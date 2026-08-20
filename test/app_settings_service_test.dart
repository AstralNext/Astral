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
      expect(settings.getStartMinimized(), isTrue);

      await settings.setStartMinimized(false);
      expect(settings.getStartMinimized(), isFalse);
    });

    test('persists core service opt-out', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettingsService(prefs);
      expect(settings.getCoreServiceOptOut(), isFalse);
      await settings.setCoreServiceOptOut(true);
      expect(settings.getCoreServiceOptOut(), isTrue);
    });
  });
}
