/// TOML 默认模板与轻量读取。
import 'package:astral/data/models/instance_toml_config.dart';

class TomlConfigService {
  String defaultToml() => InstanceTomlConfig.defaults().toToml();

  /// 顶层 `ipv4 = "x.x.x.x/n"`（Android VpnService 用）。
  String? readIpv4(String input) {
    try {
      final cfg = InstanceTomlConfig.fromToml(input);
      if (cfg.dhcp) return null;
      final ip = cfg.ipv4.trim();
      return ip.isEmpty ? null : ip;
    } catch (_) {
      final match = RegExp(
        r'''^\s*(?!#)ipv4\s*=\s*"([^"\n]*)"''',
        multiLine: true,
      ).firstMatch(input);
      final value = match?.group(1)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }
  }
}
