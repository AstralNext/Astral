import 'package:astral_rust_core/astral_rust_core.dart' show KVNodeInfo;

/// 节点是否视为直连（以 EasyTier [cost] 为准）。
bool isPeerDirectConnection(KVNodeInfo node) => node.cost <= 1;

/// 中继节点显示名；直连或无 hops 时返回空串。
String peerViaNodeLabel(KVNodeInfo node) {
  if (isPeerDirectConnection(node) || node.hops.isEmpty) return '';
  final viaHop = node.hops.first;
  return viaHop.nodeName.isNotEmpty ? viaHop.nodeName : viaHop.targetIp;
}
