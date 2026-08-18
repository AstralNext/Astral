import 'package:astral/di.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral/ui/pages/instance_peers_helpers.dart';
import 'package:astral/ui/pages/peers_topology_view.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNodeInfo;
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:signals/signals_flutter.dart';

enum _ViewMode { list, topology }

class InstancePeersPage extends StatefulWidget {
  final String instancePath;
  final String instanceName;

  const InstancePeersPage({
    super.key,
    required this.instancePath,
    required this.instanceName,
  });

  @override
  State<InstancePeersPage> createState() => _InstancePeersPageState();
}

class _InstancePeersPageState extends State<InstancePeersPage> {
  late final InstanceRuntimeStore _runtimeStore;
  _ViewMode _viewMode = _ViewMode.list;

  @override
  void initState() {
    super.initState();
    _runtimeStore = getIt<InstanceRuntimeStore>();
  }

  String _formatBytes(BigInt bytes) {
    final value = bytes.toInt();
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool _isDirectConnection(KVNodeInfo node) => isPeerDirectConnection(node);

  String _getViaNode(KVNodeInfo node) => peerViaNodeLabel(node);

  int _resolveColumns(double width) {
    if (width >= 1600) {
      return 4;
    }
    if (width >= 1200) {
      return 3;
    }
    if (width >= 700) {
      return 2;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((context) {
      final status = _runtimeStore.networkStatusByPath.value[widget.instancePath];
      var nodes = [...?status?.nodes];
      if (nodes.isEmpty && _runtimeStore.isRunning(widget.instancePath)) {
        nodes = [localPeerPlaceholder(hostname: widget.instanceName)];
      }

      if (nodes.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.devices_other_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                '暂无节点信息',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '实例可能未运行或未连接到网络',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '节点信息',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${nodes.length} 个节点',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<_ViewMode>(
                  segments: const [
                    ButtonSegment(
                      value: _ViewMode.list,
                      icon: Icon(Icons.list, size: 18),
                      label: Text('列表'),
                    ),
                    ButtonSegment(
                      value: _ViewMode.topology,
                      icon: Icon(Icons.account_tree_outlined, size: 18),
                      label: Text('拓扑'),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (mode) {
                    setState(() => _viewMode = mode.first);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _viewMode == _ViewMode.list
                ? _buildGridView(context, nodes)
                : PeersTopologyView(
                    nodes: nodes.where((n) => !isLocalPeer(n)).toList(),
                    localLabel: widget.instanceName,
                  ),
          ),
        ],
      );
    });
  }

  Widget _buildGridView(BuildContext context, List<KVNodeInfo> nodes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = _resolveColumns(constraints.maxWidth);

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              sliver: SliverMasonryGrid(
                gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                ),
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildNodeCard(context, nodes[index]),
                  childCount: nodes.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNodeCard(BuildContext context, KVNodeInfo node) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLocal = isLocalPeer(node);
    final isConnected = isLocal || node.latencyMs > 0;
    final isDirect = _isDirectConnection(node);
    final viaNode = _getViaNode(node);
    final badge = isLocal ? '本机' : (isDirect ? '直连' : '中转');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isLocal
                        ? colorScheme.primary
                        : isConnected
                        ? (isDirect ? colorScheme.primary : Colors.orange)
                        : colorScheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.hostname.isNotEmpty ? node.hostname : node.ipv4,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLocal || isDirect
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: isLocal || isDirect
                          ? colorScheme.onPrimaryContainer
                          : Colors.orange.shade800,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.language, size: 12, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  node.ipv4,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (viaNode.isNotEmpty) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(
                    Icons.alt_route,
                    size: 12,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '通过 $viaNode 中转',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildInfoChip(
                  context,
                  icon: Icons.timer_outlined,
                  value: isLocal
                      ? '—'
                      : '${node.latencyMs.toStringAsFixed(1)}ms',
                ),
                _buildInfoChip(
                  context,
                  icon: Icons.warning_amber_outlined,
                  value: '${node.lossRate.toStringAsFixed(2)}%',
                ),
                _buildInfoChip(
                  context,
                  icon: Icons.router_outlined,
                  value: node.nat,
                ),
                _buildInfoChip(
                  context,
                  icon: Icons.cable_outlined,
                  value: node.connType,
                ),
                _buildInfoChip(
                  context,
                  icon: Icons.download_outlined,
                  value: _formatBytes(node.rxBytes),
                ),
                _buildInfoChip(
                  context,
                  icon: Icons.upload_outlined,
                  value: _formatBytes(node.txBytes),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            value,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

