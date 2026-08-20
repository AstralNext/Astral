part of 'package:astral/ui/pages/dashboard_page.dart';

/// Dart 堆占用（对象 + external），不含引擎 / 内核 RSS。
class _MemoryCard extends StatefulWidget {
  const _MemoryCard();

  @override
  State<_MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<_MemoryCard> {
  Timer? _timer;
  int? _heapBytes;
  final List<double> _history = List<double>.filled(20, 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer(bool enabled) {
    if (enabled) {
      if (_timer != null) return;
      _sample();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _sample());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _sample() {
    unawaited(_sampleAsync());
  }

  Future<void> _sampleAsync() async {
    final bytes = await DartHeap.instance.sampleBytes();
    if (!mounted || bytes == null) return;
    setState(() {
      _heapBytes = bytes;
      for (var i = 0; i < _history.length - 1; i++) {
        _history[i] = _history[i + 1];
      }
      _history[_history.length - 1] = bytes.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final value = _heapBytes;

    return _DashboardCard(
      title: '内存信息',
      icon: Icons.memory_outlined,
      subtitle: 'Dart',
      contentPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value == null ? '—' : Formatters.bytes(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              painter: _SparklinePainter(
                data: _history,
                strokeColor: colorScheme.tertiary,
                fillColor: colorScheme.tertiary.withValues(alpha: 0.14),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}
