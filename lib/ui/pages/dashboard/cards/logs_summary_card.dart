part of 'package:astral/ui/pages/dashboard_page.dart';

/// 日志摘要：最近错误 / 警告（仅告警流触发刷新，避免 info 刷屏）。
class _LogsSummaryCard extends StatefulWidget {
  final VoidCallback onOpenInstances;

  const _LogsSummaryCard({required this.onOpenInstances});

  @override
  State<_LogsSummaryCard> createState() => _LogsSummaryCardState();
}

class _LogsSummaryCardState extends State<_LogsSummaryCard> {
  StreamSubscription<LogEntry>? _sub;
  List<LogEntry> _recent = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refreshFromHistory();
    _sub = getIt<LogService>().alertStream.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _refreshFromHistory();
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _refreshFromHistory() {
    final recent = getIt<LogService>().recentAlerts(limit: 8);
    setState(() => _recent = recent);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent = _recent;
    final preview = recent.take(2).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (recent.isEmpty) {
            widget.onOpenInstances();
            return;
          }
          getIt<ShellContentController>().showOverlay(
            title: '最近告警',
            content: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final e = recent[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e.level} · ${e.module}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.message,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        child: _DashboardCard(
          title: '日志摘要',
          icon: Icons.article_outlined,
          subtitle: recent.isEmpty ? '暂无告警' : '${recent.length} 条近期',
          trailing: Icon(
            Icons.chevron_right,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          child: recent.isEmpty
              ? Text(
                  '运行正常，无近期错误或警告',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in preview)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          e.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
