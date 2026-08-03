part of 'package:astral/ui/pages/dashboard_page.dart';

class _UptimeCard extends StatelessWidget {
  final InstanceRuntimeStore runtimeStore;

  const _UptimeCard({required this.runtimeStore});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final times = runtimeStore.startTimeByPath.value.values;
      if (times.isEmpty) {
        return const _DashboardCard(
          title: '运行时长',
          subtitle: '暂无运行中实例',
          child: SizedBox.shrink(),
        );
      }
      final oldest = times.reduce((a, b) => a.isBefore(b) ? a : b);
      final d = DateTime.now().difference(oldest);
      final text = d.inHours > 0
          ? '${d.inHours}h ${d.inMinutes % 60}m'
          : '${d.inMinutes}m';
      return _DashboardCard(
        title: '运行时长',
        subtitle: '最早实例',
        child: _DashMetric(label: '已运行', value: text),
      );
    });
  }
}
