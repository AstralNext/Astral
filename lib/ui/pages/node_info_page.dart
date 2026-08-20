import 'dart:io';

import 'package:astral/config/app_dimensions.dart';
import 'package:astral/config/theme.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral/di.dart';
import 'package:astral/ui/pages/instance_peers_helpers.dart';
import 'package:astral/ui/pages/peers_topology_view.dart';
import 'package:astral/ui/shell/shell_navigation_controller.dart';
import 'package:astral/ui/widgets/astral_card.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNodeInfo;
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

enum _NodeInfoView { cards, topology }

/// 节点信息 Tab。Android 同时只跑一个实例，直接展示节点，不经过实例目录。
class NodeInfoPage extends StatefulWidget {
  const NodeInfoPage({super.key});

  @override
  State<NodeInfoPage> createState() => _NodeInfoPageState();
}

class _NodeInfoPageState extends State<NodeInfoPage> {
  late final InstanceRuntimeStore _runtimeStore;
  String? _selectedPath;
  _NodeInfoView _view = _NodeInfoView.cards;

  @override
  void initState() {
    super.initState();
    _runtimeStore = getIt<InstanceRuntimeStore>();
  }

  bool get _androidSingleInstance => Platform.isAndroid;

  String _labelFromPath(String path) {
    final base = path.split(Platform.pathSeparator).last;
    const suffix = '.toml';
    if (base.toLowerCase().endsWith(suffix)) {
      return base.substring(0, base.length - suffix.length);
    }
    return base;
  }

  List<String> _runningPaths() =>
      _runtimeStore.instanceIdByPath.value.keys.toList();

  String? _resolvePath(List<String> running) {
    if (running.isEmpty) return null;
    if (_androidSingleInstance || running.length == 1) return running.first;
    final current = _selectedPath;
    if (current != null && running.contains(current)) return current;
    return running.first;
  }

  List<KVNodeInfo> _nodesFor(String path, String name) {
    final nodes = <KVNodeInfo>[
      ...?_runtimeStore.networkStatusByPath.value[path]?.nodes,
    ];
    if (nodes.isEmpty && _runtimeStore.isRunning(path)) {
      nodes.add(localPeerPlaceholder(hostname: name));
    }
    nodes.sort((a, b) {
      return peerDisplayName(a).toLowerCase().compareTo(
            peerDisplayName(b).toLowerCase(),
          );
    });
    return nodes;
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final running = _runningPaths();
      final path = _resolvePath(running);
      final name = path == null ? '' : _labelFromPath(path);
      final nodes = path == null ? const <KVNodeInfo>[] : _nodesFor(path, name);

      if (running.isEmpty) {
        return const _NodeInfoEmpty();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _NodeInfoToolbar(
              nodeCount: nodes.length,
              showInstancePicker: !_androidSingleInstance && running.length > 1,
              runningPaths: running,
              selectedPath: path,
              labelOf: _labelFromPath,
              onSelect: (value) => setState(() => _selectedPath = value),
              view: _view,
              onView: (value) => setState(() => _view = value),
            ),
          ),
          Expanded(
            child: _view == _NodeInfoView.topology
                ? PeersTopologyView(
                    nodes: nodes.where((n) => !isLocalPeer(n)).toList(),
                    localLabel: name,
                  )
                : _NodeCardGrid(nodes: nodes),
          ),
        ],
      );
    });
  }
}

class _NodeInfoToolbar extends StatelessWidget {
  const _NodeInfoToolbar({
    required this.nodeCount,
    required this.showInstancePicker,
    required this.runningPaths,
    required this.selectedPath,
    required this.labelOf,
    required this.onSelect,
    required this.view,
    required this.onView,
  });

  final int nodeCount;
  final bool showInstancePicker;
  final List<String> runningPaths;
  final String? selectedPath;
  final String Function(String path) labelOf;
  final ValueChanged<String> onSelect;
  final _NodeInfoView view;
  final ValueChanged<_NodeInfoView> onView;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$nodeCount 个节点',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            SegmentedButton<_NodeInfoView>(
              segments: const [
                ButtonSegment(
                  value: _NodeInfoView.cards,
                  icon: Icon(Icons.grid_view_outlined, size: 18),
                  label: Text('节点'),
                ),
                ButtonSegment(
                  value: _NodeInfoView.topology,
                  icon: Icon(Icons.account_tree_outlined, size: 18),
                  label: Text('拓扑'),
                ),
              ],
              selected: {view},
              onSelectionChanged: (mode) => onView(mode.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        if (showInstancePicker) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final path in runningPaths)
                ChoiceChip(
                  label: Text(labelOf(path)),
                  selected: path == selectedPath,
                  onSelected: (_) => onSelect(path),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NodeCardGrid extends StatelessWidget {
  const _NodeCardGrid({required this.nodes});

  final List<KVNodeInfo> nodes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 4
            : width >= 720
                ? 3
                : width >= AppDimensions.narrowBreakpoint
                    ? 2
                    : 1;
        const spacing = 12.0;
        final cardWidth = (width - 40 - spacing * (columns - 1)) / columns;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final node in nodes)
                  SizedBox(
                    width: cardWidth,
                    child: _NodeSummaryCard(node: node),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _NodeInfoEmpty extends StatelessWidget {
  const _NodeInfoEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lan_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无运行中的实例',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '到实例页启动后，这里会列出主机名、IP 和延迟',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () {
                getIt<ShellNavigationController>().navigateTo(
                  ShellTab.instances,
                );
              },
              icon: const Icon(Icons.developer_board_outlined),
              label: const Text('去实例页'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeSummaryCard extends StatelessWidget {
  const _NodeSummaryCard({required this.node});

  final KVNodeInfo node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.astralPalette;
    final isLocal = isLocalPeer(node);
    final connected = isLocal || node.latencyMs > 0;
    final name = peerDisplayName(node);
    final ip = node.ipv4.trim().isEmpty ? '—' : node.ipv4.trim();
    final latency = peerLatencyLabel(node);
    final Color latencyColor;
    if (isLocal) {
      latencyColor = scheme.primary;
    } else if (!connected) {
      latencyColor = scheme.onSurfaceVariant;
    } else if (node.latencyMs < 80) {
      latencyColor = scheme.primary;
    } else if (node.latencyMs < 200) {
      latencyColor = scheme.tertiary;
    } else {
      latencyColor = scheme.error;
    }

    return AstralCard(
      radius: AppDimensions.radiusLg,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLocal ? Icons.home_outlined : Icons.language,
                size: 16,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ip,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            latency,
            style: TextStyle(
              color: latencyColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
