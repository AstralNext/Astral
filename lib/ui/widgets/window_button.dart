import 'package:flutter/material.dart';

class WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final double width;
  final double height;
  final Color? hoverColor;
  final Color? iconColor;
  final VoidCallback onTap;

  const WindowButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconSize = 14,
    this.width = 46,
    this.height = 32,
    this.hoverColor,
    this.iconColor,
  });

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = _hovering
        ? (widget.hoverColor ?? colorScheme.surfaceContainerHighest)
        : Colors.transparent;
    final foregroundColor = widget.iconColor ?? colorScheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          height: widget.height,
          color: backgroundColor,
          alignment: Alignment.center,
          child: Icon(widget.icon, size: widget.iconSize, color: foregroundColor),
        ),
      ),
    );
  }
}
