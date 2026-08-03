import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 平台路径：应用配置目录。
class PlatformPathService {
  /// 配置目录（Application Support），可选子目录。
  Future<Directory> configDir({String? subDir}) async {
    final base = await getApplicationSupportDirectory();
    return _ensureDir(_withSubDir(base, subDir));
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
