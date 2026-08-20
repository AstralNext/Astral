import 'dart:async';

import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNetworkStatus;
import 'package:get_it/get_it.dart';
import 'package:signals/signals_core.dart';

class TrafficData {
  final int rxBytes;
  final int txBytes;
  final double rxRate;
  final double txRate;
  final List<double> rxHistory;
  final List<double> txHistory;
  final DateTime updatedAt;
  final int nodeCount;
  final double avgLatencyMs;
  final double avgLossRate;

  TrafficData({
    this.rxBytes = 0,
    this.txBytes = 0,
    this.rxRate = 0,
    this.txRate = 0,
    this.rxHistory = const [],
    this.txHistory = const [],
    DateTime? updatedAt,
    this.nodeCount = 0,
    this.avgLatencyMs = 0,
    this.avgLossRate = 0,
  }) : updatedAt = updatedAt ?? DateTime.now();

  TrafficData copyWith({
    int? rxBytes,
    int? txBytes,
    double? rxRate,
    double? txRate,
    List<double>? rxHistory,
    List<double>? txHistory,
    DateTime? updatedAt,
    int? nodeCount,
    double? avgLatencyMs,
    double? avgLossRate,
  }) {
    return TrafficData(
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
      rxRate: rxRate ?? this.rxRate,
      txRate: txRate ?? this.txRate,
      rxHistory: rxHistory ?? this.rxHistory,
      txHistory: txHistory ?? this.txHistory,
      updatedAt: updatedAt ?? this.updatedAt,
      nodeCount: nodeCount ?? this.nodeCount,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      avgLossRate: avgLossRate ?? this.avgLossRate,
    );
  }
}

/// Aggregated metrics for dashboard cards (one compute, many subscribers).
class LiveNetworkMetrics {
  final double rxRate;
  final double txRate;
  final int nodeCount;
  final double avgLatencyMs;
  final double avgLossRate;
  final int runningCount;
  final int samplesWithNodes;
  final List<double> rxHistory;

  const LiveNetworkMetrics({
    this.rxRate = 0,
    this.txRate = 0,
    this.nodeCount = 0,
    this.avgLatencyMs = 0,
    this.avgLossRate = 0,
    this.runningCount = 0,
    this.samplesWithNodes = 0,
    this.rxHistory = const [],
  });

  static const empty = LiveNetworkMetrics();
}

class InstanceRuntimeStore {
  static const _historyLen = 60;
  static const _metricsInterval = Duration(seconds: 2);
  static const _aliveOnlyInterval = Duration(seconds: 8);

  /// 连续失败达到此次数时打 warn；不据此判定实例死亡。
  static const _degradedWarnEvery = 3;

  final _logService = GetIt.I<LogService>();
  KernelEngine get _engine => GetIt.I<KernelEngine>();
  final version = Signal<String>("");

  final instanceIdByPath = Signal<Map<String, String>>({});
  final pathByInstanceId = Signal<Map<String, String>>({});
  final startTimeByPath = Signal<Map<String, DateTime>>({});
  final startingPaths = Signal<Set<String>>({});
  final trafficByPath = Signal<Map<String, TrafficData>>({});
  final networkStatusByPath = Signal<Map<String, KVNetworkStatus>>({});

  /// Poll 发现实例已死时回调（由 [InstanceConnectionService] 关 VPN 等）。
  Future<void> Function(String path, String instanceId)? onNaturalExit;

  late final liveMetrics = computed(() {
    final running = instanceIdByPath.value;
    final map = trafficByPath.value;
    if (running.isEmpty) return LiveNetworkMetrics.empty;

    var rx = 0.0;
    var tx = 0.0;
    var nodes = 0;
    var latencySum = 0.0;
    var lossSum = 0.0;
    var samples = 0;
    List<double> rxHistory = const [];

    for (final path in running.keys) {
      final t = map[path];
      if (t == null) continue;
      rx += t.rxRate;
      tx += t.txRate;
      if (t.nodeCount > 0) {
        nodes += t.nodeCount;
        latencySum += t.avgLatencyMs;
        lossSum += t.avgLossRate;
        samples += 1;
      }
      if (t.rxHistory.length >= rxHistory.length) {
        rxHistory = t.rxHistory;
      }
    }

    return LiveNetworkMetrics(
      rxRate: rx,
      txRate: tx,
      nodeCount: nodes,
      avgLatencyMs: samples > 0 ? latencySum / samples : 0,
      avgLossRate: samples > 0 ? lossSum / samples : 0,
      runningCount: running.length,
      samplesWithNodes: samples,
      rxHistory: rxHistory,
    );
  });

  final Map<String, int> _lastRxBytes = {};
  final Map<String, int> _lastTxBytes = {};
  final Map<String, DateTime> _lastUpdateTime = {};
  final Map<String, int> _pollFailures = {};

  Timer? _sharedPollTimer;
  bool _pollInFlight = false;

  /// UI 可见时拉流量/节点指标；关掉后仍做 [isRunning] 存活探测。
  bool _metricsEnabled = true;

  StreamSubscription? _coreLogSubscription;
  Timer? _coreLogResubscribeTimer;

  InstanceRuntimeStore() {
    if (!GetIt.I.isRegistered<KernelEngine>()) return;
    final engine = GetIt.I<KernelEngine>();
    if (engine.connected) unawaited(attachKernel());
  }

  /// 内核连上后再拉版本、订日志，避免启动瞬间刷「未连接」。
  Future<void> attachKernel() async {
    if (!GetIt.I.isRegistered<KernelEngine>()) return;
    final engine = GetIt.I<KernelEngine>();
    if (!engine.connected) return;
    try {
      final v = await engine.easytierVersion();
      if (v.trim().isNotEmpty) version.value = v;
    } catch (e) {
      _logService.warn('P2P', 'easytierVersion failed: $e');
    }
    _coreLogResubscribeTimer?.cancel();
    _coreLogResubscribeTimer = null;
    await _coreLogSubscription?.cancel();
    _coreLogSubscription = null;
    _startCoreLogListener(engine);
  }

  /// [enabled] 控制指标采样；存活监控在有运行实例时始终开启。
  void setPollingEnabled(bool enabled, {bool forcePoll = false}) {
    final changed = _metricsEnabled != enabled;
    _metricsEnabled = enabled;
    if (changed) {
      _sharedPollTimer?.cancel();
      _sharedPollTimer = null;
    }
    _ensureSharedTimer();
    if (forcePoll || (changed && enabled)) {
      unawaited(_pollAll());
    }
  }

  void _startCoreLogListener(KernelEngine engine) {
    try {
      _coreLogSubscription = engine.subscribeCoreLogs().listen(
        (event) {
          final message = event.message;
          if (message.isEmpty) return;
          final instancePath = _resolveLogInstancePath(event);
          _logService.info('P2P', message, instancePath: instancePath);
        },
        onError: (Object e) {
          final text = e.toString();
          if (text.contains('UNIMPLEMENTED') ||
              text.contains('尚未实现') ||
              text.contains('CANCELLED')) {
            return;
          }
          if (text.contains('DEADLINE_EXCEEDED') ||
              text.contains('UNAVAILABLE')) {
            _scheduleCoreLogResubscribe(engine);
            return;
          }
          _logService.warn('P2P', '日志流错误: $e');
          _scheduleCoreLogResubscribe(engine);
        },
      );
    } catch (e) {
      _logService.warn('P2P', '无法订阅内核日志: $e');
    }
  }

  void _scheduleCoreLogResubscribe(KernelEngine engine) {
    if (_coreLogResubscribeTimer?.isActive ?? false) return;
    _coreLogResubscribeTimer = Timer(const Duration(seconds: 1), () {
      if (!engine.connected) return;
      unawaited(_coreLogSubscription?.cancel());
      _coreLogSubscription = null;
      _startCoreLogListener(engine);
    });
  }

  static final _instanceIdInMessage = RegExp(
    r'^\[([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\]',
  );

  String? _resolveLogInstancePath(KernelLogEvent event) {
    var instanceId = event.instanceId.trim();
    if (instanceId.isEmpty) {
      final match = _instanceIdInMessage.firstMatch(event.message.trim());
      if (match != null) {
        instanceId = match.group(1) ?? '';
      }
    }
    if (instanceId.isNotEmpty) {
      return pathByInstanceId.value[instanceId];
    }
    final running = instanceIdByPath.value;
    if (running.length == 1) {
      return running.keys.first;
    }
    return null;
  }

  /// 打开实例日志页时，从内核缓冲补拉历史。
  Future<void> importKernelLogsForInstance({
    required String instancePath,
    required String instanceId,
  }) async {
    if (!_engine.connected) return;
    try {
      final lines = await _engine.recentCoreLogs(
        instanceId: instanceId,
        limit: 500,
      );
      for (final line in lines) {
        if (line.message.isEmpty) continue;
        _logService.info('P2P', line.message, instancePath: instancePath);
      }
    } catch (e) {
      _logService.warn('P2P', '拉取内核历史日志失败: $e');
    }
  }

  void setStarting(String path, bool starting) {
    final set = Set<String>.from(startingPaths.value);
    if (starting) {
      set.add(path);
    } else {
      set.remove(path);
    }
    startingPaths.value = set;
  }

  void bindInstanceLogRoute(String path, String instanceId) {
    final paths = Map<String, String>.from(pathByInstanceId.value);
    paths[instanceId] = path;
    pathByInstanceId.value = paths;
  }

  void unbindInstanceLogRoute(String instanceId) {
    final paths = Map<String, String>.from(pathByInstanceId.value);
    paths.remove(instanceId);
    pathByInstanceId.value = paths;
  }

  void setRunning(String path, String instanceId, {DateTime? startedAt}) {
    final ids = Map<String, String>.from(instanceIdByPath.value);
    final paths = Map<String, String>.from(pathByInstanceId.value);
    final times = Map<String, DateTime>.from(startTimeByPath.value);
    ids[path] = instanceId;
    paths[instanceId] = path;
    if (startedAt != null) {
      times[path] = startedAt;
    } else if (!times.containsKey(path)) {
      times[path] = DateTime.now();
    }
    instanceIdByPath.value = ids;
    pathByInstanceId.value = paths;
    startTimeByPath.value = times;
    _pollFailures.remove(path);
    startTrafficPolling(path, instanceId);
  }

  void setStopped(String path) {
    final ids = Map<String, String>.from(instanceIdByPath.value);
    final paths = Map<String, String>.from(pathByInstanceId.value);
    final times = Map<String, DateTime>.from(startTimeByPath.value);
    final removedInstanceId = ids[path];
    ids.remove(path);
    if (removedInstanceId != null) {
      paths.remove(removedInstanceId);
    }
    times.remove(path);
    instanceIdByPath.value = ids;
    pathByInstanceId.value = paths;
    startTimeByPath.value = times;
    stopTrafficPolling(path);
    _clearTrafficData(path);
  }

  bool isRunning(String path) => instanceIdByPath.value.containsKey(path);

  String? getInstanceId(String path) => instanceIdByPath.value[path];

  DateTime? getStartTime(String path) => startTimeByPath.value[path];

  /// 从内核拉取运行中实例的启动时刻（GUI 重开 / 旧内核无字段时补全）。
  Future<void> refreshStartedTimesFromKernel() async {
    if (!_engine.connected) return;
    try {
      final running = await _engine.listRunning();
      if (running.isEmpty) return;

      final times = Map<String, DateTime>.from(startTimeByPath.value);
      var changed = false;

      for (final item in running) {
        final path = pathByInstanceId.value[item.instanceId]?.trim();
        if (path == null || path.isEmpty) continue;

        DateTime? started = item.startedAt;
        if (started == null) {
          final probe = await _engine.inspectInstance(item.instanceId);
          started = probe.startedAt;
        }
        if (started == null) continue;
        if (times[path] == started) continue;
        times[path] = started;
        changed = true;
      }

      if (changed) startTimeByPath.value = times;
    } catch (e) {
      _logService.warn('P2P', 'refreshStartedTimes failed: $e');
    }
  }

  bool isStarting(String path) => startingPaths.value.contains(path);

  TrafficData? getTraffic(String path) => trafficByPath.value[path];

  void startTrafficPolling(String path, String instanceId) {
    _lastRxBytes[path] = 0;
    _lastTxBytes[path] = 0;
    _lastUpdateTime[path] = DateTime.now();
    unawaited(_pollOne(path, instanceId));
    _ensureSharedTimer();
  }

  void stopTrafficPolling(String path) {
    _lastRxBytes.remove(path);
    _lastTxBytes.remove(path);
    _lastUpdateTime.remove(path);
    _pollFailures.remove(path);
    if (instanceIdByPath.value.isEmpty) {
      _sharedPollTimer?.cancel();
      _sharedPollTimer = null;
    }
  }

  void _ensureSharedTimer() {
    if (_sharedPollTimer != null) return;
    if (instanceIdByPath.value.isEmpty) return;
    final interval = _metricsEnabled ? _metricsInterval : _aliveOnlyInterval;
    _sharedPollTimer = Timer.periodic(interval, (_) {
      unawaited(_pollAll());
    });
  }

  Future<void> _pollAll() async {
    if (_pollInFlight) return;
    final entries = instanceIdByPath.value.entries.toList();
    if (entries.isEmpty) {
      _sharedPollTimer?.cancel();
      _sharedPollTimer = null;
      return;
    }
    _pollInFlight = true;
    try {
      for (final e in entries) {
        await _pollOne(e.key, e.value);
      }
    } finally {
      _pollInFlight = false;
    }
  }

  List<double> _pushHistory(List<double> current, double value) {
    if (current.length < _historyLen) {
      return [...current, value];
    }
    final next = List<double>.filled(_historyLen, 0);
    for (var i = 0; i < _historyLen - 1; i++) {
      next[i] = current[i + 1];
    }
    next[_historyLen - 1] = value;
    return next;
  }

  bool _stillMapped(String path, String instanceId) =>
      instanceIdByPath.value[path] == instanceId;

  Future<void> _markNaturalExit(String path, String instanceId) async {
    if (!_stillMapped(path, instanceId)) return;
    setStopped(path);
    _logService.info('P2P', 'poll: instance exited, cleared $path');
    final cb = onNaturalExit;
    if (cb != null) {
      try {
        await cb(path, instanceId);
      } catch (e) {
        _logService.warn('P2P', 'onNaturalExit failed: $e');
      }
    }
  }

  void _notePollDegraded(String path, Object e) {
    final n = (_pollFailures[path] ?? 0) + 1;
    _pollFailures[path] = n;
    if (n == 1 || n % _degradedWarnEvery == 0) {
      _logService.warn('P2P', 'poll degraded ($n) $path: $e');
    }
  }

  Future<void> _pollOne(String path, String instanceId) async {
    if (!_stillMapped(path, instanceId)) return;

    // 存活探测：仅 isRunning==false 才自然退出；探测失败只 degraded。
    try {
      final stillUp = await _engine.isRunning(instanceId);
      if (!_stillMapped(path, instanceId)) return;
      if (!stillUp) {
        await _markNaturalExit(path, instanceId);
        return;
      }
      if (startTimeByPath.value[path] == null) {
        final probe = await _engine.inspectInstance(instanceId);
        if (probe.startedAt != null && _stillMapped(path, instanceId)) {
          final times = Map<String, DateTime>.from(startTimeByPath.value);
          times[path] = probe.startedAt!;
          startTimeByPath.value = times;
        }
      }
    } catch (e) {
      if (!_stillMapped(path, instanceId)) return;
      _notePollDegraded(path, e);
      return;
    }

    if (!_metricsEnabled) return;

    try {
      final status = await _engine.getNetworkStatus(instanceId);
      if (!_stillMapped(path, instanceId)) return;

      _pollFailures[path] = 0;
      final nodes = status.nodes;

      var totalRx = 0;
      var totalTx = 0;
      var totalLatency = 0.0;
      var totalLoss = 0.0;
      var latencyCount = 0;

      for (final node in nodes) {
        totalRx += node.rxBytes.toInt();
        totalTx += node.txBytes.toInt();
        if (node.latencyMs > 0) {
          totalLatency += node.latencyMs;
          latencyCount++;
        }
        totalLoss += node.lossRate;
      }

      final now = DateTime.now();
      final lastRx = _lastRxBytes[path] ?? 0;
      final lastTx = _lastTxBytes[path] ?? 0;
      final lastTime = _lastUpdateTime[path] ?? now;
      final elapsed = now.difference(lastTime).inMilliseconds;

      var rxRate = 0.0;
      var txRate = 0.0;
      if (elapsed > 0) {
        rxRate = ((totalRx - lastRx) / elapsed * 1000).clamp(
          0,
          double.infinity,
        );
        txRate = ((totalTx - lastTx) / elapsed * 1000).clamp(
          0,
          double.infinity,
        );
      }

      if (!_stillMapped(path, instanceId)) return;

      _lastRxBytes[path] = totalRx;
      _lastTxBytes[path] = totalTx;
      _lastUpdateTime[path] = now;

      final current = trafficByPath.value[path] ?? TrafficData();
      final newData = TrafficData(
        rxBytes: totalRx,
        txBytes: totalTx,
        rxRate: rxRate,
        txRate: txRate,
        rxHistory: _pushHistory(current.rxHistory, rxRate),
        txHistory: _pushHistory(current.txHistory, txRate),
        updatedAt: now,
        nodeCount: nodes.length,
        avgLatencyMs: latencyCount > 0 ? totalLatency / latencyCount : 0,
        avgLossRate: nodes.isNotEmpty ? totalLoss / nodes.length : 0,
      );

      batch(() {
        if (!_stillMapped(path, instanceId)) return;
        final statusMap = Map<String, KVNetworkStatus>.from(
          networkStatusByPath.value,
        );
        statusMap[path] = status;
        networkStatusByPath.value = statusMap;

        final map = Map<String, TrafficData>.from(trafficByPath.value);
        map[path] = newData;
        trafficByPath.value = map;
      });
    } catch (e) {
      if (!_stillMapped(path, instanceId)) return;
      _notePollDegraded(path, e);
    }
  }

  void _clearTrafficData(String path) {
    batch(() {
      final map = Map<String, TrafficData>.from(trafficByPath.value);
      map.remove(path);
      trafficByPath.value = map;

      final statusMap = Map<String, KVNetworkStatus>.from(
        networkStatusByPath.value,
      );
      statusMap.remove(path);
      networkStatusByPath.value = statusMap;
    });
  }

  void dispose() {
    _sharedPollTimer?.cancel();
    _sharedPollTimer = null;
    _coreLogResubscribeTimer?.cancel();
    _coreLogResubscribeTimer = null;
    _coreLogSubscription?.cancel();
    _coreLogSubscription = null;
    onNaturalExit = null;
  }
}
