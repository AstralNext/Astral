import 'package:astral/data/kernel/core_service_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoreServiceHealthReport', () {
    test('parses doctor json', () {
      const raw = '''
{
  "service_name": "dev.astral.core",
  "service_generation": "core-v2",
  "listen": "127.0.0.1:50051",
  "scm_status": "running",
  "legacy_service_installed": true,
  "legacy_service_status": "stopped",
  "listener": {
    "pid": 123,
    "command_line": "astral-core --windows-service dev.astral.core-default",
    "is_astral_core": true,
    "is_legacy": true,
    "generation_match": false
  },
  "registry_present": true,
  "registry_generation": "core-v1",
  "registry_data_dir": "C:/data",
  "data_dir": "C:/data",
  "legacy_data_dir": "C:/data/instances/default",
  "legacy_data_dir_exists": true,
  "issues": ["旧服务仍存在"],
  "needs_repair": true
}
''';
      final report = CoreServiceHealthReport.tryParse(raw);
      expect(report, isNotNull);
      expect(report!.serviceName, 'dev.astral.core');
      expect(report.needsRepair, isTrue);
      expect(report.listenerPid, 123);
      expect(report.issues, contains('旧服务仍存在'));
    });
  });

  group('parseRepairOutput', () {
    test('parses repair summary line', () {
      final report = parseRepairOutput(
        'repair: stopped_current=true uninstalled_legacy=true killed_listeners=1 migrated_data=true normalized_registry=false',
      );
      expect(report, isNotNull);
      expect(report!.stoppedCurrentService, isTrue);
      expect(report.killedStaleListeners, 1);
      expect(report.changed, isTrue);
    });
  });
}
