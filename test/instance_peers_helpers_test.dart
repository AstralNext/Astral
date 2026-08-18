import 'package:astral/ui/pages/instance_peers_helpers.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNodeInfo;
import 'package:flutter_test/flutter_test.dart';

KVNodeInfo _node({
  int peerId = 1,
  int cost = 1,
  String connType = 'p2p',
}) {
  return KVNodeInfo(
    peerId: peerId,
    hostname: 'n',
    ipv4: '10.0.0.1',
    ipv6: '',
    latencyMs: 1,
    nat: '',
    hops: const [],
    lossRate: 0,
    connections: const [],
    tunnelProto: '',
    connType: connType,
    rxBytes: BigInt.zero,
    txBytes: BigInt.zero,
    version: '',
    cost: cost,
    remoteStaticPubkeyB64: '',
    isCredentialPeer: false,
  );
}

void main() {
  test('local peer is not treated as p2p/relay', () {
    final local = _node(peerId: 0, cost: 0, connType: 'local');
    expect(isLocalPeer(local), isTrue);
    expect(isPeerDirectConnection(local), isFalse);
    expect(peerViaNodeLabel(local), isEmpty);
  });

  test('p2p is direct, relay is not', () {
    expect(isPeerDirectConnection(_node(cost: 1, connType: 'p2p')), isTrue);
    expect(isPeerDirectConnection(_node(cost: 2, connType: 'relay')), isFalse);
  });
}
