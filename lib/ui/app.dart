import 'dart:async';
import 'dart:io';

import 'package:astral/config/theme.dart';
import 'package:astral/data/state/settings_state.dart';
import 'package:astral/di.dart';
import 'package:astral/ui/shell/shell.dart';
import 'package:astral/ui/widgets/theme_water_drop_overlay.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class AstralApp extends StatefulWidget {
  const AstralApp({super.key});

  @override
  State<AstralApp> createState() => _AstralAppState();
}

class _AstralAppState extends State<AstralApp> with WidgetsBindingObserver {
  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 桌面退出走 exit(0)，不在此处停内核。
    if (!_isDesktop) {
      unawaited(disposeDI());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 移动端进程将死：尽量开停机（回调无法 await，disposeDI 幂等且先 stopAll）。
    if (!_isDesktop && state == AppLifecycleState.detached) {
      unawaited(disposeDI());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = getIt<SettingsState>();

    return Watch((context) {
      final theme = AstralTheme.build(settingsState.appThemeId.value);

      return MaterialApp(
        title: 'Astral',
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeAnimationDuration: AppThemeAnimation.duration,
        themeAnimationCurve: AppThemeAnimation.curve,
        builder: (context, child) =>
            ThemeWaterDropHost(child: child ?? const SizedBox.shrink()),
        home: const Shell(),
      );
    });
  }
}
