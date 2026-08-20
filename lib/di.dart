import 'dart:io';

import 'package:astral/data/kernel/core_host.dart';
import 'package:astral/data/kernel/core_service_controller.dart';
import 'package:astral/data/kernel/embedded_kernel_engine.dart';
import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/data/kernel/kernel_mode.dart';
import 'package:astral/data/kernel/service_kernel_engine.dart';
import 'package:astral/data/services/app_settings_service.dart';
import 'package:astral/data/services/instance_catalog_service.dart';
import 'package:astral/data/services/instance_connection_service.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral/data/services/platform_path_service.dart';
import 'package:astral/data/services/toml_config_service.dart';
import 'package:astral/data/services/update_service.dart';
import 'package:astral/data/services/vpn_manager.dart';
import 'package:astral/data/state/settings_state.dart';
import 'package:astral/data/state/theme_reveal_state.dart';
import 'package:astral/data/state/update_state.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral/ui/shell/shell_content_controller.dart';
import 'package:astral/ui/shell/shell_navigation_controller.dart';
import 'package:astral/utils/client_runtime_info.dart';
import 'package:astral_rust_core/p2p_service.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

final getIt = GetIt.instance;

var _diDisposed = false;

Future<void> setupDI() async {
  _diDisposed = false;
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);
  getIt.registerSingleton<AppSettingsService>(AppSettingsService(prefs));

  getIt.registerLazySingleton<LogService>(() => LogService());
  getIt.registerLazySingleton<PlatformPathService>(() => PlatformPathService());
  getIt.registerLazySingleton<TomlConfigService>(() => TomlConfigService());
  getIt.registerLazySingleton<InstanceCatalogService>(
    () => InstanceCatalogService(
      getIt<PlatformPathService>(),
      getIt<TomlConfigService>(),
    ),
  );

  await ClientRuntimeInfo.warmUp();

  final host = CoreHost();
  getIt.registerSingleton<CoreHost>(host);

  if (KernelMode.forPlatform() == KernelMode.service) {
    getIt.registerSingleton<CoreServiceController>(
      CoreServiceController(
        host: getIt<CoreHost>(),
        settings: getIt<AppSettingsService>(),
        log: getIt<LogService>(),
      ),
    );
    try {
      await getIt<CoreServiceController>().refresh();
    } catch (e) {
      getIt<LogService>().warn('DI', '刷新内核服务状态失败: $e');
    }
  }

  final engine = await _createKernelEngine();
  getIt.registerSingleton<KernelEngine>(engine);
  getIt<LogService>().info(
    'DI',
    'KernelEngine ${engine.mode.label}: ${engine.statusMessage ?? '窗口显示后连接'}',
  );

  if (engine.mode == KernelMode.embedded && Platform.isAndroid) {
    getIt.registerLazySingleton<VpnManager>(
      () => VpnManager(getIt<P2PService>()),
    );
  }

  final runtimeStore = InstanceRuntimeStore();
  getIt.registerSingleton<InstanceRuntimeStore>(runtimeStore);
  final connection = InstanceConnectionService(
    getIt<TomlConfigService>(),
    runtimeStore,
    getIt<LogService>(),
  );
  getIt.registerSingleton<InstanceConnectionService>(connection);
  runtimeStore.onNaturalExit = connection.handleNaturalExit;

  if (getIt.isRegistered<VpnManager>()) {
    final vpn = getIt<VpnManager>();
    vpn.onRevokedBySystem = connection.handleVpnRevokedBySystem;
    vpn.startListening();
  }

  getIt.registerLazySingleton<SettingsState>(() => SettingsState());
  getIt<SettingsState>().loadFromPersistence();
  getIt.registerLazySingleton<ThemeRevealController>(
    () => ThemeRevealController(),
  );

  getIt.registerSingleton<UpdateState>(UpdateState());
  getIt<UpdateState>().loadFromPersistence();
  getIt.registerLazySingleton<UpdateService>(
    () => UpdateService(getIt<UpdateState>()),
  );

  getIt.registerLazySingleton<ShellNavigationController>(
    () => ShellNavigationController(),
  );
  getIt.registerLazySingleton<ShellContentController>(
    () => ShellContentController(),
  );
}

Future<KernelEngine> _createKernelEngine() async {
  if (KernelMode.forPlatform() == KernelMode.service) {
    return ServiceKernelEngine(
      host: getIt<CoreHost>(),
      core: getIt<CoreServiceController>(),
      log: getIt<LogService>(),
    );
  }

  final p2p = P2PService();
  getIt.registerSingleton<P2PService>(p2p);
  return EmbeddedKernelEngine(p2p);
}

/// Android 内嵌内核：首帧后再 dlopen，避免挡住界面。
Future<void> bootstrapEmbeddedKernel() async {
  if (!getIt.isRegistered<KernelEngine>()) return;
  final engine = getIt<KernelEngine>();
  if (engine.mode != KernelMode.embedded) return;
  try {
    await engine.ensureReady();
  } catch (e) {
    getIt<LogService>().warn('DI', '内核未就绪: $e');
  }
  if (engine.connected) {
    await syncRunningInstances();
  }
}

Future<void> syncRunningInstances({bool reattachKernel = true}) async {
  if (!getIt.isRegistered<KernelEngine>() ||
      !getIt.isRegistered<InstanceRuntimeStore>()) {
    return;
  }
  final engine = getIt<KernelEngine>();
  if (!engine.connected) return;
  final log = getIt.isRegistered<LogService>() ? getIt<LogService>() : null;
  try {
    final store = getIt<InstanceRuntimeStore>();
    if (reattachKernel) {
      await store.attachKernel();
    }
    await store.refreshStartedTimesFromKernel();
    final running = await engine.listRunning();
    InstanceCatalogSnapshot? snapshot;
    if (getIt.isRegistered<InstanceCatalogService>()) {
      snapshot = await getIt<InstanceCatalogService>().loadSnapshot();
    }
    var restored = 0;
    for (final item in running) {
      final path = await _resolveRunningInstancePath(item, snapshot);
      if (path == null || path.isEmpty) {
        log?.warn('DI', '运行中实例无法对回配置: ${item.instanceId}');
        continue;
      }
      store.setRunning(path, item.instanceId, startedAt: item.startedAt);
      restored++;
    }
    if (restored > 0) {
      log?.info('DI', '已恢复 $restored 个运行中实例');
    }
  } catch (e) {
    log?.warn('DI', '同步运行中实例失败: $e');
  }
}

/// 内核开机自启实例可能稍晚才起来，短时间内再对几次状态。
Future<void> followRunningInstances() async {
  for (final delay in const [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 9),
  ]) {
    await Future<void>.delayed(delay);
    await syncRunningInstances(reattachKernel: false);
  }
}

Future<String?> _resolveRunningInstancePath(
  KernelRunningInstance item,
  InstanceCatalogSnapshot? snapshot,
) async {
  final source = item.sourcePath.trim();
  final items = snapshot?.items ?? const <InstanceCatalogItem>[];
  if (source.isNotEmpty) {
    for (final catalogItem in items) {
      if (_sameFsPath(catalogItem.path, source)) return catalogItem.path;
    }
    if (File(source).existsSync()) return source;
  }
  if (items.isEmpty ||
      !getIt.isRegistered<InstanceCatalogService>() ||
      !getIt.isRegistered<TomlConfigService>()) {
    return source.isEmpty ? null : source;
  }
  final catalog = getIt<InstanceCatalogService>();
  final tomlSvc = getIt<TomlConfigService>();
  final want = item.instanceId.trim().toLowerCase();
  for (final catalogItem in items) {
    final toml = await catalog.readToml(catalogItem.path);
    if (toml == null) continue;
    final id = tomlSvc.readInstanceId(toml)?.toLowerCase();
    if (id != null && id == want) return catalogItem.path;
  }
  return null;
}

bool _sameFsPath(String a, String b) {
  final na = a.replaceAll('/', '\\').trim().toLowerCase();
  final nb = b.replaceAll('/', '\\').trim().toLowerCase();
  return na == nb;
}

/// 退出前清理。服务模式不停内核实例。
Future<void> disposeDI() async {
  if (_diDisposed) return;
  _diDisposed = true;
  void log(String msg) {
    if (getIt.isRegistered<LogService>()) {
      try {
        getIt<LogService>().warn('DI', msg);
      } catch (_) {}
    }
  }

  final engine = getIt.isRegistered<KernelEngine>()
      ? getIt<KernelEngine>()
      : null;

  if (engine == null || engine.stopsInstancesOnExit) {
    if (getIt.isRegistered<InstanceConnectionService>()) {
      try {
        await getIt<InstanceConnectionService>().stopAll();
      } catch (e) {
        log('stopAll failed: $e');
      }
    }
  }
  if (getIt.isRegistered<VpnManager>()) {
    try {
      await getIt<VpnManager>().dispose();
    } catch (e) {
      log('VpnManager.dispose failed: $e');
    }
  }
  if (getIt.isRegistered<InstanceRuntimeStore>()) {
    getIt<InstanceRuntimeStore>().dispose();
  }
  if (engine != null) {
    try {
      await engine.dispose();
    } catch (e) {
      log('KernelEngine.dispose failed: $e');
    }
  }
  if (getIt.isRegistered<LogService>()) {
    getIt<LogService>().dispose();
  }
}
