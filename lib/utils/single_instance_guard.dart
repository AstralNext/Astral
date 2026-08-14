import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 桌面单实例：文件排他锁。移动端允许多进程。
class SingleInstanceGuard {
  SingleInstanceGuard._();

  static RandomAccessFile? _lockHandle;

  static Future<bool> tryAcquire() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return true;
    }

    final lockPath = _lockFilePath();
    final file = File(lockPath);
    try {
      await file.parent.create(recursive: true);
      _lockHandle = await file.open(mode: FileMode.write);
      await _lockHandle!.lock(FileLock.exclusive);
      await _lockHandle!.setPosition(0);
      await _lockHandle!.truncate(0);
      await _lockHandle!.writeString('$pid\n');
      await _lockHandle!.flush();
      return true;
    } on FileSystemException {
      await _activateExisting();
      return false;
    }
  }

  static String _lockFilePath() {
    if (Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          Directory.systemTemp.path;
      return p.join(base, 'AstralNext', 'single_instance.lock');
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.astralnext', 'single_instance.lock');
    }
    return p.join(Directory.systemTemp.path, 'astral.single_instance.lock');
  }

  static Future<void> _activateExisting() async {
    if (Platform.isMacOS) {
      try {
        await Process.run('open', ['-a', 'Astral']);
      } catch (_) {}
    }
  }
}
