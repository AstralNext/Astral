part of 'package:astral/ui/pages/dashboard_page.dart';

class _TrafficCard extends StatelessWidget {
  final InstanceRuntimeStore runtimeStore;

  const _TrafficCard({
    required this.runtimeStore,
  });

  String _formatRate(double bytesPerSec) {
    final bitsPerSec = bytesPerSec * 8;
    if (bitsPerSec < 1000) {
      return '${bitsPerSec.toStringAsFixed(0)} bps';
    } else if (bitsPerSec < 1000 * 1000) {
      return '${(bitsPerSec / 1000).toStringAsFixed(1)} Kbps';
    } else if (bitsPerSec < 1000 * 1000 * 1000) {
      return '${(bitsPerSec / (1000 * 1000)).toStringAsFixed(1)} Mbps';
    } else {
      return '${(bitsPerSec / (1000 * 1000 * 1000)).toStringAsFixed(1)} Gbps';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((context) {
      final m = runtimeStore.liveMetrics.value;
      return _DashboardCard(
        title: '流量',
        subtitle: '合计上下行',
        child: Row(
          children: [
            Expanded(
              child: _DashMetric(
                label: '下行',
                value: _formatRate(m.rxRate),
                color: colorScheme.primary,
              ),
            ),
            Expanded(
              child: _DashMetric(
                label: '上行',
                value: _formatRate(m.txRate),
                color: colorScheme.tertiary,
              ),
            ),
          ],
        ),
      );
    });
  }
}
