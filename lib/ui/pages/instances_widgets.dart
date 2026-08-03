part of 'instances_page.dart';

class _ReactiveInstanceCard extends StatefulWidget {
  final InstanceCatalogItem item;
  final InstanceRuntimeStore runtimeStore;
  final VoidCallback onToggleRun;
  final VoidCallback onOpenConfig;
  final VoidCallback onOpenLogs;
  final VoidCallback onOpenPeers;
  final VoidCallback? onDelete;

  const _ReactiveInstanceCard({
    super.key,
    required this.item,
    required this.runtimeStore,
    required this.onToggleRun,
    required this.onOpenConfig,
    required this.onOpenLogs,
    required this.onOpenPeers,
    this.onDelete,
  });

  @override
  State<_ReactiveInstanceCard> createState() => _ReactiveInstanceCardState();
}

class _ReactiveInstanceCardState extends State<_ReactiveInstanceCard> {
  late final ReadonlySignal<bool> _isRunning;
  late final ReadonlySignal<bool> _isStarting;
  late final ReadonlySignal<DateTime?> _startedAt;

  @override
  void initState() {
    super.initState();
    final path = widget.item.path;
    final store = widget.runtimeStore;
    _isRunning = computed(() => store.instanceIdByPath.value.containsKey(path));
    _isStarting = computed(() => store.startingPaths.value.contains(path));
    _startedAt = computed(() => store.startTimeByPath.value[path]);
  }

  @override
  void dispose() {
    _isRunning.dispose();
    _isStarting.dispose();
    _startedAt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isRunning = _isRunning.value;
      return _InstanceCard(
        item: widget.item,
        isRunning: isRunning,
        isStarting: _isStarting.value,
        startedAt: _startedAt.value,
        onToggleRun: widget.onToggleRun,
        onOpenConfig: widget.onOpenConfig,
        onOpenLogs: widget.onOpenLogs,
        onOpenPeers: isRunning ? widget.onOpenPeers : null,
        onDelete: widget.onDelete,
      );
    });
  }
}

class _InstanceCard extends StatefulWidget {
  final InstanceCatalogItem item;
  final VoidCallback? onToggleRun;
  final VoidCallback? onOpenConfig;
  final VoidCallback? onOpenLogs;
  final VoidCallback? onOpenPeers;
  final VoidCallback? onDelete;
  final bool isRunning;
  final bool isStarting;
  final DateTime? startedAt;

  const _InstanceCard({
    required this.item,
    this.onToggleRun,
    this.onOpenConfig,
    this.onOpenLogs,
    this.onOpenPeers,
    this.onDelete,
    this.isRunning = false,
    this.isStarting = false,
    this.startedAt,
  });

  @override
  State<_InstanceCard> createState() => _InstanceCardState();
}

class _InstanceCardState extends State<_InstanceCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final statusColor =
        widget.isRunning ? palette.accent : palette.textSecondary;
    final cardColor = widget.isRunning
        ? Color.alphaBlend(palette.accentMuted, palette.card)
        : palette.card;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isRunning && widget.onOpenPeers != null
              ? widget.onOpenPeers
              : null,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: palette.surfaceDecoration(
              radius: AppDimensions.radiusLg,
              color: cardColor,
              emphasized: widget.isRunning,
              hovered: _isHovered,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.developer_board_rounded,
                        color: palette.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (widget.isRunning)
                        Icon(
                          Icons.chevron_right,
                          color: palette.textSecondary,
                          size: 18,
                        ),
                      _MoreMenu(
                        enabled: !widget.isStarting,
                        onOpenConfig: widget.onOpenConfig,
                        onOpenLogs: widget.onOpenLogs,
                        onDelete: widget.onDelete,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.item.relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        widget.isRunning ? '运行中' : '未运行',
                        style: TextStyle(color: statusColor, fontSize: 11),
                      ),
                      const Spacer(),
                      if (widget.isStarting)
                        Text(
                          '正在启动…',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11.5,
                          ),
                        )
                      else if (widget.isRunning && widget.startedAt != null)
                        _UptimeLabel(
                          startedAt: widget.startedAt!,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: widget.isStarting ? null : widget.onToggleRun,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      icon: widget.isStarting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              widget.isRunning
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_circle_outlined,
                              size: 18,
                            ),
                      label: Text(
                        widget.isStarting
                            ? '启动中'
                            : (widget.isRunning ? '停止' : '启动'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onOpenConfig;
  final VoidCallback? onOpenLogs;
  final VoidCallback? onDelete;

  const _MoreMenu({
    required this.enabled,
    this.onOpenConfig,
    this.onOpenLogs,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    return PopupMenuButton<_InstanceAction>(
      tooltip: '更多',
      enabled: enabled,
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert,
        size: 18,
        color: palette.textSecondary,
      ),
      onSelected: (action) {
        switch (action) {
          case _InstanceAction.config:
            onOpenConfig?.call();
          case _InstanceAction.logs:
            onOpenLogs?.call();
          case _InstanceAction.delete:
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        if (onOpenConfig != null)
          const PopupMenuItem(
            value: _InstanceAction.config,
            child: Text('配置'),
          ),
        if (onOpenLogs != null)
          const PopupMenuItem(
            value: _InstanceAction.logs,
            child: Text('日志'),
          ),
        if (onDelete != null)
          const PopupMenuItem(
            value: _InstanceAction.delete,
            child: Text('删除'),
          ),
      ],
    );
  }
}

enum _InstanceAction { config, logs, delete }

class _UptimeLabel extends StatefulWidget {
  final DateTime startedAt;
  final TextStyle? style;

  const _UptimeLabel({
    required this.startedAt,
    this.style,
  });

  @override
  State<_UptimeLabel> createState() => _UptimeLabelState();
}

class _UptimeLabelState extends State<_UptimeLabel> {
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled) {
      if (_timer != null) return;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(DateTime startedAt) {
    final duration = DateTime.now().difference(startedAt);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(widget.startedAt),
      style: widget.style,
    );
  }
}
