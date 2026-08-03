import 'package:package_info_plus/package_info_plus.dart';

class ClientRuntimeInfo {
  ClientRuntimeInfo._();

  static bool _ready = false;
  static String _appVersion = '';

  static Future<void> warmUp() async {
    if (_ready) return;
    try {
      final p = await PackageInfo.fromPlatform();
      final ver = p.version.trim();
      final build = p.buildNumber.trim();
      _appVersion =
          build.isEmpty ? ver : (ver.isEmpty ? build : '$ver+$build');
    } catch (_) {
      _appVersion = '';
    }
    _ready = true;
  }

  static String get appVersion =>
      _appVersion.isEmpty ? 'unknown' : _appVersion;
}
