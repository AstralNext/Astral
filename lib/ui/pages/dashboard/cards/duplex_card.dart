part of 'package:astral/ui/pages/dashboard_page.dart';

class _DuplexCard extends StatelessWidget {
  final InstanceRuntimeStore runtimeStore;

  const _DuplexCard({required this.runtimeStore});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final m = runtimeStore.liveMetrics.value;
      return _DashboardCard(
        title: '上下行',
        subtitle: '实时速率',
        child: Row(
          children: [
            Expanded(
              child: _DashMetric(
                label: '下行',
                value: _fmtRate(m.rxRate),
              ),
            ),
            Expanded(
              child: _DashMetric(
                label: '上行',
                value: _fmtRate(m.txRate),
              ),
            ),
          ],
        ),
      );
    });
  }

  String _fmtRate(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(0)} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }
}
