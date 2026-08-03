import 'package:astral/config/app_dimensions.dart';
import 'package:astral/config/theme.dart';
import 'package:flutter/material.dart';

export 'package:astral/config/theme.dart' show AstralSurfaceVariant;

class AstralCard extends StatelessWidget {
  const AstralCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppDimensions.radiusMd,
    this.variant = AstralSurfaceVariant.raised,
    this.emphasized = false,
    this.hovered = false,
    this.color,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final AstralSurfaceVariant variant;
  final bool emphasized;
  final bool hovered;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final borderRadius = BorderRadius.circular(radius);
    final fill = palette.surfaceColor(
      variant: variant,
      color: color,
      emphasized: emphasized,
      hovered: hovered,
    );

    Widget inner = child;
    if (padding != null) {
      inner = Padding(padding: padding!, child: inner);
    }

    // 必须用 Material 承载色，不能用 DecoratedBox：否则内部 ListTile
    // 的 ink 画在更上层 Material 上会被挡住，debug 下狂抛异常导致卡顿。
    if (onTap != null || onLongPress != null) {
      return Material(
        color: fill,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          splashColor: palette.accentMuted,
          highlightColor: palette.accent.withValues(alpha: 0.08),
          child: inner,
        ),
      );
    }

    return Material(
      color: fill,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: inner,
    );
  }
}

/// 带悬停 state layer 的可点击卡片。
class AstralHoverCard extends StatefulWidget {
  const AstralHoverCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppDimensions.radiusMd,
    this.variant = AstralSurfaceVariant.raised,
    this.color,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final AstralSurfaceVariant variant;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<AstralHoverCard> createState() => _AstralHoverCardState();
}

class _AstralHoverCardState extends State<AstralHoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AstralCard(
        padding: widget.padding,
        radius: widget.radius,
        variant: widget.variant,
        color: widget.color,
        hovered: _hovered,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.child,
      ),
    );
  }
}
