import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:astral/config/theme.dart';
import 'package:astral/data/state/theme_reveal_state.dart';
import 'package:astral/di.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class ThemeWaterDropHost extends StatefulWidget {
  const ThemeWaterDropHost({super.key, required this.child});

  final Widget child;

  @override
  State<ThemeWaterDropHost> createState() => _ThemeWaterDropHostState();
}

class _ThemeWaterDropHostState extends State<ThemeWaterDropHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final EffectCleanup _revealEffect;
  ThemeRevealState? _animatingReveal;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppThemeAnimation.revealDuration,
    )..addStatusListener(_onRevealStatus);

    _revealEffect = effect(() {
      final reveal = getIt<ThemeRevealController>().reveal.value;
      if (!reveal.isActive || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startReveal(reveal);
      });
    });
  }

  void _onRevealStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    getIt<ThemeRevealController>().finishReveal();
    if (mounted) {
      setState(() => _animatingReveal = null);
    }
  }

  @override
  void dispose() {
    _revealEffect();
    _controller.dispose();
    super.dispose();
  }

  void _startReveal(ThemeRevealState reveal) {
    if (_controller.isAnimating) {
      _controller.stop();
    }
    setState(() => _animatingReveal = reveal);
    _controller
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final animating = _animatingReveal;
    final showOverlay =
        animating != null && animating.isActive && animating.origin != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showOverlay && animating.previousThemeId != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final size = MediaQuery.sizeOf(context);
                  final origin = animating.origin!;
                  final maxR = _maxRevealRadius(origin, size);
                  final t = AppThemeAnimation.revealCurve
                      .transform(_controller.value);
                  final radius = maxR * t;
                  final palette =
                      AppThemePalette.of(animating.previousThemeId!);

                  return CustomPaint(
                    painter: _WaterDropOverlayPainter(
                      center: origin,
                      radius: radius,
                      fillColor: palette.background,
                      edgeColor: palette.accent.withValues(alpha: 0.22),
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

double _maxRevealRadius(Offset origin, Size size) {
  var maxDist = 0.0;
  for (final corner in [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ]) {
    maxDist = math.max(maxDist, (corner - origin).distance);
  }
  return maxDist + 8;
}

/// 旧主题遮罩：满屏填色 + 中心挖洞（避免每帧 Path.combine）。
class _WaterDropOverlayPainter extends CustomPainter {
  _WaterDropOverlayPainter({
    required this.center,
    required this.radius,
    required this.fillColor,
    required this.edgeColor,
  });

  final Offset center;
  final double radius;
  final Color fillColor;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = fillColor);
    if (radius > 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..blendMode = ui.BlendMode.clear,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = edgeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaterDropOverlayPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.center != center ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.edgeColor != edgeColor;
}
