import 'dart:async';

import 'package:astral/data/kernel/core_host.dart';
import 'package:astral/data/kernel/core_rpc_client.dart';
import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral/data/services/app_settings_service.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral_rust_core/astral_rust_core.dart'
    show KVNetworkStatus, KVNodeInfo;

class ServiceKernelEngine implements KernelEngine {
  ServiceKernelEngine({
    required CoreHost host,
    required AppSettingsService settings,
    required LogService log,
  }) : _host = host,
       _settings = settings,
       _log = log;

  final CoreHost _host;
  final AppSettingsService _settings;
  final LogService _log;

  CoreRpcClient? _client;
  var _connected = false;
  String? _statusMessage = '未连接';
  Future<void>? _readyOp;
  Object? _lastConnectError;

  static const _module = 'ServiceKernel';

  @override
  KernelMode get mode => KernelMode.service;

  @override
  bool get connected => _connected;

  @override
  bool get stopsInstancesOnExit => false;

  @override
  String? get statusMessage => _statusMessage;

  CoreRpcClient get _requireClient {
    final client = _client;
    if (client == null || !_connected) {
      throw StateError(_statusMessage ?? '内核未连接');
    }
    return client;
  }

  @override
  Future<void> ensureReady() {
    final inflight = _readyOp;
    if (inflight != null) return inflight;
    late final Future<void> started;
    started = _ensureReadyBody().whenComplete(() {
      if (identical(_readyOp, started)) _readyOp = null;
    });
    _readyOp = started;
    return started;
  }

  Future<void> _ensureReadyBody() async {
    await _host.ensureRuntimeSidecars(
      nearProgram: await _host.findBinary(_settings.getCoreBinaryPath()),
    );

    if (_client != null) {
      try {
        if (await _ping()) {
          _connected = true;
          _statusMessage = '已连接 ${_settings.getCoreTarget()}';
          return;
        }
      } catch (_) {}
      await _closeClient();
    }

    Object? lastError;
    if (await _tryConnect()) return;
    lastError = _lastConnectError;

    if (CoreHost.looksLikeProtocolMismatch(lastError ?? '')) {
      final upgraded = await _tryUpgradeMismatchedService();
      if (upgraded) {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (await _tryConnect()) return;
        }
        lastError = _lastConnectError ?? lastError;
      }
    }

    final binary = await _host.findBinary(_settings.getCoreBinaryPath());
    if (binary == null) {
      _connected = false;
      _statusMessage = '未找到 astral-core，正在等待自动下载安装';
      _log.warn(_module, _statusMessage!);
      return;
    }

    await _host.ensureRuntimeSidecars(nearProgram: binary);

    final bool launchedNow;
    try {
      launchedNow = await _ensureProcess(binary);
    } catch (e) {
      _connected = false;
      _statusMessage = '无法启动 astral-core: $e';
      _log.warn(_module, _statusMessage!);
      return;
    }

    final tries = launchedNow ? 40 : 4;
    for (var i = 0; i < tries; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await _tryConnect()) return;
      lastError = _lastConnectError ?? lastError;
    }

    _connected = false;
    _statusMessage = CoreHost.looksLikeProtocolMismatch(lastError ?? '')
        ? '本机内核协议过旧，无法连接 ${_settings.getCoreTarget()}。请更新 astral-core 服务'
        : '无法连接到 ${_settings.getCoreTarget()}';
    _log.warn(_module, _statusMessage!);
  }

  /// 已安装则 `service start`；未安装才临时拉起，避免双开。
  /// 返回是否在这次调用里新拉起了进程（需要稍等 JSON-RPC 就绪）。
  Future<bool> _ensureProcess(String binary) async {
    final installState = await _host.queryInstallState(
      configured: _settings.getCoreBinaryPath(),
    );
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
        await _host.stopDetachedListener(_settings.getCoreTarget());
        await _host.spawnDetached(
          binary: binary,
          listen: _settings.getCoreTarget(),
        );
        _log.info(_module, '服务未安装，已临时拉起: $binary');
        return true;
      case CoreInstallState.notInstalled:
        await _host.stopDetachedListener(_settings.getCoreTarget());
        await _host.spawnDetached(
          binary: binary,
          listen: _settings.getCoreTarget(),
        );
        _log.info(_module, '未安装系统服务，已临时拉起: $binary');
        return true;
      case CoreInstallState.missingBinary:
        return false;
    }
  }

  Future<bool> _ping([CoreRpcClient? client]) async {
    final c = client ?? _client;
    if (c == null) return false;
    final res = await c.call('ping', timeout: const Duration(seconds: 3));
    return res is Map && res['ok'] == true;
  }

  Future<bool> _tryUpgradeMismatchedService() async {
    final upgrade = await _host.findUpgradeBinary(
      _settings.getCoreBinaryPath(),
    );
    if (upgrade == null) {
      _log.warn(_module, '本机内核协议不匹配，且未找到更新的 astral-core');
      return false;
    }
    _log.info(_module, '协议不匹配，正在用新内核更新服务: $upgrade');
    _statusMessage = '正在更新内核服务以匹配 JSON-RPC 协议';
    final result = await _host.updateService(
      newProgram: upgrade,
      binary: upgrade,
    );
    if (!result.ok) {
      _log.warn(_module, '更新内核服务失败: ${result.output}');
      return false;
    }
    _log.info(_module, '内核服务已更新');
    await _host.ensureRuntimeSidecars(nearProgram: upgrade);
    return true;
  }

  Future<bool> _tryConnect() async {
    await _closeClient();
    _lastConnectError = null;
    final client = CoreRpcClient(
      target: _settings.getCoreTarget(),
      timeout: const Duration(seconds: 30),
    );
    try {
      if (await _ping(client)) {
        _client = client;
        _connected = true;
        _statusMessage = '已连接 ${_settings.getCoreTarget()}';
        _log.info(_module, _statusMessage!);
        return true;
      }
    } catch (e) {
      _lastConnectError = e;
      _log.warn(_module, '连接失败: $e');
    }
    client.close();
    return false;
  }

  Future<void> _closeClient() async {
    final client = _client;
    _client = null;
    _connected = false;
    client?.close();
  }

  @override
  Future<String> easytierVersion() async {
    final info = await _requireClient.call('info');
    final version = info is Map ? '${info['core_version'] ?? ''}'.trim() : '';
    return version.isEmpty ? 'astral-core' : version;
  }

  @override
  Future<String> createInstance({
    required String configToml,
    required String sourcePath,
    String? name,
  }) async {
    final res = await _requireClient.call(
      'instance.start',
      params: {
        'toml': configToml,
        'display_name': name ?? '',
        'source_path': sourcePath,
      },
      timeout: const Duration(seconds: 30),
    );
    final map = _asMap(res);
    return '${map['instance_id'] ?? ''}';
  }

  @override
  Future<void> closeInstance(String instanceId) async {
    await _requireClient.call(
      'instance.stop',
      params: {'instance_id': instanceId},
    );
  }

  @override
  Future<bool> isRunning(String instanceId) async {
    final probe = await inspectInstance(instanceId);
    return probe.running;
  }

  @override
  Future<KernelInstanceInspect> inspectInstance(String instanceId) async {
    try {
      final res = await _requireClient.call(
        'instance.get',
        params: {'instance_id': instanceId},
      );
      final summary = _asMap(_asMap(res)['summary']);
      if (summary.isEmpty) return const KernelInstanceInspect();
      final state = '${summary['state'] ?? ''}';
      if (state == 'error') {
        final err = '${summary['error_message'] ?? ''}'.trim();
        return KernelInstanceInspect(
          failed: true,
          errorMessage: err.isEmpty ? '实例错误' : err,
        );
      }
      final up =
          summary['running'] == true ||
          state == 'running' ||
          state == 'starting';
      return KernelInstanceInspect(running: up);
    } catch (_) {
      return const KernelInstanceInspect();
    }
  }

  @override
  Future<KVNetworkStatus> getNetworkStatus(String instanceId) async {
    final res = await _requireClient.call(
      'network.status',
      params: {'instance_id': instanceId},
    );
    final map = _asMap(res);
    final peers = (map['peers'] as List? ?? const [])
        .map(_asMap)
        .map(_peerToNode)
        .toList();
    if (!peers.any(_isLocalNode)) {
      peers.insert(
        0,
        _localNode(
          hostname: '${map['hostname'] ?? ''}',
          ipv4: '${map['my_ipv4'] ?? ''}',
          ipv6: '${map['my_ipv6'] ?? ''}',
        ),
      );
    }
    return KVNetworkStatus(
      totalNodes: BigInt.from(peers.length),
      nodes: peers,
    );
  }

  @override
  Stream<KernelLogEvent> subscribeCoreLogs() async* {
    var after = 0;
    while (_connected) {
      try {
        final res = await _requireClient.call(
          'logs.recent',
          params: {'after': after, 'limit': 200},
        );
        final map = _asMap(res);
        final lines = map['lines'] as List? ?? const [];
        for (final raw in lines) {
          final line = _asMap(raw);
          after = (line['seq'] as num?)?.toInt() ?? after;
          yield KernelLogEvent(
            instanceId: '${line['instance_id'] ?? ''}',
            message: _formatLogLine(
              '${line['level'] ?? ''}',
              '${line['target'] ?? ''}',
              '${line['message'] ?? ''}',
            ),
          );
        }
        after = (map['last_seq'] as num?)?.toInt() ?? after;
      } catch (e) {
        if (!_isExpectedLogSubscribeGap(e)) {
          _log.warn(_module, '无法订阅内核日志: $e');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  static bool _isExpectedLogSubscribeGap(Object e) {
    final text = e.toString();
    return text.contains('未连接') || text.contains('内核未连接');
  }

  @override
  Future<List<KernelRunningInstance>> listRunning() async {
    final res = await _requireClient.call('instance.list_meta');
    final metas = _asMap(res)['metas'] as List? ?? const [];
    return [
      for (final raw in metas)
        if (_metaLooksAlive(_asMap(raw)))
          KernelRunningInstance(
            instanceId: '${_asMap(raw)['instance_id'] ?? ''}',
            sourcePath: '${_asMap(raw)['source_path'] ?? ''}',
          ),
    ];
  }

  static bool _metaLooksAlive(Map<String, dynamic> meta) {
    final state = '${meta['state'] ?? ''}';
    if (state == 'error' || state == 'stopped') {
      return false;
    }
    return meta['running'] == true || state == 'running' || state == 'starting';
  }

  @override
  Future<void> dispose() async {
    _statusMessage = '已断开';
    await _closeClient();
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

String _formatLogLine(String level, String target, String message) {
  final body = message.trim().isEmpty ? target.trim() : message.trim();
  final lv = level.trim();
  if (lv.isEmpty) return body;
  return '[$lv] $body';
}

bool _isLocalNode(KVNodeInfo node) {
  final conn = node.connType.trim().toLowerCase();
  return node.cost == 0 || conn == 'local' || node.peerId == 0;
}

KVNodeInfo _peerToNode(Map<String, dynamic> peer) {
  final conn = '${peer['conn_type'] ?? ''}'.trim();
  final cost = switch (conn.toLowerCase()) {
    'local' => 0,
    'p2p' => 1,
    'relay' => 2,
    _ => 1,
  };
  return KVNodeInfo(
    peerId: int.tryParse('${peer['peer_id'] ?? ''}') ?? 0,
    hostname: '${peer['hostname'] ?? ''}',
    ipv4: '${peer['ipv4'] ?? ''}',
    ipv6: '${peer['ipv6'] ?? ''}',
    latencyMs: (peer['latency_ms'] as num?)?.toDouble() ?? 0,
    nat: '',
    hops: const [],
    lossRate: () {
      final loss = (peer['loss_percent'] as num?)?.toDouble() ?? 0;
      return loss > 1 ? loss / 100.0 : loss;
    }(),
    connections: const [],
    tunnelProto: '',
    connType: conn,
    rxBytes: BigInt.parse('${peer['rx_bytes'] ?? 0}'),
    txBytes: BigInt.parse('${peer['tx_bytes'] ?? 0}'),
    version: '',
    cost: cost,
    remoteStaticPubkeyB64: '',
    isCredentialPeer: false,
  );
}

KVNodeInfo _localNode({
  required String hostname,
  required String ipv4,
  required String ipv6,
}) {
  return KVNodeInfo(
    peerId: 0,
    hostname: hostname.trim().isEmpty ? '本机' : hostname.trim(),
    ipv4: ipv4,
    ipv6: ipv6,
    latencyMs: 0,
    nat: '',
    hops: const [],
    lossRate: 0,
    connections: const [],
    tunnelProto: '-',
    connType: 'local',
    rxBytes: BigInt.zero,
    txBytes: BigInt.zero,
    version: '',
    cost: 0,
    remoteStaticPubkeyB64: '',
    isCredentialPeer: false,
  );
}
