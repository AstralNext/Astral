part of 'package:astral/ui/pages/dashboard_page.dart';

class _UptimeCard extends StatefulWidget {
  final InstanceRuntimeStore runtimeStore;

  const _UptimeCard({required this.runtimeStore});

  @override
  State<_UptimeCard> createState() => _UptimeCardState();
}

class _UptimeCardState extends State<_UptimeCard> {
  Timer? _tick;

  InstanceRuntimeStore get _store => widget.runtimeStore;

  @override
  void initState() {
    super.initState();
    unawaited(_store.refreshStartedTimesFromKernel());
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final runningCount = _store.instanceIdByPath.value.length;
      final times = _store.startTimeByPath.value.values.toList();

      if (runningCount == 0) {
        return const _DashboardCard(
          title: '运行时长',
          icon: Icons.timer_outlined,
          subtitle: '暂无运行中实例',
          child: SizedBox.shrink(),
        );
      }

      if (times.isEmpty) {
        return const _DashboardCard(
          title: '运行时长',
          icon: Icons.timer_outlined,
          subtitle: '等待内核同步',
          child: _DashMetric(label: '已运行', value: '—'),
        );
      }

      final oldest = times.reduce((a, b) => a.isBefore(b) ? a : b);
      final text = Formatters.duration(DateTime.now().difference(oldest));
      return _DashboardCard(
        title: '运行时长',
        icon: Icons.timer_outlined,
        subtitle: runningCount > 1 ? '$runningCount 个在跑' : '当前实例',
        child: _DashMetric(label: '已运行', value: text),
      );
    });
  }
}
