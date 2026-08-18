part of 'package:astral/ui/pages/dashboard_page.dart';

/// 面板「节点信息」：绑定单个实例，紧凑列出主机名 / IP / 延迟 / 直连或中转。
class _PeerInfoCard extends StatelessWidget {
  final String? instancePath;
  final List<InstanceCatalogItem> items;
  final InstanceRuntimeStore runtimeStore;
  final VoidCallback onBind;
  final VoidCallback onOpenPeers;

  const _PeerInfoCard({
    super.key,
    required this.instancePath,
    required this.items,
    required this.runtimeStore,
    required this.onBind,
    required this.onOpenPeers,
  });

  InstanceCatalogItem? get _bound {
    final path = instancePath?.trim();
    if (path == null || path.isEmpty) return null;
    for (final item in items) {
      if (item.path == path) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final scheme = Theme.of(context).colorScheme;
      final bound = _bound;
      final path = bound?.path ?? instancePath?.trim();
      final hasBinding = path != null && path.isNotEmpty;
      final running = hasBinding && runtimeStore.isRunning(path);
      var nodes = hasBinding
          ? (runtimeStore.networkStatusByPath.value[path]?.nodes ??
                const <KVNodeInfo>[])
          : const <KVNodeInfo>[];
      if (running && nodes.isEmpty) {
        nodes = [localPeerPlaceholder(hostname: bound?.name ?? '本机')];
      }
      final sorted = [...nodes]
        ..sort((a, b) {
          final an = a.hostname.isNotEmpty ? a.hostname : a.ipv4;
          final bn = b.hostname.isNotEmpty ? b.hostname : b.ipv4;
          return an.toLowerCase().compareTo(bn.toLowerCase());
        });

      final title = bound?.name ?? '节点信息';
      final String subtitle;
      if (!hasBinding) {
        subtitle = '未绑定实例';
      } else if (!running) {
        subtitle = '实例未运行';
      } else {
        subtitle = '${sorted.length} 个节点';
      }

      return _DashboardCard(
        title: title,
        subtitle: subtitle,
        onTitleTap: hasBinding ? onOpenPeers : onBind,
        trailing: IconButton(
          tooltip: hasBinding ? '更换实例' : '绑定实例',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: onBind,
          icon: Icon(
            hasBinding ? Icons.swap_horiz : Icons.link,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _buildBody(context, scheme, hasBinding, running, sorted),
      );
    });
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme scheme,
    bool hasBinding,
    bool running,
    List<KVNodeInfo> nodes,
  ) {
    if (!hasBinding) {
      return _PeerInfoEmpty(
        icon: Icons.link,
        message: '选择一个实例，在面板上查看它的节点',
        actionLabel: '绑定实例',
        onAction: onBind,
      );
    }
    if (!running) {
      return _PeerInfoEmpty(
        icon: Icons.play_circle_outline,
        message: '启动实例后会显示节点列表',
        actionLabel: '打开节点页',
        onAction: onOpenPeers,
      );
    }
    if (nodes.isEmpty) {
      return _PeerInfoEmpty(
        icon: Icons.devices_other_outlined,
        message: '暂无节点，点标题查看详情',
        actionLabel: '打开节点页',
        onAction: onOpenPeers,
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: nodes.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.6),
      ),
      itemBuilder: (_, i) => _PeerInfoRow(node: nodes[i]),
    );
  }
}

class _PeerInfoEmpty extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _PeerInfoEmpty({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _PeerInfoRow extends StatelessWidget {
  final KVNodeInfo node;

  const _PeerInfoRow({required this.node});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLocal = isLocalPeer(node);
    final isConnected = isLocal || node.latencyMs > 0;
    final isDirect = isPeerDirectConnection(node);
    final via = peerViaNodeLabel(node);
    final name = node.hostname.isNotEmpty ? node.hostname : node.ipv4;
    final latency = isLocal
        ? '本机'
        : isConnected
        ? '${node.latencyMs.toStringAsFixed(0)} ms'
        : '—';
    final badge = isLocal ? '本机' : (isDirect ? '直连' : '中转');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isLocal
                  ? scheme.primary
                  : isConnected
                  ? (isDirect ? scheme.primary : Colors.orange)
                  : scheme.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  via.isNotEmpty ? '${node.ipv4} · 经 $via' : node.ipv4,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            latency,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
            color: isLocal || isDirect
                ? scheme.primaryContainer.withValues(alpha: 0.5)
                : Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badge,
            style: TextStyle(
              color: isLocal || isDirect
                  ? scheme.onPrimaryContainer
                  : Colors.orange.shade800,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
