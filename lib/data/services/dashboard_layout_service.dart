import 'dart:io';

import 'package:astral/data/services/platform_path_service.dart';
import 'package:astral/ui/pages/dashboard/models/dashboard_layout.dart';

class DashboardLayoutService {
  DashboardLayoutService(this._paths);

  final PlatformPathService _paths;
  static const _fileName = 'dashboard_layout.json';

  Future<File> get _file async {
    final dir = await _paths.configDir();
    return File('${dir.path}/$_fileName');
  }

  Future<DashboardLayout> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) {
        return DashboardLayout.defaultLayout;
      }
      return DashboardLayout.fromJson(await file.readAsString());
    } catch (_) {
      return DashboardLayout.defaultLayout;
    }
  }

  Future<void> save(DashboardLayout layout) async {
    try {
      final file = await _file;
      await file.writeAsString(layout.toJson());
    } catch (_) {}
  }

  Future<void> reset() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
