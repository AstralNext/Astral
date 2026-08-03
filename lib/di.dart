import 'dart:io';

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
  getIt.registerLazySingleton<PlatformPathService>(
    () => PlatformPathService(),
  );
  getIt.registerLazySingleton<TomlConfigService>(
    () => TomlConfigService(),
  );
  getIt.registerLazySingleton<InstanceCatalogService>(
    () => InstanceCatalogService(
      getIt<PlatformPathService>(),
      getIt<TomlConfigService>(),
    ),
  );

  await ClientRuntimeInfo.warmUp();

  final p2p = P2PService();
  await p2p.ensureInitialized();
  getIt.registerSingleton<P2PService>(p2p);
  getIt.registerLazySingleton<VpnManager>(
    () => VpnManager(getIt<P2PService>()),
  );
  getIt<LogService>().info('DI', 'P2PService ready');

  final runtimeStore = InstanceRuntimeStore();
  getIt.registerSingleton<InstanceRuntimeStore>(runtimeStore);
  final connection = InstanceConnectionService(
    getIt<TomlConfigService>(),
    runtimeStore,
    getIt<LogService>(),
  );
  getIt.registerSingleton<InstanceConnectionService>(connection);
  runtimeStore.onNaturalExit = connection.handleNaturalExit;

  if (Platform.isAndroid) {
    final vpn = getIt<VpnManager>();
    vpn.onRevokedBySystem = connection.handleVpnRevokedBySystem;
    vpn.startListening();
  }

  getIt.registerLazySingleton<SettingsState>(() => SettingsState());
  getIt<SettingsState>().loadFromPersistence();
  getIt.registerLazySingleton<ThemeRevealController>(() => ThemeRevealController());

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

/// 退出前：停实例 → VPN → FRB。可安全重复调用。
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

  if (getIt.isRegistered<InstanceConnectionService>()) {
    try {
      await getIt<InstanceConnectionService>().stopAll();
    } catch (e) {
      log('stopAll failed: $e');
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
  if (getIt.isRegistered<P2PService>()) {
    getIt<P2PService>().dispose();
  }
  if (getIt.isRegistered<LogService>()) {
    getIt<LogService>().dispose();
  }
}
