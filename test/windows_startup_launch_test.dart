import 'package:astral/data/services/windows_startup_launch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsStartupLaunch', () {
    test('runValue quotes exe and optional minimized flag', () {
      expect(
        WindowsStartupLaunch.runValue(r'C:\Astral\astral.exe', startMinimized: false),
        r'"C:\Astral\astral.exe"',
      );
      expect(
        WindowsStartupLaunch.runValue(r'C:\Astral\astral.exe', startMinimized: true),
        r'"C:\Astral\astral.exe" --minimized',
      );
    });

    test('argsRequestMinimized reads --minimized', () {
      expect(WindowsStartupLaunch.argsRequestMinimized(const []), isFalse);
      expect(
        WindowsStartupLaunch.argsRequestMinimized(const ['--minimized']),
        isTrue,
      );
    });
  });
}
