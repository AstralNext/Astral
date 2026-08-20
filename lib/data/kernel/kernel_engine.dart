import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNetworkStatus;

/// 解析内核 JSON 中的 `started_at_unix_ms`。
DateTime? parseKernelStartedAt(Object? unixMs) {
  if (unixMs is num && unixMs > 0) {
    return DateTime.fromMillisecondsSinceEpoch(unixMs.toInt());
  }
  return null;
}

class KernelLogEvent {
  const KernelLogEvent({required this.instanceId, required this.message});

  final String instanceId;
  final String message;
}

class KernelRunningInstance {
  const KernelRunningInstance({
    required this.instanceId,
    required this.sourcePath,
    this.startedAt,
  });

  final String instanceId;
  final String sourcePath;

  /// 内核记录的本次运行开始时刻。
  final DateTime? startedAt;
}

/// 内核侧实例探测结果（启动轮询用）。
class KernelInstanceInspect {
  const KernelInstanceInspect({
    this.running = false,
    this.failed = false,
    this.errorMessage = '',
    this.startedAt,
  });

  /// STARTING / RUNNING 都算还活着。
  final bool running;

  /// 内核已明确报错，应停止等待。
  final bool failed;
  final String errorMessage;

  /// 内核记录的本次运行开始时刻。
  final DateTime? startedAt;
}

/// GUI 只打这一层：内嵌 FFI 或本机 JSON-RPC 服务。
abstract class KernelEngine {
  KernelMode get mode;

  bool get connected;

  /// 退出 GUI 时是否应 stopAll。服务模式为 false。
  bool get stopsInstancesOnExit;

  String? get statusMessage;

  Future<void> ensureReady();

  Future<String> easytierVersion();

  Future<String> createInstance({
    required String configToml,
    required String sourcePath,
    String? name,
  });

  Future<void> closeInstance(String instanceId);

  Future<bool> isRunning(String instanceId);

  /// 默认把 [isRunning] 映射成探测结果；服务内核可覆盖以区分 STARTING / ERROR。
  Future<KernelInstanceInspect> inspectInstance(String instanceId) async {
    return KernelInstanceInspect(running: await isRunning(instanceId));
  }

  Future<KVNetworkStatus> getNetworkStatus(String instanceId);

  Stream<KernelLogEvent> subscribeCoreLogs();

  /// 拉取内核环形缓冲中的历史日志（服务模式下有效）。
  Future<List<KernelLogEvent>> recentCoreLogs({
    int after = 0,
    int limit = 500,
    String? instanceId,
  });

  Future<List<KernelRunningInstance>> listRunning();

  Future<void> dispose();
}
