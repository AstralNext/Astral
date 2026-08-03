import 'package:astral/ui/widgets/astral_card.dart';
import 'package:astral/ui/widgets/astral_grouped_tile.dart';
import 'package:flutter/material.dart';

class AstralSettingItem {
  const AstralSettingItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.subtitleMuted = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool subtitleMuted;
  final VoidCallback onTap;
}

/// MD3 设置分区：分类标题 + 抬升表面内的一组偏好项。
class AstralSettingsSection extends StatelessWidget {
  const AstralSettingsSection({
    super.key,
    required this.title,
    this.items,
    this.child,
  }) : assert(
          (items != null) ^ (child != null),
          'Provide either items or child',
        );

  final String title;
  final List<AstralSettingItem>? items;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        AstralCard(
          padding: EdgeInsets.zero,
          child: child ??
              Column(
                children: [
                  for (var i = 0; i < items!.length; i++)
                    AstralGroupedTile(
                      icon: items![i].icon,
                      label: items![i].label,
                      subtitle: items![i].subtitle,
                      subtitleMuted: items![i].subtitleMuted,
                      onTap: items![i].onTap,
                      index: i,
                      count: items!.length,
                    ),
                ],
              ),
        ),
      ],
    );
  }
}

/// 分区内开关项之间的分隔线（MD3 列表分割）。
class AstralSettingsDivider extends StatelessWidget {
  const AstralSettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
    );
  }
}

class AstralSettingsFormCard extends StatelessWidget {
  const AstralSettingsFormCard({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.leading,
  });

  final List<Widget> children;
  final String? title;
  final String? subtitle;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AstralCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  if (leading != null) ...[
                    Icon(leading, color: scheme.primary, size: 22),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (title != null) const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}
