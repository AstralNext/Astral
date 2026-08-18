import 'dart:io';

import 'package:astral/data/kernel/core_host.dart';
import 'package:astral/data/kernel/core_update_service.dart';
import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral/data/services/app_settings_service.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral/data/state/settings_state.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals.dart';

/// 桌面内核服务的安装 / 启停 / 自启 / 更新。
class CoreServiceController {
  CoreServiceController({
    required CoreHost host,
    required CoreUpdateService updater,
    required AppSettingsService settings,
    required LogService log,
  }) : _host = host,
       _updater = updater,
       _settings = settings,
       _log = log;

  final CoreHost _host;
  final CoreUpdateService _updater;
  final AppSettingsService _settings;
  final LogService _log;

  static const _module = 'CoreService';

  final state = signal(CoreInstallState.unknown);
  final version = signal('');
  final latestVersion = signal<String?>(null);
  final busy = signal(false);
  final lastMessage = signal<String?>(null);

  late final hasUpdate = computed(() {
    final latest = latestVersion.value;
    if (latest == null) return false;
    return _updater.isNewer(latest, version.value);
  });

  Future<void> refresh() async {
    try {
      final next = await _host.queryInstallState(
        configured: _settings.getCoreBinaryPath(),
      );
      state.value = next;
      final binary = await _host.findBinary(_settings.getCoreBinaryPath());
      version.value = (await _host.readVersion(binary)) ?? '';
    } catch (e) {
      _log.warn(_module, '刷新服务状态失败: $e');
      state.value = CoreInstallState.unknown;
    }
  }

  /// 启动时自动准备。
  /// [allowNetwork] 为 false 时只拉起已安装服务，避免把首次启动卡在下载 / UAC。
  Future<void> ensureProvisioned({bool allowNetwork = true}) async {
    await refresh();
    try {
      if (state.value == CoreInstallState.stopped) {
        lastMessage.value = await start();
        return;
      }
      if (state.value == CoreInstallState.running) return;
      if (!allowNetwork) return;

      final optedOut = _settings.getCoreServiceOptOut();
      if (state.value == CoreInstallState.unknown) {
        await _resolveUnknown(optedOut: optedOut);
        return;
      }
      if (optedOut) {
        if (state.value == CoreInstallState.missingBinary) {
          lastMessage.value = await downloadLatest();
        }
        return;
      }
      lastMessage.value = await install();
      await refresh();
      if (state.value == CoreInstallState.stopped) {
        lastMessage.value = await start();
      }
    } catch (e) {
      _log.warn(_module, '自动准备内核失败: $e');
      lastMessage.value = '$e';
    }
  }

  Future<void> _resolveUnknown({required bool optedOut}) async {
    final binary = await _host.findBinary(_settings.getCoreBinaryPath());
    if (binary != null) {
      final started = await _host.startService(binary: binary);
      if (started.ok || CoreHost.looksLikeAlreadyRunning(started)) {
        await refresh();
        return;
      }
      if (!CoreHost.looksLikeNotInstalled(started)) {
        _log.warn(_module, '状态未知且启动失败，跳过自动安装: ${started.output}');
        return;
      }
    }
    if (optedOut) {
      if (binary == null) lastMessage.value = await downloadLatest();
      return;
    }
    lastMessage.value = await install();
  }

  Future<String> _guard(
    Future<String> Function() action, {
    bool reconnect = false,
  }) async {
    if (busy.value) return '正在执行其它操作';
    busy.value = true;
    try {
      final msg = await action();
      lastMessage.value = msg;
      await refresh();
      if (reconnect) await _reconnectEngine();
      return msg;
    } catch (e) {
      lastMessage.value = '$e';
      await refresh();
      rethrow;
    } finally {
      busy.value = false;
    }
  }

  bool get _wantPrerelease => _settings.getUpdateBetaChannel();

  Future<void> _persistBinaryPath(String path) async {
    await _settings.setCoreBinaryPath(path);
    if (GetIt.I.isRegistered<SettingsState>()) {
      GetIt.I<SettingsState>().coreBinaryPath.value = path;
    }
  }

  Future<void> _reconnectEngine() async {
    if (!GetIt.I.isRegistered<KernelEngine>()) return;
    final engine = GetIt.I<KernelEngine>();
    if (engine.mode != KernelMode.service) return;
    try {
      await engine.ensureReady();
    } catch (e) {
      _log.warn(_module, '重连内核失败: $e');
    }
  }

  /// Windows UAC 提权后拿不到子进程 stdout，用 status 复核。
  Future<bool> _okOrNowInstalled(CoreCliResult result) async {
    if (result.ok) return true;
    if (!Platform.isWindows) return false;
    final next = await _host.queryInstallState(
      configured: _settings.getCoreBinaryPath(),
    );
    return next.isInstalled;
  }

  Future<String> start() => _guard(() async {
    final binary = await _host.findBinary(_settings.getCoreBinaryPath());
    if (binary == null) {
      throw StateError('未找到 astral-core，请先安装服务');
    }
    if (!state.value.isInstalled) {
      throw StateError('尚未安装系统服务');
    }
    final r = await _host.startService(binary: binary);
    if (!r.ok && !CoreHost.looksLikeAlreadyRunning(r)) {
      throw StateError(r.output.isEmpty ? '启动失败' : r.output);
    }
    return '内核服务已启动';
  }, reconnect: true);

  Future<String> stop() => _guard(() async {
    final r = await _host.stopService(
      binary: await _host.findBinary(_settings.getCoreBinaryPath()),
    );
    if (!r.ok) throw StateError(r.output.isEmpty ? '停止失败' : r.output);
    return '内核服务已停止';
  });

  Future<String> install({String? program}) => _guard(() async {
    var binary =
        program ?? await _host.findBinary(_settings.getCoreBinaryPath());
    if (binary == null) {
      binary = await _downloadLatestUnlocked();
    }
    if (_settings.getCoreBinaryPath().trim().isEmpty) {
      await _persistBinaryPath(binary);
    }
    await _settings.setCoreServiceOptOut(false);
    if (state.value == CoreInstallState.notInstalled ||
        state.value == CoreInstallState.missingBinary) {
      await _host.stopDetachedListener(_settings.getCoreTarget());
    }
    final r = await _host.installService(
      binary: binary,
      listen: _settings.getCoreTarget(),
    );
    if (!await _okOrNowInstalled(r)) {
      throw StateError(r.output.isEmpty ? '安装失败' : r.output);
    }
    await _copySidecars(binary);
    return '已安装内核服务并开机自启';
  }, reconnect: true);

  Future<String> uninstall() => _guard(() async {
    await _settings.setCoreServiceOptOut(true);
    final r = await _host.uninstallService(
      binary: await _host.findBinary(_settings.getCoreBinaryPath()),
    );
    if (r.ok) return '已卸载系统服务';
    await refresh();
    if (!state.value.isInstalled) return '已卸载系统服务';
    throw StateError(r.output.isEmpty ? '卸载失败' : r.output);
  });

  /// 未安装则安装（必要时先下载），已安装则卸载。
  Future<String> toggleInstall() {
    if (state.value.isInstalled) return uninstall();
    return install();
  }

  Future<String> downloadLatest() => _guard(() async {
    final exe = await _downloadLatestUnlocked();
    return '已下载内核到 $exe';
  });

  Future<String> _downloadLatestUnlocked() async {
    final release = await _updater.fetchLatest(
      includePrereleases: _wantPrerelease,
    );
    if (release == null) {
      throw StateError('无法获取当前平台的 astral-core 发行包');
    }
    final exe = await _updater.downloadRelease(release);
    await _persistBinaryPath(exe);
    latestVersion.value = release.version;
    await _updater.copySidecarsNextTo(exe);
    return exe;
  }

  Future<String> downloadAndInstall() => install();

  Future<String> checkUpdate({bool applyIfNewer = false}) async {
    final current = version.value;
    final release = await _updater.fetchLatest(
      includePrereleases: _wantPrerelease,
    );
    if (release == null) {
      throw StateError('无法获取 astral-core 发行版');
    }
    latestVersion.value = release.version;
    if (!_updater.isNewer(release.version, current)) {
      return '内核已是最新 ${release.version}';
    }
    if (!applyIfNewer) {
      return '发现内核新版本 ${release.version}';
    }
    if (!state.value.isInstalled && _settings.getCoreServiceOptOut()) {
      return '发现内核新版本 ${release.version}（未安装服务，未自动安装）';
    }
    return applyUpdate(release);
  }

  Future<String> applyUpdate([CoreReleaseInfo? known]) => _guard(() async {
    final release =
        known ??
        await _updater.fetchLatest(includePrereleases: _wantPrerelease);
    if (release == null) {
      throw StateError('无法获取 astral-core 发行版');
    }
    latestVersion.value = release.version;
    if (!_updater.isNewer(release.version, version.value) &&
        state.value.isInstalled) {
      return '内核已是最新 ${release.version}';
    }
    final exe = await _updater.downloadRelease(release);
    await _persistBinaryPath(exe);
    await _settings.setCoreServiceOptOut(false);
    final latestState = await _host.queryInstallState(configured: exe);
    if (latestState == CoreInstallState.notInstalled ||
        latestState == CoreInstallState.missingBinary) {
      await _host.stopDetachedListener(_settings.getCoreTarget());
    }
    if (latestState.isInstalled) {
      final r = await _host.updateService(newProgram: exe, binary: exe);
      if (!r.ok && Platform.isWindows) {
        final after = await _host.queryInstallState(configured: exe);
        if (!after.isInstalled) {
          throw StateError(r.output.isEmpty ? '更新失败' : r.output);
        }
      } else if (!r.ok) {
        throw StateError(r.output.isEmpty ? '更新失败' : r.output);
      }
    } else {
      final r = await _host.installService(
        binary: exe,
        listen: _settings.getCoreTarget(),
      );
      if (!await _okOrNowInstalled(r)) {
        throw StateError(r.output.isEmpty ? '安装失败' : r.output);
      }
    }
    await _copySidecars(exe);
    return '内核已更新到 ${release.version}';
  }, reconnect: true);

  Future<void> _copySidecars(String exe) async {
    await _updater.copySidecarsNextTo(exe);
    await _updater.copySidecarsNextTo(_host.currentProgramPath());
  }
}
