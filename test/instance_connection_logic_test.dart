import 'dart:io';

import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral/data/services/instance_catalog_service.dart';
import 'package:astral/data/services/instance_connection_service.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral/data/services/platform_path_service.dart';
import 'package:astral/data/services/toml_config_service.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNetworkStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeKernel engine;
  late InstanceRuntimeStore store;
  late InstanceConnectionService connection;

  setUp(() async {
    await GetIt.I.reset();
    tempDir = await Directory.systemTemp.createTemp('astral_conn_');
    engine = _FakeKernel();
    GetIt.I.registerSingleton<KernelEngine>(engine);
    GetIt.I.registerSingleton<LogService>(LogService());
    store = InstanceRuntimeStore();
    GetIt.I.registerSingleton<InstanceRuntimeStore>(store);
    GetIt.I.registerSingleton<TomlConfigService>(TomlConfigService());
    GetIt.I.registerSingleton<InstanceCatalogService>(
      _FakeCatalog(tempDir.path),
    );
    connection = InstanceConnectionService(
      GetIt.I<TomlConfigService>(),
      store,
      GetIt.I<LogService>(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('stop clears zombie map entry', () async {
    final path = p.join(tempDir.path, 'a.toml');
    store.setRunning(path, 'id-dead');
    store.stopTrafficPolling(path);
    engine.runningIds.clear();

    expect(await connection.stop(path: path, name: 'a'), isTrue);
    expect(store.isRunning(path), isFalse);
  });

  test('startFromFile starts instance', () async {
    final file = File(p.join(tempDir.path, 'b.toml'));
    await file.writeAsString(GetIt.I<TomlConfigService>().defaultToml());

    expect(await connection.startFromFile(path: file.path, name: 'b'), isTrue);
    expect(store.isRunning(file.path), isTrue);
  });

  test('stop clears live instance', () async {
    final path = p.join(tempDir.path, 'c.toml');
    final id = await engine.createInstance(configToml: 'x=1', sourcePath: path);
    store.setRunning(path, id);
    store.stopTrafficPolling(path);

    expect(await connection.stop(path: path, name: 'c'), isTrue);
    expect(store.isRunning(path), isFalse);
    expect(engine.runningIds, isEmpty);
  });

  test('natural exit closes instance', () async {
    final path = p.join(tempDir.path, 'e.toml');
    final id = await engine.createInstance(configToml: 'x=1', sourcePath: path);
    store.setRunning(path, id);
    store.stopTrafficPolling(path);
    store.setStopped(path);

    await connection.handleNaturalExit(path, id);
    expect(engine.runningIds, isEmpty);
  });

  test('vpn revoke stops mapped instance', () async {
    final path = p.join(tempDir.path, 'f.toml');
    final id = await engine.createInstance(configToml: 'x=1', sourcePath: path);
    store.setRunning(path, id);
    store.stopTrafficPolling(path);

    await connection.handleVpnRevokedBySystem(id);
    expect(store.isRunning(path), isFalse);
    expect(engine.runningIds, isEmpty);
  });

  test('global queue serializes starts on same path', () async {
    final file = File(p.join(tempDir.path, 'd.toml'));
    await file.writeAsString(GetIt.I<TomlConfigService>().defaultToml());
    final path = file.path;
    final toml = GetIt.I<TomlConfigService>().defaultToml();

    engine.startDelay = const Duration(milliseconds: 80);
    final first = connection.start(path: path, configToml: toml, name: 'd');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = connection.start(path: path, configToml: toml, name: 'd');

    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(engine.startCount, 1);
  });
}

class _FakeKernel implements KernelEngine {
  final runningIds = <String>{};
  var _seq = 0;
  var startCount = 0;
  Duration startDelay = Duration.zero;

  @override
  KernelMode get mode => KernelMode.embedded;

  @override
  bool get connected => true;

  @override
  bool get stopsInstancesOnExit => true;

  @override
  String? get statusMessage => 'fake';

  @override
  Future<void> ensureReady() async {}

  @override
  Future<String> createInstance({
    required String configToml,
    required String sourcePath,
    String? name,
  }) async {
    startCount++;
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
    }
    final id = 'id-${++_seq}';
    runningIds.add(id);
    return id;
  }

  @override
  Future<void> closeInstance(String instanceId) async {
    runningIds.remove(instanceId);
  }

  @override
  Future<bool> isRunning(String instanceId) async =>
      runningIds.contains(instanceId);

  @override
  Future<KernelInstanceInspect> inspectInstance(String instanceId) async =>
      KernelInstanceInspect(running: runningIds.contains(instanceId));

  @override
  Future<String> easytierVersion() async => 'test';

  @override
  Stream<KernelLogEvent> subscribeCoreLogs() => const Stream.empty();

  @override
  Future<List<KernelLogEvent>> recentCoreLogs({
    int after = 0,
    int limit = 500,
    String? instanceId,
  }) async =>
      const [];

  @override
  Future<KVNetworkStatus> getNetworkStatus(String instanceId) async =>
      KVNetworkStatus(totalNodes: BigInt.zero, nodes: const []);

  @override
  Future<List<KernelRunningInstance>> listRunning() async => const [];

  @override
  Future<void> dispose() async {}
}

class _FakeCatalog extends InstanceCatalogService {
  _FakeCatalog(String root) : super(_NopPaths(root), TomlConfigService());
}

class _NopPaths extends PlatformPathService {
  _NopPaths(this._root);
  final String _root;

  @override
  Future<Directory> configDir({String? subDir}) async => Directory(_root);
}
