import 'dart:io';

import 'package:astral/di.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘图标与菜单。
class ShellTrayController {
  ShellTrayController(this._tray);

  final TrayManager _tray;

  Future<void> init() async {
    final String iconPath;
    if (Platform.isWindows) {
      iconPath = await _ensureTrayIconFile(
        preferredAssetPath: 'assets/icon.ico',
        fallbackAssetPath: 'assets/logo.png',
        outputFileName: 'astral_tray_icon',
      );
    } else {
      iconPath = await _ensureTrayIconFile(
        preferredAssetPath: 'assets/logo.png',
        fallbackAssetPath: 'assets/logo.png',
        outputFileName: 'astral_tray_icon',
      );
    }

    await _tray.setIcon(iconPath);
    if (!Platform.isLinux) {
      await _tray.setToolTip('Astral');
    }
    await _tray.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: '显示主界面'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// 先等内核/VPN 停干净，再关窗。
  Future<void> exitApp() async {
    await disposeDI();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<String> _ensureTrayIconFile({
    required String preferredAssetPath,
    required String fallbackAssetPath,
    required String outputFileName,
  }) async {
    final tmpDir = await getTemporaryDirectory();

    Future<String> writeAsset(String assetPath, String ext) async {
      final bytes = await rootBundle.load(assetPath);
      final file = File(
        '${tmpDir.path}${Platform.pathSeparator}$outputFileName$ext',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return file.path;
    }

    try {
      final ext =
          preferredAssetPath.toLowerCase().endsWith('.ico') ? '.ico' : '.png';
      return await writeAsset(preferredAssetPath, ext);
    } catch (_) {
      final ext =
          fallbackAssetPath.toLowerCase().endsWith('.ico') ? '.ico' : '.png';
      return await writeAsset(fallbackAssetPath, ext);
    }
  }
}
