import 'package:flutter/material.dart';

/// 系统字体查找顺序：有 Noto 用 Noto；Noto 缺中文或未安装则落到雅黑，再不行用系统默认。
abstract final class AppFonts {
  static const family = 'Noto Sans';

  static const fallbacks = <String>[
    'Noto Sans SC',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
  ];

  static TextStyle apply([TextStyle? base]) {
    return (base ?? const TextStyle()).copyWith(
      fontFamily: family,
      fontFamilyFallback: fallbacks,
    );
  }

  static TextTheme applyTextTheme(TextTheme theme) {
    TextStyle? wrap(TextStyle? style) =>
        style == null ? null : apply(style);

    return theme.copyWith(
      displayLarge: wrap(theme.displayLarge),
      displayMedium: wrap(theme.displayMedium),
      displaySmall: wrap(theme.displaySmall),
      headlineLarge: wrap(theme.headlineLarge),
      headlineMedium: wrap(theme.headlineMedium),
      headlineSmall: wrap(theme.headlineSmall),
      titleLarge: wrap(theme.titleLarge),
      titleMedium: wrap(theme.titleMedium),
      titleSmall: wrap(theme.titleSmall),
      bodyLarge: wrap(theme.bodyLarge),
      bodyMedium: wrap(theme.bodyMedium),
      bodySmall: wrap(theme.bodySmall),
      labelLarge: wrap(theme.labelLarge),
      labelMedium: wrap(theme.labelMedium),
      labelSmall: wrap(theme.labelSmall),
    );
  }
}
