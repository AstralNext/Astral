import 'dart:async';

import 'package:astral/data/services/log_service.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral/di.dart';
import 'package:astral/ui/widgets/astral_confirm_dialog.dart';
import 'package:flutter/material.dart';

class InstanceLogsPage extends StatefulWidget {
  final String instancePath;
  final String instanceName;

  const InstanceLogsPage({
    super.key,
    required this.instancePath,
    required this.instanceName,
  });

  @override
  State<InstanceLogsPage> createState() => _InstanceLogsPageState();
}

class _InstanceLogsPageState extends State<InstanceLogsPage> {
  late final LogService _logService;
  late final List<LogEntry> _logs;
  StreamSubscription<LogEntry>? _subscription;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _logService = getIt<LogService>();
    _logs = _logService.getHistoryForInstance(widget.instancePath);
    _subscription = _logService.stream.listen(_onNewLog);
    _importKernelHistory();
  }

  Future<void> _importKernelHistory() async {
    if (!getIt.isRegistered<InstanceRuntimeStore>()) return;
    final store = getIt<InstanceRuntimeStore>();
    final instanceId = store.getInstanceId(widget.instancePath);
    if (instanceId == null || instanceId.isEmpty) return;
    await _subscription?.cancel();
    await store.importKernelLogsForInstance(
      instancePath: widget.instancePath,
      instanceId: instanceId,
    );
    if (!mounted) return;
    setState(() {
      _logs
        ..clear()
        ..addAll(_logService.getHistoryForInstance(widget.instancePath));
    });
    _subscription = _logService.stream.listen(_onNewLog);
    _scrollToBottom();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNewLog(LogEntry entry) {
    if (entry.instancePath == widget.instancePath) {
      setState(() {
        _logs.add(entry);
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _clearLogs() async {
    if (_logs.isEmpty) return;
    final ok = await showAstralConfirm(
      context,
      title: '清空日志？',
      message: '将清除「${widget.instanceName}」的运行日志，此操作不可撤销。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _logs.clear();
      _logService.clearForInstance(widget.instancePath);
    });
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_logs.isEmpty) {
      return _buildEmptyState(colorScheme);
    }
    return _buildLogList(colorScheme);
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '暂无日志记录',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '启动实例后将在此显示运行日志',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              return _LogRow(
                entry: _logs[index],
                formatTime: _formatTime,
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                '共 ${_logs.length} 条日志',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearLogs,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空日志'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  final String Function(DateTime) formatTime;

  const _LogRow({
    required this.entry,
    required this.formatTime,
  });

  Color _badgeColor(ColorScheme scheme) {
    if (entry.level.contains('error') || entry.level.contains('ERROR')) {
      return scheme.error;
    }
    if (entry.level.contains('warning') || entry.level.contains('WARN')) {
      return scheme.tertiary;
    }
    return scheme.primary;
  }

  String _levelText() {
    final level = entry.level.toLowerCase();
    if (level.contains('error')) return 'ERROR';
    if (level.contains('warning')) return 'WARN';
    if (level.contains('debug')) return 'DEBUG';
    return 'INFO';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeColor = _badgeColor(colorScheme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              _levelText(),
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatTime(entry.time),
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
