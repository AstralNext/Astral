part of 'package:astral/ui/pages/dashboard_page.dart';

/// 连接质量：延迟 / 丢包。
class _QualityCard extends StatelessWidget {
  final InstanceRuntimeStore runtimeStore;

  const _QualityCard({required this.runtimeStore});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Watch((context) {
      final m = runtimeStore.liveMetrics.value;
      final n = m.samplesWithNodes;
      final latency = m.avgLatencyMs;
      final loss = m.avgLossRate;

      Color health;
      String label;
      if (n == 0) {
        health = scheme.onSurfaceVariant;
        label = '暂无数据';
      } else if (latency < 80 && loss < 2) {
        health = scheme.primary;
        label = '良好';
      } else if (latency < 200 && loss < 8) {
        health = scheme.tertiary;
        label = '一般';
      } else {
        health = scheme.error;
        label = '较差';
      }

      return _DashboardCard(
        title: '连接质量',
        subtitle: label,
        trailing: Icon(Icons.network_check, size: 18, color: health),
        child: Row(
          children: [
            Expanded(
              child: _DashMetric(
                label: '延迟',
                value: n > 0 ? '${latency.toStringAsFixed(0)} ms' : '—',
                color: health,
              ),
            ),
            Expanded(
              child: _DashMetric(
                label: '丢包',
                value: n > 0 ? '${loss.toStringAsFixed(1)}%' : '—',
              ),
            ),
          ],
        ),
      );
    });
  }
}
