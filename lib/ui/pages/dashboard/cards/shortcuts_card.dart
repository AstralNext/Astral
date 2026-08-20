part of 'package:astral/ui/pages/dashboard_page.dart';

/// 快捷入口：实例 / 节点信息 / 设置。
class _ShortcutsCard extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _ShortcutsCard({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget cell({
      required IconData icon,
      required String label,
      required int tab,
    }) {
      return Expanded(
        child: InkWell(
          onTap: () => onNavigate(tab),
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: scheme.primary, size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _DashboardCard(
      title: '快捷入口',
      icon: Icons.apps_outlined,
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          cell(
            icon: Icons.developer_board_outlined,
            label: '实例',
            tab: ShellTab.instances,
          ),
          cell(
            icon: Icons.lan_outlined,
            label: '节点',
            tab: ShellTab.nodeInfo,
          ),
          cell(
            icon: Icons.settings_outlined,
            label: '设置',
            tab: ShellTab.settings,
          ),
        ],
      ),
    );
  }
}
