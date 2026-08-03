import 'package:toml/toml.dart';

/// EasyTier 端口转发项。
class PortForwardEntry {
  PortForwardEntry({
    this.bindAddr = '',
    this.dstAddr = '',
    this.proto = 'tcp',
  });

  String bindAddr;
  String dstAddr;
  String proto;

  PortForwardEntry copy() => PortForwardEntry(
        bindAddr: bindAddr,
        dstAddr: dstAddr,
        proto: proto,
      );
}

/// EasyTier 实例 TOML 表单模型（对齐引擎 `Config` + `FlagsInConfig`）。
class InstanceTomlConfig {
  InstanceTomlConfig({
    this.instanceName = 'default',
    this.hostname = '',
    this.dhcp = false,
    this.ipv4 = '10.126.126.1/24',
    this.ipv6 = '',
    List<String>? listeners,
    List<String>? mappedListeners,
    List<String>? exitNodes,
    List<String>? routes,
    this.socks5Proxy = '',
    List<String>? tcpWhitelist,
    List<String>? udpWhitelist,
    List<String>? stunServers,
    List<String>? stunServersV6,
    this.networkName = 'astral',
    this.networkSecret = 'astral',
    List<String>? peerUris,
    List<String>? proxyCidrs,
    List<PortForwardEntry>? portForwards,
    this.vpnClientCidr = '',
    this.vpnWireguardListen = '',
    // flags
    this.defaultProtocol = 'tcp',
    this.devName = 'astral',
    this.enableEncryption = true,
    this.enableIpv6 = true,
    this.mtu = '1380',
    this.latencyFirst = false,
    this.enableExitNode = false,
    this.proxyForwardBySystem = false,
    this.noTun = false,
    this.useSmoltcp = false,
    this.relayNetworkWhitelist = '*',
    this.disableP2p = false,
    this.p2pOnly = false,
    this.lazyP2p = false,
    this.needP2p = false,
    this.relayAllPeerRpc = false,
    this.disableTcpHolePunching = false,
    this.disableUdpHolePunching = false,
    this.disableSymHolePunching = false,
    this.multiThread = true,
    this.multiThreadCount = '2',
    this.dataCompressAlgo = 1, // 1=None, 2=Zstd
    this.bindDevice = true,
    this.enableKcpProxy = false,
    this.disableKcpInput = false,
    this.disableRelayKcp = false,
    this.enableRelayForeignNetworkKcp = false,
    this.enableQuicProxy = false,
    this.disableQuicInput = false,
    this.disableRelayQuic = false,
    this.enableRelayForeignNetworkQuic = false,
    this.acceptDns = false,
    this.tldDnsZone = 'et.net.',
    this.privateMode = false,
    this.foreignRelayBpsLimit = '',
    this.instanceRecvBpsLimit = '',
    this.encryptionAlgorithm = '',
    this.disableUpnp = false,
    this.disableRelayData = false,
    this.enableUdpBroadcastRelay = false,
  })  : listeners = List<String>.from(
          listeners ?? const ['tcp://0.0.0.0:0', 'udp://0.0.0.0:0'],
        ),
        mappedListeners = List<String>.from(mappedListeners ?? const []),
        exitNodes = List<String>.from(exitNodes ?? const []),
        routes = List<String>.from(routes ?? const []),
        tcpWhitelist = List<String>.from(tcpWhitelist ?? const []),
        udpWhitelist = List<String>.from(udpWhitelist ?? const []),
        stunServers = List<String>.from(stunServers ?? const []),
        stunServersV6 = List<String>.from(stunServersV6 ?? const []),
        peerUris = List<String>.from(peerUris ?? const []),
        proxyCidrs = List<String>.from(proxyCidrs ?? const []),
        portForwards = [
          for (final e in portForwards ?? const <PortForwardEntry>[]) e.copy(),
        ];

  String instanceName;
  String hostname;
  bool dhcp;
  String ipv4;
  String ipv6;
  List<String> listeners;
  List<String> mappedListeners;
  List<String> exitNodes;
  List<String> routes;
  String socks5Proxy;
  List<String> tcpWhitelist;
  List<String> udpWhitelist;
  List<String> stunServers;
  List<String> stunServersV6;
  String networkName;
  String networkSecret;
  List<String> peerUris;
  List<String> proxyCidrs;
  List<PortForwardEntry> portForwards;
  String vpnClientCidr;
  String vpnWireguardListen;

  String defaultProtocol;
  String devName;
  bool enableEncryption;
  bool enableIpv6;
  String mtu;
  bool latencyFirst;
  bool enableExitNode;
  bool proxyForwardBySystem;
  bool noTun;
  bool useSmoltcp;
  String relayNetworkWhitelist;
  bool disableP2p;
  bool p2pOnly;
  bool lazyP2p;
  bool needP2p;
  bool relayAllPeerRpc;
  bool disableTcpHolePunching;
  bool disableUdpHolePunching;
  bool disableSymHolePunching;
  bool multiThread;
  String multiThreadCount;
  int dataCompressAlgo;
  bool bindDevice;
  bool enableKcpProxy;
  bool disableKcpInput;
  bool disableRelayKcp;
  bool enableRelayForeignNetworkKcp;
  bool enableQuicProxy;
  bool disableQuicInput;
  bool disableRelayQuic;
  bool enableRelayForeignNetworkQuic;
  bool acceptDns;
  String tldDnsZone;
  bool privateMode;
  String foreignRelayBpsLimit;
  String instanceRecvBpsLimit;
  String encryptionAlgorithm;
  bool disableUpnp;
  bool disableRelayData;
  bool enableUdpBroadcastRelay;

  factory InstanceTomlConfig.defaults() => InstanceTomlConfig();

  factory InstanceTomlConfig.fromToml(String source) {
    final map = TomlDocument.parse(source).toMap();
    final identity = _asMap(map['network_identity']);
    final flags = _asMap(map['flags']);
    final peers = _asList(map['peer']);
    final proxies = _asList(map['proxy_network']);
    final forwards = _asList(map['port_forward']);
    final vpn = _asMap(map['vpn_portal_config']);

    return InstanceTomlConfig(
      instanceName: _str(map['instance_name'], 'default'),
      hostname: _str(map['hostname'], ''),
      dhcp: _bool(map['dhcp'], false),
      ipv4: _str(map['ipv4'], '10.126.126.1/24'),
      ipv6: _str(map['ipv6'], ''),
      listeners: _stringList(map['listeners'], const [
        'tcp://0.0.0.0:0',
        'udp://0.0.0.0:0',
      ]),
      mappedListeners: _stringList(map['mapped_listeners'], const []),
      exitNodes: _stringList(map['exit_nodes'], const []),
      routes: _stringList(map['routes'], const []),
      socks5Proxy: _str(map['socks5_proxy'], ''),
      tcpWhitelist: _stringList(map['tcp_whitelist'], const []),
      udpWhitelist: _stringList(map['udp_whitelist'], const []),
      stunServers: _stringList(map['stun_servers'], const []),
      stunServersV6: _stringList(map['stun_servers_v6'], const []),
      networkName: _str(identity['network_name'], 'astral'),
      networkSecret: _str(identity['network_secret'], 'astral'),
      peerUris: [
        for (final p in peers) _str(_asMap(p)['uri'], ''),
      ].where((u) => u.isNotEmpty).toList(),
      proxyCidrs: [
        for (final p in proxies) _str(_asMap(p)['cidr'], ''),
      ].where((c) => c.isNotEmpty).toList(),
      portForwards: [
        for (final f in forwards)
          PortForwardEntry(
            bindAddr: _str(_asMap(f)['bind_addr'], ''),
            dstAddr: _str(_asMap(f)['dst_addr'], ''),
            proto: _str(_asMap(f)['proto'], 'tcp'),
          ),
      ].where((e) => e.bindAddr.isNotEmpty && e.dstAddr.isNotEmpty).toList(),
      vpnClientCidr: _str(vpn['client_cidr'], ''),
      vpnWireguardListen: _str(vpn['wireguard_listen'], ''),
      defaultProtocol: _str(flags['default_protocol'], 'tcp'),
      devName: _str(flags['dev_name'], 'astral'),
      enableEncryption: _bool(flags['enable_encryption'], true),
      enableIpv6: _bool(flags['enable_ipv6'], true),
      mtu: flags['mtu'] == null ? '1380' : '${flags['mtu']}',
      latencyFirst: _bool(flags['latency_first'], false),
      enableExitNode: _bool(flags['enable_exit_node'], false),
      proxyForwardBySystem: _bool(flags['proxy_forward_by_system'], false),
      noTun: _bool(flags['no_tun'], false),
      useSmoltcp: _bool(flags['use_smoltcp'], false),
      relayNetworkWhitelist: _str(flags['relay_network_whitelist'], '*'),
      disableP2p: _bool(flags['disable_p2p'], false),
      p2pOnly: _bool(flags['p2p_only'], false),
      lazyP2p: _bool(flags['lazy_p2p'], false),
      needP2p: _bool(flags['need_p2p'], false),
      relayAllPeerRpc: _bool(flags['relay_all_peer_rpc'], false),
      disableTcpHolePunching: _bool(flags['disable_tcp_hole_punching'], false),
      disableUdpHolePunching: _bool(flags['disable_udp_hole_punching'], false),
      disableSymHolePunching: _bool(flags['disable_sym_hole_punching'], false),
      multiThread: _bool(flags['multi_thread'], true),
      multiThreadCount:
          flags['multi_thread_count'] == null ? '2' : '${flags['multi_thread_count']}',
      dataCompressAlgo: _int(flags['data_compress_algo'], 1),
      bindDevice: _bool(flags['bind_device'], true),
      enableKcpProxy: _bool(flags['enable_kcp_proxy'], false),
      disableKcpInput: _bool(flags['disable_kcp_input'], false),
      disableRelayKcp: _bool(flags['disable_relay_kcp'], false),
      enableRelayForeignNetworkKcp:
          _bool(flags['enable_relay_foreign_network_kcp'], false),
      enableQuicProxy: _bool(flags['enable_quic_proxy'], false),
      disableQuicInput: _bool(flags['disable_quic_input'], false),
      disableRelayQuic: _bool(flags['disable_relay_quic'], false),
      enableRelayForeignNetworkQuic:
          _bool(flags['enable_relay_foreign_network_quic'], false),
      acceptDns: _bool(flags['accept_dns'], false),
      tldDnsZone: _str(flags['tld_dns_zone'], 'et.net.'),
      privateMode: _bool(flags['private_mode'], false),
      foreignRelayBpsLimit: _bpsFromToml(flags['foreign_relay_bps_limit']),
      instanceRecvBpsLimit: _bpsFromToml(flags['instance_recv_bps_limit']),
      encryptionAlgorithm: _str(flags['encryption_algorithm'], ''),
      disableUpnp: _bool(flags['disable_upnp'], false),
      disableRelayData: _bool(flags['disable_relay_data'], false),
      enableUdpBroadcastRelay: _bool(flags['enable_udp_broadcast_relay'], false),
    );
  }

  /// 生成稳定、可读的 TOML（保存时覆盖整文件）。
  String toToml() {
    final buf = StringBuffer();
    buf.writeln(
      'instance_name = ${_q(instanceName.trim().isEmpty ? 'default' : instanceName.trim())}',
    );
    final host = hostname.trim();
    if (host.isNotEmpty) {
      buf.writeln('hostname = ${_q(host)}');
    }
    buf.writeln('dhcp = $dhcp');
    final ip = ipv4.trim();
    if (!dhcp && ip.isNotEmpty) {
      buf.writeln('ipv4 = ${_q(ip)}');
    }
    final v6 = ipv6.trim();
    if (v6.isNotEmpty) {
      buf.writeln('ipv6 = ${_q(v6)}');
    }
    _writeStringArray(buf, 'listeners', listeners);
    _writeStringArray(buf, 'mapped_listeners', mappedListeners);
    _writeStringArray(buf, 'exit_nodes', exitNodes);
    _writeStringArray(buf, 'routes', routes);
    final socks = socks5Proxy.trim();
    if (socks.isNotEmpty) {
      buf.writeln('socks5_proxy = ${_q(socks)}');
    }
    _writeStringArray(buf, 'tcp_whitelist', tcpWhitelist);
    _writeStringArray(buf, 'udp_whitelist', udpWhitelist);
    _writeStringArray(buf, 'stun_servers', stunServers);
    _writeStringArray(buf, 'stun_servers_v6', stunServersV6);
    buf.writeln();
    buf.writeln('[network_identity]');
    buf.writeln('network_name = ${_q(networkName.trim())}');
    buf.writeln('network_secret = ${_q(networkSecret)}');
    buf.writeln();

    for (final uri in peerUris.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      buf.writeln('[[peer]]');
      buf.writeln('uri = ${_q(uri)}');
      buf.writeln();
    }

    for (final cidr
        in proxyCidrs.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      buf.writeln('[[proxy_network]]');
      buf.writeln('cidr = ${_q(cidr)}');
      buf.writeln();
    }

    for (final pf in portForwards) {
      final bind = pf.bindAddr.trim();
      final dst = pf.dstAddr.trim();
      if (bind.isEmpty || dst.isEmpty) continue;
      buf.writeln('[[port_forward]]');
      buf.writeln('bind_addr = ${_q(bind)}');
      buf.writeln('dst_addr = ${_q(dst)}');
      buf.writeln(
        'proto = ${_q(pf.proto.trim().isEmpty ? 'tcp' : pf.proto.trim())}',
      );
      buf.writeln();
    }

    final vpnCidr = vpnClientCidr.trim();
    final vpnListen = vpnWireguardListen.trim();
    if (vpnCidr.isNotEmpty && vpnListen.isNotEmpty) {
      buf.writeln('[vpn_portal_config]');
      buf.writeln('client_cidr = ${_q(vpnCidr)}');
      buf.writeln('wireguard_listen = ${_q(vpnListen)}');
      buf.writeln();
    }

    buf.writeln('[flags]');
    buf.writeln(
      'default_protocol = ${_q(defaultProtocol.trim().isEmpty ? 'tcp' : defaultProtocol.trim())}',
    );
    buf.writeln('dev_name = ${_q(devName.trim())}');
    buf.writeln('enable_encryption = $enableEncryption');
    buf.writeln('enable_ipv6 = $enableIpv6');
    final mtuVal = int.tryParse(mtu.trim());
    if (mtuVal != null && mtuVal > 0) {
      buf.writeln('mtu = $mtuVal');
    }
    buf.writeln('latency_first = $latencyFirst');
    buf.writeln('enable_exit_node = $enableExitNode');
    buf.writeln('proxy_forward_by_system = $proxyForwardBySystem');
    buf.writeln('no_tun = $noTun');
    buf.writeln('use_smoltcp = $useSmoltcp');
    buf.writeln(
      'relay_network_whitelist = ${_q(relayNetworkWhitelist.trim())}',
    );
    buf.writeln('disable_p2p = $disableP2p');
    buf.writeln('p2p_only = $p2pOnly');
    buf.writeln('lazy_p2p = $lazyP2p');
    buf.writeln('need_p2p = $needP2p');
    buf.writeln('relay_all_peer_rpc = $relayAllPeerRpc');
    buf.writeln('disable_tcp_hole_punching = $disableTcpHolePunching');
    buf.writeln('disable_udp_hole_punching = $disableUdpHolePunching');
    buf.writeln('disable_sym_hole_punching = $disableSymHolePunching');
    buf.writeln('multi_thread = $multiThread');
    final threads = int.tryParse(multiThreadCount.trim());
    if (threads != null && threads > 0) {
      buf.writeln('multi_thread_count = $threads');
    }
    buf.writeln('data_compress_algo = $dataCompressAlgo');
    buf.writeln('bind_device = $bindDevice');
    buf.writeln('enable_kcp_proxy = $enableKcpProxy');
    buf.writeln('disable_kcp_input = $disableKcpInput');
    buf.writeln('disable_relay_kcp = $disableRelayKcp');
    buf.writeln(
      'enable_relay_foreign_network_kcp = $enableRelayForeignNetworkKcp',
    );
    buf.writeln('enable_quic_proxy = $enableQuicProxy');
    buf.writeln('disable_quic_input = $disableQuicInput');
    buf.writeln('disable_relay_quic = $disableRelayQuic');
    buf.writeln(
      'enable_relay_foreign_network_quic = $enableRelayForeignNetworkQuic',
    );
    buf.writeln('accept_dns = $acceptDns');
    buf.writeln('tld_dns_zone = ${_q(tldDnsZone.trim())}');
    buf.writeln('private_mode = $privateMode');
    _writeBps(buf, 'foreign_relay_bps_limit', foreignRelayBpsLimit);
    _writeBps(buf, 'instance_recv_bps_limit', instanceRecvBpsLimit);
    final enc = encryptionAlgorithm.trim();
    if (enc.isNotEmpty) {
      buf.writeln('encryption_algorithm = ${_q(enc)}');
    }
    buf.writeln('disable_upnp = $disableUpnp');
    buf.writeln('disable_relay_data = $disableRelayData');
    buf.writeln('enable_udp_broadcast_relay = $enableUdpBroadcastRelay');
    return buf.toString();
  }

  InstanceTomlConfig copy() => InstanceTomlConfig.fromToml(toToml());

  bool sameAs(InstanceTomlConfig other) => toToml() == other.toToml();

  static void _writeStringArray(
    StringBuffer buf,
    String key,
    List<String> values,
  ) {
    final items =
        values.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (items.isEmpty) return;
    buf.writeln('$key = [');
    for (final item in items) {
      buf.writeln('    ${_q(item)},');
    }
    buf.writeln(']');
  }

  static void _writeBps(StringBuffer buf, String key, String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    final n = int.tryParse(v);
    if (n == null || n < 0) return;
    buf.writeln('$key = $n');
  }

  static String _bpsFromToml(Object? v) {
    if (v == null) return '';
    if (v is int) {
      if (v < 0) return '';
      // ET 默认 u64::MAX 表示不限
      if (v >= 0x7fffffffffffffff) return '';
      return '$v';
    }
    final s = '$v'.trim();
    if (s.isEmpty) return '';
    final n = int.tryParse(s);
    if (n != null && n >= 0x7fffffffffffffff) return '';
    return s;
  }

  static String _q(String s) {
    final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  static Map<String, dynamic> _asMap(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  static List<dynamic> _asList(Object? v) {
    if (v is List) return v;
    return const [];
  }

  static String _str(Object? v, String fallback) {
    if (v == null) return fallback;
    final s = '$v'.trim();
    return s.isEmpty ? fallback : s;
  }

  static bool _bool(Object? v, bool fallback) {
    if (v is bool) return v;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return fallback;
  }

  static int _int(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  static List<String> _stringList(Object? v, List<String> fallback) {
    if (v is! List) return List<String>.from(fallback);
    if (v.isEmpty) return [];
    return [
      for (final e in v)
        if ('$e'.trim().isNotEmpty) '$e'.trim(),
    ];
  }
}
