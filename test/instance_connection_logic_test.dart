import 'dart:io';

import 'package:astral/data/services/instance_catalog_service.dart';
import 'package:astral/data/services/instance_connection_service.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral/data/services/platform_path_service.dart';
import 'package:astral/data/services/toml_config_service.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral_rust_core/p2p_service.dart';
import 'package:astral_rust_core/src/rust/api/p2p.dart'
    show CoreLogEventC, KVNetworkStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeP2P p2p;
  late InstanceRuntimeStore store;
  late InstanceConnectionService connection;

  setUp(() async {
    await GetIt.I.reset();
    tempDir = await Directory.systemTemp.createTemp('astral_conn_');
    p2p = _FakeP2P();
    GetIt.I.registerSingleton<P2PService>(p2p);
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
    p2p.runningIds.clear();

    expect(await connection.stop(path: path, name: 'a'), isTrue);
    expect(store.isRunning(path), isFalse);
  });

  test('startFromFile starts instance', () async {
    final file = File(p.join(tempDir.path, 'b.toml'));
    await file.writeAsString(GetIt.I<TomlConfigService>().defaultToml());

    expect(
      await connection.startFromFile(path: file.path, name: 'b'),
      isTrue,
    );
    expect(store.isRunning(file.path), isTrue);
  });

  test('stop clears live instance', () async {
    final path = p.join(tempDir.path, 'c.toml');
    final id = await p2p.createInstance(configToml: 'x=1', watchEvent: true);
    store.setRunning(path, id);
    store.stopTrafficPolling(path);

    expect(await connection.stop(path: path, name: 'c'), isTrue);
    expect(store.isRunning(path), isFalse);
    expect(p2p.runningIds, isEmpty);
  });

  test('natural exit closes instance', () async {
    final path = p.join(tempDir.path, 'e.toml');
    final id = await p2p.createInstance(configToml: 'x=1', watchEvent: true);
    store.setRunning(path, id);
    store.stopTrafficPolling(path);
    store.setStopped(path);

    await connection.handleNaturalExit(path, id);
    expect(p2p.runningIds, isEmpty);
  });

  test('vpn revoke stops mapped instance', () async {
    final path = p.join(tempDir.path, 'f.toml');
    final id = await p2p.createInstance(configToml: 'x=1', watchEvent: true);
    store.setRunning(path, id);
    store.stopTrafficPolling(path);

    await connection.handleVpnRevokedBySystem(id);
    expect(store.isRunning(path), isFalse);
    expect(p2p.runningIds, isEmpty);
  });

  test('global queue serializes starts on same path', () async {
    final file = File(p.join(tempDir.path, 'd.toml'));
    await file.writeAsString(GetIt.I<TomlConfigService>().defaultToml());
    final path = file.path;
    final toml = GetIt.I<TomlConfigService>().defaultToml();

    p2p.startDelay = const Duration(milliseconds: 80);
    final first = connection.start(path: path, configToml: toml, name: 'd');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = connection.start(path: path, configToml: toml, name: 'd');

    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(p2p.startCount, 1);
  });
}

class _FakeP2P extends P2PService {
  final runningIds = <String>{};
  var _seq = 0;
  var startCount = 0;
  Duration startDelay = Duration.zero;

  @override
  Future<void> ensureInitialized({bool forceSameCodegenVersion = true}) async {}

  @override
  Future<String> createInstance({
    required String configToml,
    required bool watchEvent,
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
  Future<bool> isEasytierRunning(String instanceId) async =>
      runningIds.contains(instanceId);

  @override
  Future<String> easytierVersion() async => 'test';

  @override
  Stream<CoreLogEventC> subscribeCoreLogs() => const Stream.empty();

  @override
  Future<KVNetworkStatus> getNetworkStatus(String instanceId) async =>
      KVNetworkStatus(totalNodes: BigInt.zero, nodes: const []);
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
