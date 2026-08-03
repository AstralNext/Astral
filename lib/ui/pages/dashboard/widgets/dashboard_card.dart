part of 'package:astral/ui/pages/dashboard_page.dart';

class _DashboardCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;

  const _DashboardCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
    this.contentPadding = const EdgeInsets.fromLTRB(18, 0, 18, 18),
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  static const _headerPadding = EdgeInsets.fromLTRB(18, 18, 18, 0);
  static const _contentSpacing = 12.0;

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final radius = BorderRadius.circular(AppDimensions.radiusMd);
    final fill = palette.surfaceColor(hovered: _isHovered);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Material(
          color: fill,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: _headerPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.subtitle,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.trailing != null) widget.trailing!,
                  ],
                ),
              ),
              const SizedBox(height: _contentSpacing),
              Expanded(
                child: Padding(
                  padding: widget.contentPadding,
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
