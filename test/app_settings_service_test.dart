import 'package:astral/data/services/app_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettingsService', () {
    test('persists update channel prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettingsService(prefs);
      expect(settings.getAutoCheckUpdate(), isTrue);
      expect(settings.getUpdateBetaChannel(), isFalse);

      await settings.setAutoCheckUpdate(false);
      await settings.setUpdateBetaChannel(true);
      expect(settings.getAutoCheckUpdate(), isFalse);
      expect(settings.getUpdateBetaChannel(), isTrue);
    });

    test('persists theme and window prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettingsService(prefs);

      await settings.setCloseMinimize(false);
      await settings.setLaunchAtStartup(true);
      expect(settings.getCloseMinimize(), isFalse);
      expect(settings.isLaunchAtStartup(), isTrue);
    });

    test('persists core connection prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettingsService(prefs);
      expect(settings.getCoreTarget(), AppSettingsService.defaultCoreTarget);

      await settings.setCoreTarget('127.0.0.1:50052');
      await settings.setCoreBinaryPath(r'C:\core\astral-core.exe');
      expect(settings.getCoreTarget(), '127.0.0.1:50052');
      expect(settings.getCoreBinaryPath(), r'C:\core\astral-core.exe');
      expect(settings.getCoreServiceOptOut(), isFalse);
      await settings.setCoreServiceOptOut(true);
      expect(settings.getCoreServiceOptOut(), isTrue);
    });
  });
}
