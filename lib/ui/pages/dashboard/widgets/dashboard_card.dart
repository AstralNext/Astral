part of 'package:astral/ui/pages/dashboard_page.dart';

class _DashboardCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTitleTap;
  final EdgeInsetsGeometry contentPadding;

  const _DashboardCard({
    required this.title,
    required this.child,
    this.subtitle = '',
    this.icon,
    this.trailing,
    this.onTitleTap,
    this.contentPadding = const EdgeInsets.fromLTRB(14, 0, 14, 12),
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  static const _headerPadding = EdgeInsets.fromLTRB(14, 12, 14, 0);
  static const _contentSpacing = 8.0;

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final radius = BorderRadius.circular(AppDimensions.radiusLg);
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
                child: _DashboardCardHeader(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  icon: widget.icon,
                  trailing: widget.trailing,
                  onTap: widget.onTitleTap,
                  titleColor: palette.textPrimary,
                  subtitleColor: palette.textSecondary,
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

class _DashboardCardHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color titleColor;
  final Color subtitleColor;

  const _DashboardCardHeader({
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.subtitleColor,
    this.icon,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: subtitleColor),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, size: 16, color: subtitleColor),
              ],
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: subtitleColor, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}
