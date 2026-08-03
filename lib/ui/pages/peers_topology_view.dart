import 'dart:math' as math;

import 'package:astral/ui/pages/instance_peers_helpers.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNodeInfo;
import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

/// 节点拓扑图：直连连本机；中继按 hops 串边。
class PeersTopologyView extends StatefulWidget {
  const PeersTopologyView({
    super.key,
    required this.nodes,
    required this.localLabel,
  });

  final List<KVNodeInfo> nodes;
  final String localLabel;

  @override
  State<PeersTopologyView> createState() => _PeersTopologyViewState();
}

class _PeersTopologyViewState extends State<PeersTopologyView> {
  late NodeFlowController<_PeerNodeData, dynamic> _controller;

  @override
  void initState() {
    super.initState();
    _controller = _buildController(widget.nodes);
  }

  @override
  void didUpdateWidget(covariant PeersTopologyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_fingerprint(oldWidget.nodes, oldWidget.localLabel) !=
        _fingerprint(widget.nodes, widget.localLabel)) {
      _controller.dispose();
      _controller = _buildController(widget.nodes);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fingerprint(List<KVNodeInfo> nodes, String localLabel) {
    final parts = <String>[localLabel];
    for (final n in nodes) {
      parts.add(
        '${n.peerId}:${n.cost}:${n.latencyMs.toStringAsFixed(0)}:'
        '${peerViaNodeLabel(n)}:${n.hops.map((h) => h.peerId).join('-')}',
      );
    }
    return parts.join('|');
  }

  NodeFlowController<_PeerNodeData, dynamic> _buildController(
    List<KVNodeInfo> peers,
  ) {
    const center = Offset(420, 320);
    const radius = 220.0;
    const localId = 'local';
    const nodeSize = Size(140, 72);

    final knownIds = {for (final p in peers) p.peerId};

    final nodes = <Node<_PeerNodeData>>[
      Node<_PeerNodeData>(
        id: localId,
        type: 'local',
        position: center - const Offset(70, 36),
        size: nodeSize,
        data: _PeerNodeData(
          title: widget.localLabel,
          subtitle: '本机',
          isLocal: true,
          isDirect: true,
        ),
        ports: [
          Port(
            id: 'out',
            name: 'out',
            position: PortPosition.right,
            offset: const Offset(0, 36),
            type: PortType.output,
          ),
          Port(
            id: 'in',
            name: 'in',
            position: PortPosition.left,
            offset: const Offset(0, 36),
            type: PortType.input,
          ),
        ],
      ),
    ];

    final connections = <Connection>[];
    final edgeKeys = <String>{};
    final n = peers.length;
    for (var i = 0; i < n; i++) {
      final peer = peers[i];
      final angle = n == 1 ? -math.pi / 2 : (2 * math.pi * i / n) - math.pi / 2;
      final pos = Offset(
        center.dx + radius * math.cos(angle) - 70,
        center.dy + radius * math.sin(angle) - 36,
      );
      final id = 'peer_${peer.peerId}';
      final direct = isPeerDirectConnection(peer);
      final title = peer.hostname.isNotEmpty ? peer.hostname : peer.ipv4;
      nodes.add(
        Node<_PeerNodeData>(
          id: id,
          type: 'peer',
          position: pos,
          size: nodeSize,
          data: _PeerNodeData(
            title: title,
            subtitle: direct
                ? '${peer.latencyMs.toStringAsFixed(0)} ms'
                : '经 ${peerViaNodeLabel(peer)}',
            isLocal: false,
            isDirect: direct,
          ),
          ports: [
            Port(
              id: 'in',
              name: 'in',
              position: PortPosition.left,
              offset: const Offset(0, 36),
              type: PortType.input,
            ),
            Port(
              id: 'out',
              name: 'out',
              position: PortPosition.right,
              offset: const Offset(0, 36),
              type: PortType.output,
            ),
          ],
        ),
      );

      if (direct) {
        _addEdge(edgeKeys, connections, localId, id);
      } else {
        final hopIds = peer.hops
            .map((h) => h.peerId)
            .where((pid) => pid != peer.peerId && knownIds.contains(pid))
            .toList();
        if (hopIds.isEmpty) {
          _addEdge(edgeKeys, connections, localId, id);
        } else {
          var prev = localId;
          for (final hopPid in hopIds) {
            final hopId = 'peer_$hopPid';
            _addEdge(edgeKeys, connections, prev, hopId);
            prev = hopId;
          }
          _addEdge(edgeKeys, connections, prev, id);
        }
      }
    }

    return NodeFlowController<_PeerNodeData, dynamic>(
      nodes: nodes,
      connections: connections,
    );
  }

  void _addEdge(
    Set<String> edgeKeys,
    List<Connection> connections,
    String from,
    String to,
  ) {
    if (from == to) return;
    final key = '$from->$to';
    if (!edgeKeys.add(key)) return;
    connections.add(
      Connection(
        id: 'c_${from}_$to',
        sourceNodeId: from,
        sourcePortId: 'out',
        targetNodeId: to,
        targetPortId: 'in',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return NodeFlowEditor<_PeerNodeData, dynamic>(
      controller: _controller,
      theme: isDark ? NodeFlowTheme.dark : NodeFlowTheme.light,
      nodeBuilder: (context, node) {
        final data = node.data;
        final scheme = Theme.of(context).colorScheme;
        final accent = data.isLocal
            ? scheme.primary
            : (data.isDirect ? scheme.tertiary : Colors.orange);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: accent),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PeerNodeData {
  const _PeerNodeData({
    required this.title,
    required this.subtitle,
    required this.isLocal,
    required this.isDirect,
  });

  final String title;
  final String subtitle;
  final bool isLocal;
  final bool isDirect;
}
