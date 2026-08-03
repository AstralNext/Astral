part of 'package:astral/ui/pages/dashboard_page.dart';

class _NodesPulseCard extends StatelessWidget {
  final InstanceRuntimeStore runtimeStore;

  const _NodesPulseCard({required this.runtimeStore});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final nodes = runtimeStore.liveMetrics.value.nodeCount;
      final running = runtimeStore.liveMetrics.value.runningCount;
      return _DashboardCard(
        title: '节点',
        subtitle: '运行中 $running',
        child: _DashMetric(
          label: '可见节点',
          value: '$nodes',
        ),
      );
    });
  }
}
