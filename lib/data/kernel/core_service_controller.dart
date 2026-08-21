import 'dart:io';

import 'package:astral/data/kernel/core_host.dart';
import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral/data/services/app_settings_service.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals.dart';

/// 桌面内核服务：安装 / 启停 / 用软件携带的内核同步。
class CoreServiceController {
  CoreServiceController({
    required CoreHost host,
    required AppSettingsService settings,
    required LogService log,
  }) : _host = host,
       _settings = settings,
       _log = log;

  CoreHost get host => _host;
  final CoreHost _host;
  final AppSettingsService _settings;
  final LogService _log;

  static const _module = 'CoreService';

  final state = signal(CoreInstallState.unknown);
  final version = signal('');
  final bundledDiffers = signal(false);
  final busy = signal(false);
  final lastMessage = signal<String?>(null);

  var _environmentRepairDone = false;

  Future<void> refresh() async {
    try {
      await _host.repairBrokenCurrentEntry();
      final next = await _host.queryInstallState();
      state.value = next;
      final binary = await _host.findBinary();
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

  /// 启动时：体检 → 必要时 UAC 修复 → 同步携带内核 → 启动服务。
  /// [allowElevate] 为 false 时仅刷新状态，完整流程留到窗口就绪后执行。
  Future<void> ensureProvisioned({bool allowElevate = true}) async {
    try {
      if (!allowElevate) {
        await refresh();
        return;
      }

      await _ensureEnvironmentHealthy(allowElevate: true);

      final bundled = await _host.materializeBundledProgram();
      if (bundled != null) {
        await _host.ensureRuntimeSidecars(nearProgram: bundled);
      }
      await refresh();

      if (_settings.getCoreServiceOptOut()) {
        await _startIfStopped();
        return;
      }

      if (bundled == null) {
        await _startIfStopped();
        if (!state.value.isInstalled) {
          lastMessage.value = '未找到随软件携带的 astral-core';
          _log.warn(_module, lastMessage.value!);
        }
        return;
      }

      if (!state.value.isInstalled || bundledDiffers.value) {
        lastMessage.value = await _guard(
          () => _syncBundledUnlocked(program: bundled),
        );
        return;
      }

      await _host.ensureRuntimeSidecars(nearProgram: bundled);
      await _startIfStopped();
    } catch (e) {
      _log.warn(_module, '自动准备内核失败: $e');
      lastMessage.value = '$e';
    }
  }

  Future<void> _startIfStopped() async {
    if (state.value != CoreInstallState.stopped) return;
    lastMessage.value = await start();
  }

  /// 自动修复 legacy 服务/目录/登记；需要时通过 UAC 提权卸载旧服务。
  Future<bool> _ensureEnvironmentHealthy({required bool allowElevate}) async {
    if (!allowElevate) return false;
    if (_environmentRepairDone) {
      final report = await _host.serviceDoctor();
      return report?.needsRepair != true;
    }

    final report = await _host.serviceDoctor();
    if (report == null || !report.needsRepair) {
      _environmentRepairDone = true;
      return true;
    }

    _log.info(_module, '正在自动修复服务环境…');
    final repair = await _host.serviceRepair(
      migrateLegacyData: true,
      elevateIfNeeded: true,
    );
    _environmentRepairDone = true;

    final after = await _host.serviceDoctor();
    if (after?.needsRepair == true) {
      _log.warn(_module, '仍有待处理项: ${after!.issues.join(' · ')}');
      return false;
    }
    if (repair?.changed == true) {
      _log.info(_module, '服务环境已自动修复');
    } else {
      _log.info(_module, '服务环境已就绪');
    }
    return true;
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
    return (await _host.queryInstallState()).isInstalled;
  }

  Future<String> start() => _guard(() async {
    final binary = await _host.findBinary();
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

  /// 用 GUI 携带的内核安装或覆盖系统服务。
  Future<String> syncFromBundled({String? program}) => _guard(
    () => _syncBundledUnlocked(program: program),
    reconnect: true,
  );

  Future<String> install({String? program}) => syncFromBundled(program: program);

  Future<String> _syncBundledUnlocked({String? program}) async {
    await _ensureEnvironmentHealthy(allowElevate: true);
    await _host.repairBrokenCurrentEntry();

    final bundled = program ?? await _host.materializeBundledProgram();
    if (bundled == null) {
      throw StateError('未找到随软件携带的 astral-core');
    }
    await _host.ensureRuntimeSidecars(nearProgram: bundled);

    final latestState = await _host.queryInstallState();
    if (!latestState.isInstalled) {
      await _settings.setCoreServiceOptOut(false);
      if (latestState == CoreInstallState.notInstalled ||
          latestState == CoreInstallState.missingBinary) {
        await _host.stopDetachedListener();
      }
      final r = await _host.installService(binary: bundled);
      if (!await _okOrNowInstalled(r)) {
        throw StateError(r.output.isEmpty ? '安装失败' : r.output);
      }
      await _host.ensureRuntimeSidecars(nearProgram: bundled);
      return '已安装内核服务并开机自启';
    }

    final current = _host.currentProgramPath();
    if (File(current).existsSync() &&
        await _host.binariesMatch(bundled, current)) {
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
      if (!(await _host.queryInstallState()).isInstalled) {
        throw StateError(r.output.isEmpty ? '更新失败' : r.output);
      }
    } else if (!r.ok) {
      throw StateError(r.output.isEmpty ? '更新失败' : r.output);
    }
    await _host.ensureRuntimeSidecars(nearProgram: bundled);
    return '已用软件携带的内核更新服务';
  }

  /// 连接失败且像旧协议时，用携带内核覆盖服务。
  Future<bool> repairIfProtocolMismatch() async {
    if (busy.value) return false;
    try {
      final bundled = await _host.materializeBundledProgram();
      if (bundled == null) {
        _log.warn(_module, '协议不匹配，且未找到随软件携带的 astral-core');
        return false;
      }
      final current = _host.currentProgramPath();
      if (File(current).existsSync() &&
          await _host.binariesMatch(bundled, current)) {
        _log.warn(_module, '携带内核与已安装文件相同，无法用复制修复协议不匹配');
        return false;
      }
      _log.info(_module, '协议不匹配，正在用携带的内核更新服务: $bundled');
      await _syncBundledUnlocked(program: bundled);
      await refresh();
      return true;
    } catch (e) {
      _log.warn(_module, '更新内核服务失败: $e');
      return false;
    }
  }

  /// 保证 JSON-RPC 端口有进程在听。
  /// 返回本次是否新启动了进程（需多等一会再 ping）。
  Future<bool> ensureListenerRunning() async {
    final binary = await _host.findBinary();
    if (binary == null) return false;
    await _host.ensureRuntimeSidecars(nearProgram: binary);

    final installState = await _host.queryInstallState();
    switch (installState) {
      case CoreInstallState.running:
        _log.info(_module, '内核服务已在运行');
        return false;
      case CoreInstallState.stopped:
        final started = await _host.startService(binary: binary);
        if (!started.ok && !CoreHost.looksLikeAlreadyRunning(started)) {
          throw StateError(
            started.output.isEmpty ? '无法启动已安装的内核服务' : started.output,
          );
        }
        _log.info(_module, '已启动内核服务');
        return true;
      case CoreInstallState.unknown:
        final started = await _host.startService(binary: binary);
        if (started.ok || CoreHost.looksLikeAlreadyRunning(started)) {
          _log.info(_module, '已启动内核服务');
          return true;
        }
        if (!CoreHost.looksLikeNotInstalled(started)) {
          _log.warn(_module, '启动服务失败: ${started.output}');
          return false;
        }
        await _host.stopDetachedListener();
        await _host.spawnDetached(binary: binary);
        _log.info(_module, '服务未安装，已临时拉起: $binary');
        return true;
      case CoreInstallState.notInstalled:
        await _host.stopDetachedListener();
        await _host.spawnDetached(binary: binary);
        _log.info(_module, '未安装系统服务，已临时拉起: $binary');
        return true;
      case CoreInstallState.missingBinary:
        return false;
    }
  }

  Future<String> uninstall() => _guard(() async {
    await _settings.setCoreServiceOptOut(true);
    final r = await _host.uninstallService(binary: await _host.findBinary());
    if (r.ok) return '已卸载系统服务';
    await refresh();
    if (!state.value.isInstalled) return '已卸载系统服务';
    throw StateError(r.output.isEmpty ? '卸载失败' : r.output);
  });
}
