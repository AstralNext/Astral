import 'package:astral/config/app_theme_id.dart';
import 'package:astral/data/state/settings_state.dart';
import 'package:astral/di.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals.dart';

class ThemePickResult {
  const ThemePickResult(this.themeId, this.origin);

  final AppThemeId themeId;
  final Offset origin;
}

class ThemeRevealState {
  const ThemeRevealState._({this.origin, this.previousThemeId});

  const ThemeRevealState.idle() : this._();

  const ThemeRevealState.revealing({
    required Offset origin,
    required AppThemeId previousThemeId,
  }) : this._(origin: origin, previousThemeId: previousThemeId);

  final Offset? origin;
  final AppThemeId? previousThemeId;

  bool get isActive => previousThemeId != null;
}

class ThemeRevealController {
  final reveal = signal(const ThemeRevealState.idle());

  void beginReveal({required Offset origin, required AppThemeId newTheme}) {
    final settings = getIt<SettingsState>();
    final previous = settings.appThemeId.value;
    if (previous == newTheme) return;

    settings.appThemeId.value = newTheme;
    reveal.value = ThemeRevealState.revealing(
      origin: origin,
      previousThemeId: previous,
    );
  }

  void finishReveal() {
    if (!reveal.value.isActive) return;
    reveal.value = const ThemeRevealState.idle();
  }
}
