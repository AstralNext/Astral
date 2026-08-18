import 'package:astral/data/models/instance_toml_config.dart';
import 'package:astral/data/services/toml_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default toml round-trips', () {
    final a = InstanceTomlConfig.defaults();
    final b = InstanceTomlConfig.fromToml(a.toToml());
    expect(b.sameAs(a), isTrue);
    expect(b.ipv4, '10.126.126.1/24');
    expect(b.dhcp, isFalse);
    expect(b.enableEncryption, isTrue);
    expect(b.mtu, '1380');
  });

  test('parses peers and flags', () {
    const src = '''
instance_name = "x"
dhcp = true
listeners = ["tcp://0.0.0.0:11010"]
routes = ["192.168.0.0/16"]

[network_identity]
network_name = "n"
network_secret = "s"

[[peer]]
uri = "tcp://1.2.3.4:11010"

[[proxy_network]]
cidr = "10.1.0.0/24"

[[port_forward]]
bind_addr = "0.0.0.0:11011"
dst_addr = "10.1.0.2:80"
proto = "tcp"

[flags]
disable_p2p = true
mtu = 1400
enable_kcp_proxy = true
lazy_p2p = true
encryption_algorithm = "chacha20"
''';
    final c = InstanceTomlConfig.fromToml(src);
    expect(c.instanceName, 'x');
    expect(c.dhcp, isTrue);
    expect(c.peerUris, ['tcp://1.2.3.4:11010']);
    expect(c.proxyCidrs, ['10.1.0.0/24']);
    expect(c.routes, ['192.168.0.0/16']);
    expect(c.portForwards.single.bindAddr, '0.0.0.0:11011');
    expect(c.disableP2p, isTrue);
    expect(c.enableKcpProxy, isTrue);
    expect(c.lazyP2p, isTrue);
    expect(c.encryptionAlgorithm, 'chacha20');
    expect(c.mtu, '1400');
    final out = c.toToml();
    expect(out, contains('[[peer]]'));
    expect(out, contains('[[port_forward]]'));
    expect(out, contains('lazy_p2p = true'));
    expect(out, isNot(contains('ipv4')));
  });

  test('reads instance_id from toml', () {
    const src = '''
instance_name = "a"
instance_id = "AEC401C7-E04F-4B57-A70B-E52E3A0C452A"
ipv4 = "10.126.126.1/24"
''';
    expect(
      TomlConfigService().readInstanceId(src),
      'AEC401C7-E04F-4B57-A70B-E52E3A0C452A',
    );
  });
}
