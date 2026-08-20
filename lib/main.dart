import 'dart:io';
import 'dart:ui' as ui;

import 'package:astral/data/services/windows_startup_launch.dart';
import 'package:astral/di.dart';
import 'package:astral/utils/single_instance_guard.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ui.DartPluginRegistrant.ensureInitialized();

  if (!await SingleInstanceGuard.tryAcquire()) {
    return;
  }

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(940, 560),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions);
  }

  await setupDI();
  runApp(const AstralApp());

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    if (WindowsStartupLaunch.argsRequestMinimized()) {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }
}
