import 'dart:async';
import 'dart:io';

import 'package:astral/data/kernel/core_host.dart';
import 'package:astral/data/kernel/core_rpc_client.dart';
import 'package:astral/data/kernel/core_service_controller.dart';
import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral_rust_core/astral_rust_core.dart'
    show KVNetworkStatus, KVNodeInfo;

class ServiceKernelEngine implements KernelEngine {
  ServiceKernelEngine({
    required CoreHost host,
    required CoreServiceController core,
    required LogService log,
  }) : _host = host,
       _core = core,
       _log = log;

  final CoreHost _host;
  final CoreServiceController _core;
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

  /// UDP 发现：发 `ASTRAL_DISCOVER` → 内核回 `ASTRAL_CORE <addr>`。
  Future<String?> _udpDiscover() async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final target = InternetAddress.loopbackIPv4;
      sock.send('ASTRAL_DISCOVER'.codeUnits, target, 50050);
      final result = await sock.timeout(const Duration(milliseconds: 500)).firstWhere(
        (e) => e == RawSocketEvent.read,
      );
      if (result == RawSocketEvent.read) {
        final dg = sock.receive();
        if (dg != null) {
          final text = String.fromCharCodes(dg.data);
          if (text.startsWith('ASTRAL_CORE ')) {
            return text.substring('ASTRAL_CORE '.length).trim();
          }
        }
      }
    } catch (_) {}
    finally {
      sock?.close();
    }
    return null;
  }

  Future<void> _ensureReadyBody() async {
    // 快速路径：已有客户端且仍可 ping。
    if (_client != null) {
      try {
        if (await _ping()) {
          _connected = true;
          _statusMessage = '已连接 ${CoreHost.listenAddress}';
          return;
        }
      } catch (_) {}
      await _closeClient();
    }

    // UDP 服务发现：一次 UDP 往返 <1ms，比盲猜 TCP 快得多。
    final discovered = await _udpDiscover();
    if (discovered != null) {
      _log.info(_module, '通过 UDP 发现内核: $discovered');
      if (await _tryConnectTo(discovered)) return;
    }

    // 回退：直接尝试默认地址。
    if (await _tryConnect()) return;
    Object? lastError = _lastConnectError;

    // 协议不匹配 → 用携带内核覆盖后重连。
    if (CoreHost.looksLikeProtocolMismatch(lastError ?? '')) {
      _statusMessage = '正在用软件携带的内核更新服务';
      if (await _core.repairIfProtocolMismatch()) {
        if (await _waitForConnect(maxTries: 20, delayMs: 150)) return;
        lastError = _lastConnectError ?? lastError;
      }
    }

    if (await _host.findBinary() == null) {
      _connected = false;
      _statusMessage = '未找到随软件携带的 astral-core';
      _log.warn(_module, _statusMessage!);
      return;
    }

    // 确保有进程在监听。
    final bool launchedNow;
    try {
      launchedNow = await _core.ensureListenerRunning();
    } catch (e) {
      _connected = false;
      _statusMessage = '无法启动 astral-core: $e';
      _log.warn(_module, _statusMessage!);
      return;
    }

    if (await _waitForConnect(
      maxTries: launchedNow ? 30 : 4,
      delayMs: launchedNow ? 150 : 200,
    )) {
      return;
    }
    lastError = _lastConnectError ?? lastError;

    _connected = false;
    _statusMessage = CoreHost.looksLikeProtocolMismatch(lastError ?? '')
        ? '本机内核协议过旧，无法连接 ${CoreHost.listenAddress}。请在设置中同步内核版本'
        : '无法连接到 ${CoreHost.listenAddress}';
    _log.warn(_module, _statusMessage!);
  }

  Future<bool> _waitForConnect({
    required int maxTries,
    int delayMs = 150,
  }) async {
    for (var i = 0; i < maxTries; i++) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (await _tryConnect()) return true;
    }
    return false;
  }

  Future<bool> _ping([CoreRpcClient? client]) async {
    final c = client ?? _client;
    if (c == null) return false;
    final res = await c.call('ping', timeout: const Duration(seconds: 3));
    return res is Map && res['ok'] == true;
  }

  Future<bool> _tryConnect() => _tryConnectTo(CoreHost.listenAddress);

  Future<bool> _tryConnectTo(String target) async {
    await _closeClient();
    _lastConnectError = null;
    final client = CoreRpcClient(
      target: target,
      timeout: const Duration(seconds: 5),
    );
    try {
      if (await _ping(client)) {
        _client = client;
        _connected = true;
        _statusMessage = '已连接 $target';
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
      return KernelInstanceInspect(
        running: up,
        startedAt: parseKernelStartedAt(summary['started_at_unix_ms']),
      );
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
    return KVNetworkStatus(totalNodes: BigInt.from(peers.length), nodes: peers);
  }

  @override
  Future<List<KernelLogEvent>> recentCoreLogs({
    int after = 0,
    int limit = 500,
    String? instanceId,
  }) async {
    final params = <String, dynamic>{
      'after': after,
      'limit': limit,
      if (instanceId != null && instanceId.trim().isNotEmpty)
        'instance_id': instanceId.trim(),
    };
    final res = await _requireClient.call('logs.recent', params: params);
    final map = _asMap(res);
    final lines = map['lines'] as List? ?? const [];
    return [
      for (final raw in lines)
        KernelLogEvent(
          instanceId: '${_asMap(raw)['instance_id'] ?? ''}',
          message: _formatLogLine(
            '${_asMap(raw)['level'] ?? ''}',
            '${_asMap(raw)['target'] ?? ''}',
            '${_asMap(raw)['message'] ?? ''}',
          ),
        ),
    ];
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
          break;
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
            startedAt: parseKernelStartedAt(_asMap(raw)['started_at_unix_ms']),
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
