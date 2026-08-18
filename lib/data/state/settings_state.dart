import 'dart:io';

import 'package:astral/config/app_theme_id.dart';
import 'package:astral/data/services/app_settings_service.dart';
import 'package:astral/data/services/windows_startup_launch.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals.dart';

class SettingsState {
  final closeMinimize = signal(true);
  final appThemeId = signal(kDefaultAppThemeId);
  final launchAtStartup = signal(false);
  final coreTarget = signal(AppSettingsService.defaultCoreTarget);
  final coreBinaryPath = signal('');

  void loadFromPersistence() {
    final settings = GetIt.I<AppSettingsService>();
    closeMinimize.value = settings.getCloseMinimize();
    appThemeId.value = AppThemeIdCodec.fromIndex(settings.getAppThemeIndex());
    launchAtStartup.value = settings.isLaunchAtStartup();
    coreTarget.value = settings.getCoreTarget();
    coreBinaryPath.value = settings.getCoreBinaryPath();

    // Sync registry → prefs if user changed it outside the app.
    if (Platform.isWindows) {
      WindowsStartupLaunch.isEnabled().then((enabled) {
        if (launchAtStartup.value != enabled) {
          launchAtStartup.value = enabled;
          settings.setLaunchAtStartup(enabled);
        }
      });
    }
  }

  Future<void> saveToPersistence() async {
    final settings = GetIt.I<AppSettingsService>();
    await Future.wait([
      settings.setCloseMinimize(closeMinimize.value),
      settings.setAppThemeIndex(appThemeId.value.storageIndex),
      settings.setLaunchAtStartup(launchAtStartup.value),
      settings.setCoreTarget(
        coreTarget.value.trim().isEmpty
            ? AppSettingsService.defaultCoreTarget
            : coreTarget.value.trim(),
      ),
      settings.setCoreBinaryPath(coreBinaryPath.value.trim()),
    ]);
  }

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
