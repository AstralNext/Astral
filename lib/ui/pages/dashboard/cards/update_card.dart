part of 'package:astral/ui/pages/dashboard_page.dart';

/// 应用版本与检查更新。
class _UpdateCard extends StatefulWidget {
  const _UpdateCard();

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await getIt<UpdateService>().getCurrentVersion();
    if (mounted) setState(() => _version = v);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final updateState = getIt<UpdateState>();
    final updateService = getIt<UpdateService>();

    return Watch((context) {
      final latest = updateState.latestVersion.value;
      final checking = updateState.isChecking.value;
      final hasNew = latest != null &&
          latest.trim().isNotEmpty &&
          _version.isNotEmpty &&
          updateService.isNewerThanCurrent(latest, currentVersion: _version);

      return _DashboardCard(
        title: '更新',
        subtitle: hasNew ? '发现新版本' : '当前已是跟进中',
        trailing: hasNew
            ? Icon(Icons.fiber_new_rounded, color: colorScheme.primary)
            : null,
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _version.isEmpty ? '读取中…' : 'v$_version',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasNew) ...[
                const SizedBox(height: 4),
                Text(
                  '最新 $latest',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ],
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: FilledButton.tonal(
                  onPressed: checking
                      ? null
                      : () => updateService.checkForUpdates(context),
                  child: Text(checking ? '检查中…' : '检查更新'),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
