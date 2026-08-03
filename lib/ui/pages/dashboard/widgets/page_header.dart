part of 'package:astral/ui/pages/dashboard_page.dart';

class _PageHeader extends StatelessWidget {
  final int instanceCount;
  final int runningCount;
  final bool isEditingLayout;
  final VoidCallback? onEditLayout;
  final VoidCallback? onAddCard;
  final VoidCallback? onResetLayout;
  final bool canAddCard;

  const _PageHeader({
    required this.instanceCount,
    required this.runningCount,
    required this.isEditingLayout,
    this.onEditLayout,
    this.onAddCard,
    this.onResetLayout,
    this.canAddCard = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            isEditingLayout
                ? '拖拽排序 · 点 − 删除 · 可添加卡片'
                : '$instanceCount 个实例 · $runningCount 运行中',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        if (isEditingLayout && onResetLayout != null) ...[
          IconButton.outlined(
            onPressed: onResetLayout,
            icon: const Icon(Icons.restart_alt),
            tooltip: '恢复默认布局',
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (isEditingLayout && onAddCard != null) ...[
          IconButton.outlined(
            onPressed: canAddCard ? onAddCard : null,
            icon: const Icon(Icons.add),
            tooltip: '添加卡片',
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (onEditLayout != null)
          isEditingLayout
              ? FilledButton.icon(
                  onPressed: onEditLayout,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('完成'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                )
              : IconButton.outlined(
                  onPressed: onEditLayout,
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  tooltip: '编辑布局',
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
      ],
    );
  }
}
