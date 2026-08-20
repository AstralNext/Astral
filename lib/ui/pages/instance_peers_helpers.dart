import 'package:astral_rust_core/astral_rust_core.dart' show KVNodeInfo;

/// 本机合成节点（无对端时列表里也应有自己）。
bool isLocalPeer(KVNodeInfo node) {
  final conn = node.connType.trim().toLowerCase();
  return node.cost == 0 || conn == 'local' || node.peerId == 0;
}

/// 节点是否视为直连（以 EasyTier [cost] 为准；本机不算直连/中转）。
bool isPeerDirectConnection(KVNodeInfo node) =>
    !isLocalPeer(node) && node.cost <= 1;

/// 中继节点显示名；直连、本机或无 hops 时返回空串。
String peerViaNodeLabel(KVNodeInfo node) {
  if (isLocalPeer(node) || isPeerDirectConnection(node) || node.hops.isEmpty) {
    return '';
  }
  final viaHop = node.hops.first;
  return viaHop.nodeName.isNotEmpty ? viaHop.nodeName : viaHop.targetIp;
}

/// 列表主标题：优先主机名，否则 IPv4。
String peerDisplayName(KVNodeInfo node) {
  final name = node.hostname.trim();
  if (name.isNotEmpty) return name;
  final ip = node.ipv4.trim();
  return ip.isEmpty ? '未知节点' : ip;
}

/// 延迟文案：本机 / N ms / —。
String peerLatencyLabel(KVNodeInfo node) {
  if (isLocalPeer(node)) return '本机';
  if (node.latencyMs > 0) return '${node.latencyMs.toStringAsFixed(0)} ms';
  return '—';
}

/// 本机占位（轮询尚未返回或内核未带本机时）。
KVNodeInfo localPeerPlaceholder({
  String hostname = '本机',
  String ipv4 = '',
  String ipv6 = '',
}) {
  return KVNodeInfo(
    peerId: 0,
    hostname: hostname.trim().isEmpty ? '本机' : hostname.trim(),
    ipv4: ipv4,
    ipv6: ipv6,
    latencyMs: 0,
    nat: '',
    hops: const [],
    lossRate: 0,
    connections: const [],
    tunnelProto: '-',
    connType: 'local',
    rxBytes: BigInt.zero,
    txBytes: BigInt.zero,
    version: '',
    cost: 0,
    remoteStaticPubkeyB64: '',
    isCredentialPeer: false,
  );
}
