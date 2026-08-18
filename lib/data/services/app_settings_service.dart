import 'package:astral/config/app_theme_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  static const String _keyAppThemeIndex = 'app_theme_index';
  static const String _keyCloseMinimize = 'close_minimize';
  static const String _keyLaunchAtStartup = 'launch_at_startup';
  static const String _keyAutoCheckUpdate = 'auto_check_update';
  static const String _keyUpdateBetaChannel = 'update_beta_channel';
  static const String _keyCoreServiceOptOut = 'core_service_opt_out';

  final SharedPreferences _prefs;

  AppSettingsService(this._prefs);

  int getAppThemeIndex() =>
      _prefs.getInt(_keyAppThemeIndex) ?? kDefaultAppThemeId.storageIndex;

  Future<void> setAppThemeIndex(int index) async =>
      await _prefs.setInt(_keyAppThemeIndex, index);

  bool getCloseMinimize() => _prefs.getBool(_keyCloseMinimize) ?? true;

  Future<void> setCloseMinimize(bool value) async =>
      await _prefs.setBool(_keyCloseMinimize, value);

  bool isLaunchAtStartup() => _prefs.getBool(_keyLaunchAtStartup) ?? false;

  Future<void> setLaunchAtStartup(bool value) async =>
      await _prefs.setBool(_keyLaunchAtStartup, value);

  bool getAutoCheckUpdate() => _prefs.getBool(_keyAutoCheckUpdate) ?? true;

  Future<void> setAutoCheckUpdate(bool value) async =>
      await _prefs.setBool(_keyAutoCheckUpdate, value);

  bool getUpdateBetaChannel() => _prefs.getBool(_keyUpdateBetaChannel) ?? false;

  Future<void> setUpdateBetaChannel(bool value) async =>
      await _prefs.setBool(_keyUpdateBetaChannel, value);

  /// 用户在设置里卸载服务后为 true，避免下次启动再自动安装。
  bool getCoreServiceOptOut() => _prefs.getBool(_keyCoreServiceOptOut) ?? false;

  Future<void> setCoreServiceOptOut(bool value) async =>
      await _prefs.setBool(_keyCoreServiceOptOut, value);
}
