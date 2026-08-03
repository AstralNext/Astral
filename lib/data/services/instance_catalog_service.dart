import 'dart:io';

import 'package:astral/data/services/platform_path_service.dart';
import 'package:astral/data/services/toml_config_service.dart';
import 'package:path/path.dart' as p;

class InstanceCatalogSnapshot {
  final String rootPath;
  final List<InstanceCatalogItem> items;

  const InstanceCatalogSnapshot({required this.rootPath, required this.items});
}

class InstanceCatalogItem {
  final String path;
  final String name;
  final String fileName;
  final String relativePath;

  const InstanceCatalogItem({
    required this.path,
    required this.name,
    required this.fileName,
    required this.relativePath,
  });
}

/// 本机实例配置目录。
class InstanceCatalogService {
  InstanceCatalogService(this._pathService, this._tomlService);

  final PlatformPathService _pathService;
  final TomlConfigService _tomlService;

  Future<InstanceCatalogSnapshot> loadSnapshot() => _loadLocalSnapshot();

  Future<String?> readToml(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  Future<void> writeToml(String path, String toml) async {
    await File(path).writeAsString(toml);
  }

  Future<String> createInstanceFile(String name) async {
    final dir = await ensureInstancesDirPath();
    return createFile(
      directoryPath: dir,
      name: name,
      appendTomlWhenMissing: true,
      withTomlTemplate: true,
    );
  }

  Future<String> createFile({
    required String directoryPath,
    required String name,
    bool appendTomlWhenMissing = true,
    bool withTomlTemplate = true,
  }) async {
    if (!isValidName(name)) {
      throw const FormatException('File name cannot contain path separators.');
    }
    var fileName = name.trim();
    if (appendTomlWhenMissing && !fileName.contains('.')) {
      fileName = ensureTomlName(fileName);
    }

    final parent = _normalizePath(directoryPath);
    final root = _normalizePath(await ensureInstancesDirPath());
    if (!_isWithinRoot(root, parent)) {
      throw const FileSystemException('Target directory is outside of root.');
    }
    final path = '$parent${Platform.pathSeparator}$fileName';
    final file = File(path);
    if (await file.exists()) {
      throw StateError('File already exists.');
    }
    await file.create(recursive: true);
    if (withTomlTemplate && fileName.toLowerCase().endsWith('.toml')) {
      await file.writeAsString(_tomlService.defaultToml());
    }
    return file.path;
  }

  Future<void> deleteEntry(String path) async {
    final root = _normalizePath(await ensureInstancesDirPath());
    final normalized = _normalizePath(path);
    if (!_isWithinRoot(root, normalized)) {
      throw const FileSystemException('Path is outside of root.');
    }
    final type = FileSystemEntity.typeSync(normalized);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(normalized).delete(recursive: true);
        return;
      case FileSystemEntityType.file:
        await File(normalized).delete();
        return;
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
      case FileSystemEntityType.link:
      case FileSystemEntityType.notFound:
        throw const FileSystemException('Entry does not exist.');
    }
  }

  bool isValidName(String name) {
    return !name.contains('/') && !name.contains('\\');
  }

  String ensureTomlName(String name) {
    final trimmed = name.trim();
    return trimmed.toLowerCase().endsWith('.toml') ? trimmed : '$trimmed.toml';
  }

  String basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  Future<String> ensureInstancesDirPath() async {
    return await _defaultInstancesDirPath();
  }

  Future<String> _defaultInstancesDirPath() async {
    final configDir = await _pathService.configDir();
    final srcDir = Directory('${configDir.path}${Platform.pathSeparator}src');
    if (!await srcDir.exists()) {
      await srcDir.create(recursive: true);
    }
    return srcDir.path;
  }

  Future<InstanceCatalogSnapshot> _loadLocalSnapshot() async {
    final rootPath = await ensureInstancesDirPath();
    final srcDir = Directory(rootPath);
    final items = <InstanceCatalogItem>[];
    await for (final entity in srcDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.toml')) {
        continue;
      }
      final displayName = basename(entity.path).replaceAll('.toml', '');
      items.add(
        InstanceCatalogItem(
          path: entity.path,
          name: displayName,
          fileName: basename(entity.path),
          relativePath: _relativePath(rootPath, entity.path),
        ),
      );
    }
    items.sort(
      (a, b) =>
          a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()),
    );
    return InstanceCatalogSnapshot(rootPath: rootPath, items: items);
  }

  String _relativePath(String rootPath, String fullPath) {
    final root = _normalizePath(rootPath);
    final full = _normalizePath(fullPath);
    if (full == root) return '';
    if (full.startsWith('$root/')) {
      return full.substring(root.length + 1);
    }
    return fullPath;
  }

  String _normalizePath(String path) {
    final absolute = p.normalize(
      p.isAbsolute(path) ? path : p.absolute(path),
    );
    final type = FileSystemEntity.typeSync(absolute, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      try {
        final resolved = type == FileSystemEntityType.directory
            ? Directory(absolute).resolveSymbolicLinksSync()
            : File(absolute).resolveSymbolicLinksSync();
        return p.normalize(resolved).replaceAll('\\', '/');
      } catch (_) {}
    }
    return absolute.replaceAll('\\', '/');
  }

  bool _isWithinRoot(String rootPath, String targetPath) {
    if (targetPath == rootPath) return true;
    final root = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    return targetPath.startsWith(root);
  }
}
