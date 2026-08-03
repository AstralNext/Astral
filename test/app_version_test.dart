import 'package:astral/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion', () {
    test('normalize strips v and build metadata', () {
      expect(AppVersion.normalize('v1.0.0-beta.1+42'), '1.0.0-beta.1');
      expect(AppVersion.normalize('1.2.3+9'), '1.2.3');
    });

    test('same core version is not newer despite build suffix', () {
      expect(
        AppVersion.isNewer('v1.0.0-beta.1', '1.0.0-beta.1+1'),
        isFalse,
      );
      expect(
        AppVersion.isNewer('1.0.0-beta.1', 'v1.0.0-beta.1+99'),
        isFalse,
      );
    });

    test('detects real upgrades', () {
      expect(AppVersion.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(AppVersion.isNewer('v2.0.0', '1.9.9+3'), isTrue);
      expect(AppVersion.isNewer('1.0.0-beta.2', '1.0.0-beta.1'), isTrue);
      expect(AppVersion.isNewer('1.0.0', '1.0.1'), isFalse);
    });
  });
}
