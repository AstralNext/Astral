import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral_rust_core/p2p_service.dart';

class EmbeddedKernelEngine implements KernelEngine {
  EmbeddedKernelEngine(this._p2p);

  final P2PService _p2p;
  var _connected = false;
  String? _statusMessage;

  @override
  KernelMode get mode => KernelMode.embedded;

  @override
  bool get connected => _connected;

  @override
  bool get stopsInstancesOnExit => true;

  @override
  String? get statusMessage => _statusMessage;

  @override
  Future<void> ensureReady() async {
    await _p2p.ensureInitialized();
    _connected = true;
    _statusMessage = '内嵌内核已就绪';
  }

  @override
  Future<String> easytierVersion() => _p2p.easytierVersion();

  @override
  Future<String> createInstance({
    required String configToml,
    required String sourcePath,
    String? name,
  }) {
    return _p2p.createInstance(configToml: configToml, watchEvent: true);
  }

  @override
  Future<void> closeInstance(String instanceId) =>
      _p2p.closeInstance(instanceId);

  @override
  Future<bool> isRunning(String instanceId) =>
      _p2p.isEasytierRunning(instanceId);

  @override
  Future<KernelInstanceInspect> inspectInstance(String instanceId) async =>
      KernelInstanceInspect(running: await isRunning(instanceId));

  @override
  Future<KVNetworkStatus> getNetworkStatus(String instanceId) =>
      _p2p.getNetworkStatus(instanceId);

  @override
  Stream<KernelLogEvent> subscribeCoreLogs() {
    return _p2p.subscribeCoreLogs().map(
      (e) => KernelLogEvent(instanceId: e.instanceId, message: e.message),
    );
  }

  @override
  Future<List<KernelRunningInstance>> listRunning() async => const [];

  @override
  Future<void> dispose() async {
    _connected = false;
    _p2p.dispose();
  }
}
