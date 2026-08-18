import 'dart:io';

import 'package:astral/data/kernel/core_host.dart';
import 'package:astral/data/kernel/core_update_service.dart';
import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral/data/services/app_settings_service.dart';
import 'package:astral/data/services/log_service.dart';
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
  final bundledDiffers = signal(false);
  final busy = signal(false);
  final lastMessage = signal<String?>(null);

  late final hasUpdate = computed(() => bundledDiffers.value);

  Future<void> refresh() async {
    try {
      final next = await _host.queryInstallState();
      state.value = next;
      final binary = await _host.findBinary(null);
      version.value = (await _host.readVersion(binary)) ?? '';
      bundledDiffers.value = await _bundledDiffersFromCurrent();
    } catch (e) {
      _log.warn(_module, '刷新服务状态失败: $e');
      state.value = CoreInstallState.unknown;
    }
  }

  Future<bool> _bundledDiffersFromCurrent() async {
    final bundled = File(_host.bundledProgramPath());
    final current = File(_host.currentProgramPath());
    if (!bundled.existsSync()) return false;
    if (!current.existsSync()) return true;
    return !await _host.binariesMatch(bundled.path, current.path);
  }

  /// 启动时：用软件携带的内核对比已安装服务，不同则复制进去。
  /// [allowElevate] 为 false 时不安装/覆盖，避免启动瞬间弹出 UAC。
  Future<void> ensureProvisioned({bool allowElevate = true}) async {
    try {
      final bundled = await _host.materializeBundledProgram();
      if (bundled != null) {
        await _host.ensureRuntimeSidecars(nearProgram: bundled);
      }
      await refresh();

      if (_settings.getCoreServiceOptOut()) {
        if (state.value == CoreInstallState.stopped) {
          lastMessage.value = await start();
        }
        return;
      }

      if (bundled == null) {
        if (state.value == CoreInstallState.stopped) {
          lastMessage.value = await start();
        } else if (!state.value.isInstalled) {
          lastMessage.value = '未找到随软件携带的 astral-core';
          _log.warn(_module, lastMessage.value!);
        }
        return;
      }

      final current = _host.currentProgramPath();
      final installed = state.value.isInstalled;
      final currentMissing = !File(current).existsSync();
      final differs =
          currentMissing || !await _host.binariesMatch(bundled, current);

      if (!installed || differs) {
        if (!allowElevate) return;
        lastMessage.value = await syncFromBundled(program: bundled);
        return;
      }

      await _copySidecars(bundled);
      if (state.value == CoreInstallState.stopped) {
        lastMessage.value = await start();
      }
    } catch (e) {
      _log.warn(_module, '自动准备内核失败: $e');
      lastMessage.value = '$e';
    }
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
    final next = await _host.queryInstallState();
    return next.isInstalled;
  }

  Future<String> start() => _guard(() async {
    final binary = await _host.findBinary(null);
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
    final r = await _host.stopService(binary: await _host.findBinary(null));
    if (!r.ok) throw StateError(r.output.isEmpty ? '停止失败' : r.output);
    return '内核服务已停止';
  });

  Future<String> install({String? program}) => _guard(() async {
    return _installUnlocked(program: program);
  }, reconnect: true);

  Future<String> _installUnlocked({String? program}) async {
    final binary = program ?? await _host.materializeBundledProgram();
    if (binary == null) {
      throw StateError('未找到随软件携带的 astral-core');
    }
    await _settings.setCoreServiceOptOut(false);
    if (state.value == CoreInstallState.notInstalled ||
        state.value == CoreInstallState.missingBinary) {
      await _host.stopDetachedListener(CoreHost.defaultListen);
    }
    final r = await _host.installService(
      binary: binary,
      listen: CoreHost.defaultListen,
    );
    if (!await _okOrNowInstalled(r)) {
      throw StateError(r.output.isEmpty ? '安装失败' : r.output);
    }
    await _copySidecars(binary);
    return '已安装内核服务并开机自启';
  }

  /// 用 GUI 旁边携带的内核安装或覆盖系统服务。
  Future<String> syncFromBundled({String? program}) => _guard(() async {
    final bundled = program ?? await _host.materializeBundledProgram();
    if (bundled == null) {
      throw StateError('未找到随软件携带的 astral-core');
    }
    await _host.ensureRuntimeSidecars(nearProgram: bundled);
    final latestState = await _host.queryInstallState(configured: bundled);
    if (!latestState.isInstalled) {
      return _installUnlocked(program: bundled);
    }
    final current = _host.currentProgramPath();
    if (File(current).existsSync() &&
        await _host.binariesMatch(bundled, current)) {
      await _copySidecars(bundled);
      if (latestState == CoreInstallState.stopped) {
        final started = await _host.startService(binary: bundled);
        if (!started.ok && !CoreHost.looksLikeAlreadyRunning(started)) {
          throw StateError(started.output.isEmpty ? '启动失败' : started.output);
        }
      }
      return '内核已与软件携带版本一致';
    }
    final r = await _host.updateService(newProgram: bundled, binary: bundled);
    if (!r.ok && Platform.isWindows) {
      final after = await _host.queryInstallState(configured: bundled);
      if (!after.isInstalled) {
        throw StateError(r.output.isEmpty ? '更新失败' : r.output);
      }
    } else if (!r.ok) {
      throw StateError(r.output.isEmpty ? '更新失败' : r.output);
    }
    await _copySidecars(bundled);
    return '已用软件携带的内核更新服务';
  }, reconnect: true);

  Future<String> uninstall() => _guard(() async {
    await _settings.setCoreServiceOptOut(true);
    final r = await _host.uninstallService(
      binary: await _host.findBinary(null),
    );
    if (r.ok) return '已卸载系统服务';
    await refresh();
    if (!state.value.isInstalled) return '已卸载系统服务';
    throw StateError(r.output.isEmpty ? '卸载失败' : r.output);
  });

  /// 未安装则用携带的内核安装，已安装则卸载。
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
    await _settings.setCoreServiceOptOut(false);
    final latestState = await _host.queryInstallState(configured: exe);
    if (latestState == CoreInstallState.notInstalled ||
        latestState == CoreInstallState.missingBinary) {
      await _host.stopDetachedListener(CoreHost.defaultListen);
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
        listen: CoreHost.defaultListen,
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
