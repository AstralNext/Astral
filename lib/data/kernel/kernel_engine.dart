import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNetworkStatus;

class KernelLogEvent {
  const KernelLogEvent({required this.instanceId, required this.message});

  final String instanceId;
  final String message;
}

class KernelRunningInstance {
  const KernelRunningInstance({
    required this.instanceId,
    required this.sourcePath,
  });

  final String instanceId;
  final String sourcePath;
}

/// 内核侧实例探测结果（启动轮询用）。
class KernelInstanceInspect {
  const KernelInstanceInspect({
    this.running = false,
    this.failed = false,
    this.errorMessage = '',
  });

  /// STARTING / RUNNING 都算还活着。
  final bool running;

  /// 内核已明确报错，应停止等待。
  final bool failed;
  final String errorMessage;
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

  Future<List<KernelRunningInstance>> listRunning();

  Future<void> dispose();
}
