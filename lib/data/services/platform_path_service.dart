import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 平台路径：应用配置目录。
class PlatformPathService {
  /// 配置目录，可选子目录。
  ///
  /// Windows 上使用系统级共享目录 `C:\ProgramData\nextAstral`，
  /// 与 astral-core 服务端 `config::paths::discover()` 对齐，
  /// 保证 LocalSystem 服务可读写实例配置。
  /// 其它平台沿用应用支持目录。
  Future<Directory> configDir({String? subDir}) async {
    final base = await _baseDir();
    return _ensureDir(_withSubDir(base, subDir));
  }

  Future<Directory> _baseDir() async {
    if (Platform.isWindows) {
      final programData =
          Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
      return Directory(p.join(programData, 'nextAstral'));
    }
    return getApplicationSupportDirectory();
  }

  Directory _withSubDir(Directory base, String? subDir) {
    if (subDir == null || subDir.trim().isEmpty) {
      return base;
    }
    return Directory('${base.path}${Platform.pathSeparator}$subDir');
  }

  Future<Directory> _ensureDir(Directory dir) async {
    if (await dir.exists()) {
      return dir;
    }
    await dir.create(recursive: true);
    return dir;
  }
}
