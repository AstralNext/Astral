import 'dart:io';

/// Windows 当前用户登录时启动 Astral GUI（HKCU Run）。
class WindowsStartupLaunch {
  WindowsStartupLaunch._();

  static const valueName = 'Astral';
  static const _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  static Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final r = await Process.run(
        'reg',
        ['query', _runKey, '/v', valueName],
        runInShell: false,
      );
      return r.exitCode == 0 &&
          (r.stdout as String).contains(valueName);
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows) return;
    if (enabled) {
      final exe = Platform.resolvedExecutable;
      final quoted = '"$exe"';
      final r = await Process.run(
        'reg',
        ['add', _runKey, '/v', valueName, '/t', 'REG_SZ', '/d', quoted, '/f'],
        runInShell: false,
      );
      if (r.exitCode != 0) {
        throw StateError(
          (r.stderr as String?)?.trim().isNotEmpty == true
              ? r.stderr
              : 'reg add failed',
        );
      }
    } else {
      await Process.run(
        'reg',
        ['delete', _runKey, '/v', valueName, '/f'],
        runInShell: false,
      );
    }
  }
}
