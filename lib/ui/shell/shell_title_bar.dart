import 'dart:async';

import 'package:astral/config/theme.dart';
import 'package:astral/ui/widgets/window_button.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面自定义标题栏（拖拽、最小化 / 最大化 / 关闭）。
class ShellTitleBar extends StatefulWidget {
  final double height;
  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  const ShellTitleBar({
    super.key,
    required this.height,
    required this.title,
    required this.onClose,
    this.showBackButton = false,
    this.onBack,
  });

  @override
  State<ShellTitleBar> createState() => _ShellTitleBarState();
}

class _ShellTitleBarState extends State<ShellTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(
      windowManager.isMaximized().then((v) {
        if (mounted) setState(() => _isMaximized = v);
      }),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (!_isMaximized && mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (_isMaximized && mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    unawaited(
      windowManager.isMaximized().then((v) {
        if (mounted && _isMaximized != v) {
          setState(() => _isMaximized = v);
        }
      }),
    );
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.restore();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final sidebarColor = palette.sidebar;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: SizedBox(
        height: widget.height,
        child: Container(
          color: sidebarColor,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (widget.showBackButton)
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: palette.textPrimary,
                    size: 20,
                  ),
                  onPressed: widget.onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                )
              else
                const SizedBox(width: 36),
              Expanded(
                child: Center(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 36),
              WindowButton(
                icon: Icons.remove,
                iconSize: 16,
                hoverColor: palette.accentMuted,
                iconColor: palette.textPrimary,
                onTap: () => windowManager.minimize(),
              ),
              WindowButton(
                icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                iconSize: 14,
                hoverColor: palette.accentMuted,
                iconColor: palette.textPrimary,
                onTap: () => unawaited(_toggleMaximize()),
              ),
              WindowButton(
                icon: Icons.close,
                iconSize: 16,
                hoverColor: palette.error.withValues(alpha: 0.2),
                iconColor: palette.textPrimary,
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 窄屏 overlay 顶栏。
class ShellCompactOverlayAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const ShellCompactOverlayAppBar({
    super.key,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return Container(
      height: 56,
      color: palette.background,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: palette.textPrimary,
            ),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}
