import 'dart:async';
import 'dart:io';

import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/services/instance_catalog_service.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral/data/services/toml_config_service.dart';
import 'package:astral/data/services/vpn_manager.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:get_it/get_it.dart';

/// 实例启停：全局串行；Android 同时只跑一个实例。
class InstanceConnectionService {
  InstanceConnectionService(this._toml, this._runtimeStore, this._log);

  final TomlConfigService _toml;
  final InstanceRuntimeStore _runtimeStore;
  final LogService _log;

  KernelEngine get _engine => GetIt.I<KernelEngine>();

  Future<void> _queue = Future<void>.value();
  var _vpnEpoch = 0;

  /// 最近一次启动的用户可见备注（如未挂 VPN）；读取后清空。
  String? _lastStartNote;

  static const _module = 'InstanceConnectionService';

  String? consumeLastStartNote() {
    final note = _lastStartNote;
    _lastStartNote = null;
    return note;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _queue = _queue.catchError((_) {}).then((_) async {
      try {
        done.complete(await action());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  VpnManager? get _vpn {
    if (!Platform.isAndroid || !GetIt.I.isRegistered<VpnManager>()) {
      return null;
    }
    return GetIt.I<VpnManager>();
  }

  Future<bool> start({
    required String path,
    required String configToml,
    String? name,
  }) {
    return _enqueue(
      () => _start(path: path, configToml: configToml, name: name),
    );
  }

  Future<bool> startFromFile({required String path, String? name}) {
    return _enqueue(() async {
      final toml = await GetIt.I<InstanceCatalogService>().readToml(path);
      if (toml == null || toml.isEmpty) {
        _log.error(_module, '配置不存在或为空', instancePath: path);
        return false;
      }
      return _start(path: path, configToml: toml, name: name);
    });
  }

  Future<bool> stop({required String path, String? name}) {
    return _enqueue(() => _stop(path: path, name: name));
  }

  Future<void> stopAll() {
    return _enqueue(() async {
      final paths = <String>{
        ..._runtimeStore.instanceIdByPath.value.keys,
        ..._runtimeStore.startingPaths.value,
      };
      for (final path in paths) {
        await _stop(path: path);
      }
      await _vpn?.stop();
    });
  }

  /// Poll 发现进程已死：关 VPN，并 closeInstance（map 已由 store 清掉）。
  Future<void> handleNaturalExit(String path, String instanceId) {
    return _enqueue(() async {
      _vpnEpoch++;
      await _vpn?.stop(instanceId: instanceId);
      try {
        await _engine.closeInstance(instanceId);
      } catch (e) {
        _log.warn(_module, '自然退出清理失败: $e', instancePath: path);
      }
      _log.info(_module, '实例已退出: $path', instancePath: path);
    });
  }

  /// 系统撤销 VpnService 时停掉对应实例。
  Future<void> handleVpnRevokedBySystem(String instanceId) {
    return _enqueue(() async {
      final path = _runtimeStore.pathByInstanceId.value[instanceId];
      _log.warn(_module, '系统撤销 VPN，停止实例', instancePath: path);
      if (path != null) {
        await _stop(path: path);
      } else {
        _vpnEpoch++;
        try {
          await _engine.closeInstance(instanceId);
        } catch (e) {
          _log.warn(_module, '撤销 VPN 后清理失败: $e');
        }
      }
    });
  }

  Future<bool> _start({
    required String path,
    required String configToml,
    String? name,
  }) async {
    _lastStartNote = null;
    if (_runtimeStore.isRunning(path) || _runtimeStore.isStarting(path)) {
      return false;
    }
    if (Platform.isAndroid) {
      final busy =
          _runtimeStore.instanceIdByPath.value.isNotEmpty ||
          _runtimeStore.startingPaths.value.any((p) => p != path);
      if (busy) {
        _log.error(_module, '请先停止其它实例（本机同时只跑一个）', instancePath: path);
        return false;
      }
    }

    _runtimeStore.setStarting(path, true);
    _log.info(_module, '正在启动: ${name ?? path}', instancePath: path);
    try {
      final vpn = _vpn;
      if (vpn != null && !await vpn.ensurePermission()) {
        _log.error(_module, 'VPN 权限未授予', instancePath: path);
        return false;
      }

      final launched = await _launch(path, configToml, name);
      if (launched == null) return false;

      _runtimeStore.setRunning(
        path,
        launched.id,
        startedAt: launched.startedAt,
      );
      _log.info(_module, '已启动: ${name ?? path}', instancePath: path);

      if (vpn != null) {
        final epoch = _vpnEpoch;
        final vpnOk = await _attachVpn(path, launched.id, configToml, epoch);
        // 仅「需要挂 TUN 却失败」才停实例；无静态 IP 时故意跳过 VPN，实例继续跑。
        if (!vpnOk &&
            epoch == _vpnEpoch &&
            _runtimeStore.getInstanceId(path) == launched.id) {
          _log.warn(_module, 'VPN 未就绪，已停止实例', instancePath: path);
          await _stop(path: path, name: name);
          return false;
        }
      } else if (Platform.isIOS) {
        _lastStartNote = '已启动（本平台未挂系统 VPN）';
        _log.warn(_module, 'iOS 无系统 VPN/TUN', instancePath: path);
      }
      return true;
    } catch (e) {
      _log.error(_module, '启动失败: $e', instancePath: path);
      return false;
    } finally {
      _runtimeStore.setStarting(path, false);
    }
  }

  Future<({String id, DateTime? startedAt})?> _launch(
    String path,
    String configToml,
    String? name,
  ) async {
    String? id;
    var ok = false;
    DateTime? startedAt;
    try {
      await _engine.ensureReady();
      id = await _engine.createInstance(
        configToml: configToml,
        sourcePath: path,
        name: name,
      );
      _runtimeStore.bindInstanceLogRoute(path, id);

      final deadline = DateTime.now().add(const Duration(seconds: 45));
      var delayMs = 400;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        delayMs = 300;
        final probe = await _engine.inspectInstance(id);
        if (probe.failed) {
          _log.error(
            _module,
            '启动失败: ${probe.errorMessage}',
            instancePath: path,
          );
          return null;
        }
        if (probe.running) {
          ok = true;
          startedAt = probe.startedAt;
          return (id: id, startedAt: startedAt);
        }
      }
      _log.error(_module, '启动失败: 未进入运行', instancePath: path);
      return null;
    } finally {
      if (id != null && !ok) {
        try {
          await _engine.closeInstance(id);
        } catch (_) {}
        _runtimeStore.unbindInstanceLogRoute(id);
      }
    }
  }

  Future<bool> _stop({required String path, String? name}) async {
    _vpnEpoch++;
    final id = _runtimeStore.getInstanceId(path);
    try {
      await _vpn?.stop(instanceId: id);
      if (id != null) {
        try {
          await _engine.closeInstance(id);
        } catch (e) {
          _log.warn(_module, 'closeInstance: $e', instancePath: path);
        }
      }
      if (_runtimeStore.isRunning(path) || id != null) {
        _runtimeStore.setStopped(path);
      }
      _log.info(_module, '已停止: ${name ?? path}', instancePath: path);
      return true;
    } catch (e) {
      _log.error(_module, '停止失败: $e', instancePath: path);
      return false;
    }
  }

  /// 挂载 Android VPN。
  ///
  /// - 无顶层静态 `ipv4`：跳过 TUN，返回 `true`（实例继续跑）。
  /// - 有 `ipv4` 但 `vpn.start` 失败 / 中途所有权失效：返回 `false`。
  Future<bool> _attachVpn(
    String path,
    String instanceId,
    String configToml,
    int epoch,
  ) async {
    final vpn = _vpn;
    if (vpn == null) return true;

    bool alive() =>
        epoch == _vpnEpoch &&
        _runtimeStore.getInstanceId(path) == instanceId &&
        _runtimeStore.isRunning(path);

    final ipv4 = _toml.readIpv4(configToml);
    if (ipv4 == null || ipv4.isEmpty || !_usableVpnIp(ipv4)) {
      _log.warn(
        _module,
        '未挂系统 VPN：配置无可用顶层静态 ipv4（dhcp 模式）。'
        '需要虚拟网卡时请设置 ipv4 并 dhcp = false',
        instancePath: path,
      );
      _lastStartNote = '已启动，但未挂系统 VPN（无静态 ipv4）';
      return true;
    }

    if (!alive()) {
      await vpn.stop(instanceId: instanceId);
      return false;
    }

    final ok = await vpn.start(instanceId: instanceId, ipv4Addr: ipv4);
    if (!alive()) {
      await vpn.stop(instanceId: instanceId);
      return false;
    }
    if (!ok) {
      _log.error(_module, 'VPN 启动失败', instancePath: path);
    }
    return ok;
  }

  bool _usableVpnIp(String raw) {
    final ip = raw.trim().split('/').first;
    if (ip.isEmpty || ip == '0.0.0.0') return false;
    if (ip.startsWith('0.')) return false;
    return true;
  }
}
