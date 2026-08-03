import 'package:astral/config/app_dimensions.dart';
import 'package:astral/data/models/instance_toml_config.dart';
import 'package:astral/data/services/instance_catalog_service.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral/di.dart';
import 'package:astral/ui/widgets/astral_settings_section.dart';
import 'package:astral/ui/widgets/astral_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 配置表单：分区映射；返回时自动保存。
class ConfigEditorPage extends StatefulWidget {
  final String path;

  const ConfigEditorPage({super.key, required this.path});

  @override
  State<ConfigEditorPage> createState() => ConfigEditorPageState();
}

class ConfigEditorPageState extends State<ConfigEditorPage> {
  InstanceTomlConfig _config = InstanceTomlConfig.defaults();
  String _savedToml = '';
  bool _isLoading = true;
  String? _loadError;
  bool _advancedOpen = false;

  late final TextEditingController _instanceName;
  late final TextEditingController _hostname;
  late final TextEditingController _networkName;
  late final TextEditingController _networkSecret;
  late final TextEditingController _ipv4;
  late final TextEditingController _ipv6;
  late final TextEditingController _devName;
  late final TextEditingController _mtu;
  late final TextEditingController _relayWhitelist;
  late final TextEditingController _tldDnsZone;
  late final TextEditingController _encryptionAlgo;
  late final TextEditingController _multiThreadCount;
  late final TextEditingController _foreignRelayBps;
  late final TextEditingController _instanceRecvBps;
  late final TextEditingController _socks5;
  late final TextEditingController _vpnCidr;
  late final TextEditingController _vpnListen;
  late final TextEditingController _peerCtrl;
  late final TextEditingController _proxyCtrl;
  late final TextEditingController _listenerCtrl;
  late final TextEditingController _mappedListenerCtrl;
  late final TextEditingController _exitNodeCtrl;
  late final TextEditingController _routeCtrl;
  late final TextEditingController _tcpWlCtrl;
  late final TextEditingController _udpWlCtrl;
  late final TextEditingController _stunCtrl;
  late final TextEditingController _stunV6Ctrl;
  late final TextEditingController _pfBindCtrl;
  late final TextEditingController _pfDstCtrl;

  bool get isDirty => !_isLoading && _config.toToml() != _savedToml;

  @override
  void initState() {
    super.initState();
    _instanceName = TextEditingController();
    _hostname = TextEditingController();
    _networkName = TextEditingController();
    _networkSecret = TextEditingController();
    _ipv4 = TextEditingController();
    _ipv6 = TextEditingController();
    _devName = TextEditingController();
    _mtu = TextEditingController();
    _relayWhitelist = TextEditingController();
    _tldDnsZone = TextEditingController();
    _encryptionAlgo = TextEditingController();
    _multiThreadCount = TextEditingController();
    _foreignRelayBps = TextEditingController();
    _instanceRecvBps = TextEditingController();
    _socks5 = TextEditingController();
    _vpnCidr = TextEditingController();
    _vpnListen = TextEditingController();
    _peerCtrl = TextEditingController();
    _proxyCtrl = TextEditingController();
    _listenerCtrl = TextEditingController();
    _mappedListenerCtrl = TextEditingController();
    _exitNodeCtrl = TextEditingController();
    _routeCtrl = TextEditingController();
    _tcpWlCtrl = TextEditingController();
    _udpWlCtrl = TextEditingController();
    _stunCtrl = TextEditingController();
    _stunV6Ctrl = TextEditingController();
    _pfBindCtrl = TextEditingController();
    _pfDstCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _instanceName,
      _hostname,
      _networkName,
      _networkSecret,
      _ipv4,
      _ipv6,
      _devName,
      _mtu,
      _relayWhitelist,
      _tldDnsZone,
      _encryptionAlgo,
      _multiThreadCount,
      _foreignRelayBps,
      _instanceRecvBps,
      _socks5,
      _vpnCidr,
      _vpnListen,
      _peerCtrl,
      _proxyCtrl,
      _listenerCtrl,
      _mappedListenerCtrl,
      _exitNodeCtrl,
      _routeCtrl,
      _tcpWlCtrl,
      _udpWlCtrl,
      _stunCtrl,
      _stunV6Ctrl,
      _pfBindCtrl,
      _pfDstCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _bindControllers(InstanceTomlConfig c) {
    _instanceName.text = c.instanceName;
    _hostname.text = c.hostname;
    _networkName.text = c.networkName;
    _networkSecret.text = c.networkSecret;
    _ipv4.text = c.ipv4;
    _ipv6.text = c.ipv6;
    _devName.text = c.devName;
    _mtu.text = c.mtu;
    _relayWhitelist.text = c.relayNetworkWhitelist;
    _tldDnsZone.text = c.tldDnsZone;
    _encryptionAlgo.text = c.encryptionAlgorithm;
    _multiThreadCount.text = c.multiThreadCount;
    _foreignRelayBps.text = c.foreignRelayBpsLimit;
    _instanceRecvBps.text = c.instanceRecvBpsLimit;
    _socks5.text = c.socks5Proxy;
    _vpnCidr.text = c.vpnClientCidr;
    _vpnListen.text = c.vpnWireguardListen;
  }

  void _syncTextToConfig() {
    _config
      ..instanceName = _instanceName.text
      ..hostname = _hostname.text
      ..networkName = _networkName.text
      ..networkSecret = _networkSecret.text
      ..ipv4 = _ipv4.text
      ..ipv6 = _ipv6.text
      ..devName = _devName.text
      ..mtu = _mtu.text
      ..relayNetworkWhitelist = _relayWhitelist.text
      ..tldDnsZone = _tldDnsZone.text
      ..encryptionAlgorithm = _encryptionAlgo.text
      ..multiThreadCount = _multiThreadCount.text
      ..foreignRelayBpsLimit = _foreignRelayBps.text
      ..instanceRecvBpsLimit = _instanceRecvBps.text
      ..socks5Proxy = _socks5.text
      ..vpnClientCidr = _vpnCidr.text
      ..vpnWireguardListen = _vpnListen.text;
  }

  void _mark() {
    _syncTextToConfig();
    setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final text = await getIt<InstanceCatalogService>().readToml(widget.path);
      if (text == null) throw StateError('配置不存在');
      final cfg = InstanceTomlConfig.fromToml(text);
      _config = cfg;
      _bindControllers(cfg);
      _savedToml = cfg.toToml();
    } catch (e) {
      _loadError = '$e';
      _config = InstanceTomlConfig.defaults();
      _bindControllers(_config);
      _savedToml = _config.toToml();
      if (mounted) {
        showAstralSnack(context, '读取/解析失败，已用默认表单: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 返回时调用：有改动则落盘；失败则阻止关闭。
  Future<bool> flushSaveOnClose() async {
    if (_isLoading) return true;
    _syncTextToConfig();
    if (!isDirty) return true;
    try {
      final text = _config.toToml();
      InstanceTomlConfig.fromToml(text);
      await getIt<InstanceCatalogService>().writeToml(widget.path, text);
      _savedToml = text;
      if (mounted) {
        final running = getIt.isRegistered<InstanceRuntimeStore>() &&
            getIt<InstanceRuntimeStore>().isRunning(widget.path);
        showAstralSnack(
          context,
          running ? '已保存（需重启实例后生效）' : '已保存',
        );
      }
      return true;
    } catch (e) {
      if (mounted) showAstralSnack(context, '保存失败: $e');
      return false;
    }
  }

  void _addLine(List<String> target, TextEditingController ctrl) {
    final v = ctrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      target.add(v);
      ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.pagePaddingH,
        AppDimensions.pagePaddingV,
        AppDimensions.pagePaddingH,
        32,
      ),
      children: [
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '原文件解析异常，返回时将按表单覆盖保存',
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
        AstralSettingsSection(
          title: '基本',
          child: Column(
            children: [
              _fieldTile(Icons.badge_outlined, '实例名', _instanceName),
              const AstralSettingsDivider(),
              _fieldTile(
                Icons.computer_outlined,
                '主机名',
                _hostname,
                hint: '对端可见；可留空',
              ),
              const AstralSettingsDivider(),
              _fieldTile(Icons.lan_outlined, '网络名', _networkName),
              const AstralSettingsDivider(),
              _fieldTile(
                Icons.lock_outline,
                '网络密钥',
                _networkSecret,
                obscure: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        AstralSettingsSection(
          title: '地址',
          child: Column(
            children: [
              _switchTile(
                Icons.dns_outlined,
                'DHCP',
                '开启后不写静态 ipv4；Android 将跳过系统 VPN',
                _config.dhcp,
                (v) {
                  _config.dhcp = v;
                  _mark();
                },
              ),
              const AstralSettingsDivider(),
              _fieldTile(
                Icons.pin_outlined,
                '静态 IPv4',
                _ipv4,
                hint: '如 10.126.126.1/24',
                enabled: !_config.dhcp,
              ),
              const AstralSettingsDivider(),
              _switchTile(
                Icons.language,
                '启用 IPv6',
                'flags.enable_ipv6',
                _config.enableIpv6,
                (v) {
                  _config.enableIpv6 = v;
                  _mark();
                },
              ),
              const AstralSettingsDivider(),
              _fieldTile(
                Icons.pin_outlined,
                '本机 IPv6 地址',
                _ipv6,
                hint: '可选 CIDR；与上项开关不同',
                enabled: _config.enableIpv6,
              ),
              const AstralSettingsDivider(),
              _stringListEditor(
                title: '监听 listeners',
                items: _config.listeners,
                controller: _listenerCtrl,
                hint: 'tcp://0.0.0.0:0',
                onAdd: () => _addLine(_config.listeners, _listenerCtrl),
              ),
              const AstralSettingsDivider(),
              _stringListEditor(
                title: '映射监听 mapped_listeners',
                items: _config.mappedListeners,
                controller: _mappedListenerCtrl,
                hint: 'tcp://公网IP:端口',
                onAdd: () =>
                    _addLine(_config.mappedListeners, _mappedListenerCtrl),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        AstralSettingsSection(
          title: '对端与路由',
          child: Column(
            children: [
              _stringListEditor(
                title: 'Peer URI',
                items: _config.peerUris,
                controller: _peerCtrl,
                hint: 'tcp://host:port',
                onAdd: () => _addLine(_config.peerUris, _peerCtrl),
              ),
              const AstralSettingsDivider(),
              _stringListEditor(
                title: '代理网段 CIDR',
                items: _config.proxyCidrs,
                controller: _proxyCtrl,
                hint: '10.0.0.0/24',
                onAdd: () => _addLine(_config.proxyCidrs, _proxyCtrl),
              ),
              const AstralSettingsDivider(),
              _stringListEditor(
                title: '手动路由 routes',
                items: _config.routes,
                controller: _routeCtrl,
                hint: '192.168.0.0/16',
                onAdd: () => _addLine(_config.routes, _routeCtrl),
              ),
              const AstralSettingsDivider(),
              _stringListEditor(
                title: '走这些节点出口（exit_nodes）',
                items: _config.exitNodes,
                controller: _exitNodeCtrl,
                hint: '对端虚拟网 IP；与「本机可作出口」无关',
                onAdd: () => _addLine(_config.exitNodes, _exitNodeCtrl),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        AstralSettingsSection(
          title: '网络行为',
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('默认协议')),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'tcp', label: Text('TCP')),
                        ButtonSegment(value: 'udp', label: Text('UDP')),
                      ],
                      selected: {
                        _config.defaultProtocol == 'udp' ? 'udp' : 'tcp',
                      },
                      onSelectionChanged: (s) {
                        _config.defaultProtocol = s.first;
                        _mark();
                      },
                    ),
                  ],
                ),
              ),
              const AstralSettingsDivider(),
              _switchTile(
                Icons.block,
                '禁用 P2P',
                '只走中继；与「仅 P2P」互斥语义',
                _config.disableP2p,
                (v) {
                  _config.disableP2p = v;
                  _mark();
                },
              ),
              const AstralSettingsDivider(),
              _switchTile(
                Icons.hub_outlined,
                '仅 P2P',
                '不允许中继转发',
                _config.p2pOnly,
                (v) {
                  _config.p2pOnly = v;
                  _mark();
                },
              ),
              const AstralSettingsDivider(),
              _switchTile(
                Icons.broadcast_on_home_outlined,
                'UDP 广播中继',
                '局域网广播进虚拟网（Windows）',
                _config.enableUdpBroadcastRelay,
                (v) {
                  _config.enableUdpBroadcastRelay = v;
                  _mark();
                },
              ),
              const AstralSettingsDivider(),
              _switchTile(
                Icons.timer_outlined,
                '延迟优先',
                '选路偏延迟而非带宽',
                _config.latencyFirst,
                (v) {
                  _config.latencyFirst = v;
                  _mark();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        AstralSettingsSection(
          title: '高级',
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.expand_more),
                title: const Text('展开全部高级选项'),
                subtitle: Text(
                  _advancedOpen ? '已展开全部 flags 与门户配置' : '点击展开',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                value: _advancedOpen,
                onChanged: (v) => setState(() => _advancedOpen = v),
              ),
              if (_advancedOpen) ...[
                const AstralSettingsDivider(),
                _advHeader('设备与 TUN'),
                _fieldTile(Icons.device_hub_outlined, '虚拟网卡名', _devName),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.straighten,
                  'MTU',
                  _mtu,
                  hint: '默认 1380',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.wifi_tethering_off_outlined,
                  '无 TUN',
                  'no_tun',
                  _config.noTun,
                  (v) {
                    _config.noTun = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.link,
                  '绑定网卡',
                  'bind_device',
                  _config.bindDevice,
                  (v) {
                    _config.bindDevice = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.memory,
                  '使用 smoltcp',
                  'use_smoltcp',
                  _config.useSmoltcp,
                  (v) {
                    _config.useSmoltcp = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.exit_to_app,
                  '本机可作出口',
                  'enable_exit_node：允许别人走我；上面「exit_nodes」是我走别人',
                  _config.enableExitNode,
                  (v) {
                    _config.enableExitNode = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.alt_route,
                  '系统转发代理',
                  'proxy_forward_by_system',
                  _config.proxyForwardBySystem,
                  (v) {
                    _config.proxyForwardBySystem = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _advHeader('P2P 细节'),
                _switchTile(
                  Icons.hourglass_empty,
                  '懒惰 P2P',
                  'lazy_p2p：需要时再建直连',
                  _config.lazyP2p,
                  (v) {
                    _config.lazyP2p = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.priority_high,
                  '需要 P2P',
                  'need_p2p：偏好强制直连',
                  _config.needP2p,
                  (v) {
                    _config.needP2p = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _advHeader('DNS / 加密'),
                _switchTile(
                  Icons.travel_explore_outlined,
                  'Magic DNS',
                  'accept_dns',
                  _config.acceptDns,
                  (v) {
                    _config.acceptDns = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.dns,
                  'TLD DNS Zone',
                  _tldDnsZone,
                  hint: 'et.net.',
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.lock,
                  '启用加密',
                  'enable_encryption',
                  _config.enableEncryption,
                  (v) {
                    _config.enableEncryption = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.enhanced_encryption_outlined,
                  '加密算法',
                  _encryptionAlgo,
                  hint: '空=默认；aes-gcm / aes-256-gcm / chacha20 / xor',
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.shield_outlined,
                  '私有模式',
                  'private_mode',
                  _config.privateMode,
                  (v) {
                    _config.privateMode = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _advHeader('传输代理（KCP / QUIC 各一套，非重复）'),
                _proxyProtoGroup(
                  title: 'KCP',
                  enableLabel: '启用 KCP 代理',
                  enableValue: _config.enableKcpProxy,
                  onEnable: (v) {
                    _config.enableKcpProxy = v;
                    _mark();
                  },
                  disableInput: _config.disableKcpInput,
                  onDisableInput: (v) {
                    _config.disableKcpInput = v;
                    _mark();
                  },
                  disableRelay: _config.disableRelayKcp,
                  onDisableRelay: (v) {
                    _config.disableRelayKcp = v;
                    _mark();
                  },
                  foreignRelay: _config.enableRelayForeignNetworkKcp,
                  onForeignRelay: (v) {
                    _config.enableRelayForeignNetworkKcp = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _proxyProtoGroup(
                  title: 'QUIC',
                  enableLabel: '启用 QUIC 代理',
                  enableValue: _config.enableQuicProxy,
                  onEnable: (v) {
                    _config.enableQuicProxy = v;
                    _mark();
                  },
                  disableInput: _config.disableQuicInput,
                  onDisableInput: (v) {
                    _config.disableQuicInput = v;
                    _mark();
                  },
                  disableRelay: _config.disableRelayQuic,
                  onDisableRelay: (v) {
                    _config.disableRelayQuic = v;
                    _mark();
                  },
                  foreignRelay: _config.enableRelayForeignNetworkQuic,
                  onForeignRelay: (v) {
                    _config.enableRelayForeignNetworkQuic = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _advHeader('打洞与中继'),
                _switchTile(
                  Icons.punch_clock_outlined,
                  '禁用 TCP 打洞',
                  'disable_tcp_hole_punching',
                  _config.disableTcpHolePunching,
                  (v) {
                    _config.disableTcpHolePunching = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.punch_clock_outlined,
                  '禁用 UDP 打洞',
                  'disable_udp_hole_punching',
                  _config.disableUdpHolePunching,
                  (v) {
                    _config.disableUdpHolePunching = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.punch_clock_outlined,
                  '禁用对称 NAT 打洞',
                  'disable_sym_hole_punching',
                  _config.disableSymHolePunching,
                  (v) {
                    _config.disableSymHolePunching = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.share,
                  '中继全部 Peer RPC',
                  'relay_all_peer_rpc',
                  _config.relayAllPeerRpc,
                  (v) {
                    _config.relayAllPeerRpc = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.data_object,
                  '禁用中继数据',
                  'disable_relay_data',
                  _config.disableRelayData,
                  (v) {
                    _config.disableRelayData = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _switchTile(
                  Icons.router_outlined,
                  '禁用 UPnP',
                  'disable_upnp',
                  _config.disableUpnp,
                  (v) {
                    _config.disableUpnp = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.filter_list,
                  '中继网络白名单',
                  _relayWhitelist,
                  hint: '* 或空格分隔网络名',
                ),
                const AstralSettingsDivider(),
                _advHeader('性能'),
                _switchTile(
                  Icons.workspaces_outlined,
                  '多线程',
                  'multi_thread',
                  _config.multiThread,
                  (v) {
                    _config.multiThread = v;
                    _mark();
                  },
                ),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.numbers,
                  '线程数',
                  _multiThreadCount,
                  hint: '2',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const AstralSettingsDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.compress, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 16),
                      const Expanded(child: Text('压缩算法')),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 1, label: Text('无')),
                          ButtonSegment(value: 2, label: Text('Zstd')),
                        ],
                        selected: {
                          _config.dataCompressAlgo == 2 ? 2 : 1,
                        },
                        onSelectionChanged: (s) {
                          _config.dataCompressAlgo = s.first;
                          _mark();
                        },
                      ),
                    ],
                  ),
                ),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.speed,
                  '外网中继限速 B/s',
                  _foreignRelayBps,
                  hint: '留空不限制',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.speed,
                  '实例接收限速 B/s',
                  _instanceRecvBps,
                  hint: '留空不限制',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const AstralSettingsDivider(),
                _advHeader('门户与转发'),
                _fieldTile(
                  Icons.vpn_key_outlined,
                  'SOCKS5 代理',
                  _socks5,
                  hint: 'socks5://0.0.0.0:1080',
                ),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.vpn_lock_outlined,
                  'VPN 客户端网段',
                  _vpnCidr,
                  hint: '10.100.0.0/24',
                ),
                const AstralSettingsDivider(),
                _fieldTile(
                  Icons.hearing,
                  'WireGuard 监听',
                  _vpnListen,
                  hint: '0.0.0.0:11013',
                ),
                const AstralSettingsDivider(),
                _stringListEditor(
                  title: 'TCP 白名单',
                  items: _config.tcpWhitelist,
                  controller: _tcpWlCtrl,
                  hint: '80 或 8000-9000',
                  onAdd: () => _addLine(_config.tcpWhitelist, _tcpWlCtrl),
                ),
                const AstralSettingsDivider(),
                _stringListEditor(
                  title: 'UDP 白名单',
                  items: _config.udpWhitelist,
                  controller: _udpWlCtrl,
                  hint: '53',
                  onAdd: () => _addLine(_config.udpWhitelist, _udpWlCtrl),
                ),
                const AstralSettingsDivider(),
                _portForwardEditor(),
                const AstralSettingsDivider(),
                _advHeader('STUN'),
                _stringListEditor(
                  title: 'STUN 服务器',
                  items: _config.stunServers,
                  controller: _stunCtrl,
                  hint: '留空用内置；可添加后清空列表以禁用',
                  onAdd: () => _addLine(_config.stunServers, _stunCtrl),
                ),
                const AstralSettingsDivider(),
                _stringListEditor(
                  title: 'STUN v6',
                  items: _config.stunServersV6,
                  controller: _stunV6Ctrl,
                  hint: 'IPv6 STUN',
                  onAdd: () => _addLine(_config.stunServersV6, _stunV6Ctrl),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '返回时自动保存',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }

  Widget _advHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// KCP / QUIC 在 ET 里是两套平行 flags，用同一布局避免看起来像复制粘贴错误。
  Widget _proxyProtoGroup({
    required String title,
    required String enableLabel,
    required bool enableValue,
    required ValueChanged<bool> onEnable,
    required bool disableInput,
    required ValueChanged<bool> onDisableInput,
    required bool disableRelay,
    required ValueChanged<bool> onDisableRelay,
    required bool foreignRelay,
    required ValueChanged<bool> onForeignRelay,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            SwitchListTile(
              dense: true,
              title: Text(enableLabel),
              value: enableValue,
              onChanged: onEnable,
            ),
            SwitchListTile(
              dense: true,
              title: const Text('禁用入站'),
              subtitle: Text('本机不接受对端 $title'),
              value: disableInput,
              onChanged: onDisableInput,
            ),
            SwitchListTile(
              dense: true,
              title: const Text('禁用本网中继'),
              value: disableRelay,
              onChanged: onDisableRelay,
            ),
            SwitchListTile(
              dense: true,
              title: const Text('允许外网中继'),
              value: foreignRelay,
              onChanged: onForeignRelay,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldTile(
    IconData icon,
    String label,
    TextEditingController controller, {
    String? hint,
    bool enabled = true,
    bool obscure = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscure,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: hint,
        ),
        onChanged: (_) => _mark(),
      ),
    );
  }

  Widget _switchTile(
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _stringListEditor({
    required String title,
    required List<String> items,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onAdd,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          for (var i = 0; i < items.length; i++)
            ListTile(
              dense: true,
              title: Text(items[i], style: const TextStyle(fontSize: 13)),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => items.removeAt(i)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: hint,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => onAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _portForwardEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '端口转发 port_forward',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (var i = 0; i < _config.portForwards.length; i++)
            ListTile(
              dense: true,
              title: Text(
                '${_config.portForwards[i].proto} '
                '${_config.portForwards[i].bindAddr} → '
                '${_config.portForwards[i].dstAddr}',
                style: const TextStyle(fontSize: 13),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    setState(() => _config.portForwards.removeAt(i)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                TextField(
                  controller: _pfBindCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'bind 如 0.0.0.0:11011',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pfDstCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'dst 如 10.126.126.2:80',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      final bind = _pfBindCtrl.text.trim();
                      final dst = _pfDstCtrl.text.trim();
                      if (bind.isEmpty || dst.isEmpty) return;
                      setState(() {
                        _config.portForwards.add(
                          PortForwardEntry(
                            bindAddr: bind,
                            dstAddr: dst,
                            proto: 'tcp',
                          ),
                        );
                        _pfBindCtrl.clear();
                        _pfDstCtrl.clear();
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('添加 TCP 转发'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
