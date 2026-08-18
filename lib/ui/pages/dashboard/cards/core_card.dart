part of 'package:astral/ui/pages/dashboard_page.dart';

/// 软件版本与内核版本。
class _CoreCard extends StatefulWidget {
  const _CoreCard();

  @override
  State<_CoreCard> createState() => _CoreCardState();
}

class _CoreCardState extends State<_CoreCard> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _cleanEtVersion(String raw) {
    var s = raw.trim();
    final lower = s.toLowerCase();
    if (lower.startsWith('easytier')) {
      s = s.substring('easytier'.length).trim();
    }
    if (s.startsWith('-') || s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1).trim();
    }
    return s.isEmpty ? raw.trim() : s;
  }

  Future<void> _load() async {
    String app = '';
    try {
      app = await getIt<UpdateService>().getCurrentVersion();
    } catch (_) {
      app = '—';
    }
    if (!mounted) return;
    setState(() => _appVersion = app);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Watch((context) {
      final fromStore = getIt<InstanceRuntimeStore>().version.value.trim();
      final app = _appVersion.isEmpty
          ? '—'
          : (_appVersion.startsWith('v') ? _appVersion : 'v$_appVersion');
      final et = fromStore.isEmpty ? '—' : _cleanEtVersion(fromStore);

      Widget row(String label, String value) {
        return Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        );
      }

      return _DashboardCard(
        title: '内核',
        subtitle: '内核版本',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [row('软件', app), const SizedBox(height: 8), row('ET', et)],
        ),
      );
    });
  }
}
