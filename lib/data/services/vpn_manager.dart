import 'package:astral/data/services/log_service.dart';
import 'package:astral_rust_core/p2p_service.dart';
import 'package:get_it/get_it.dart';
import 'package:vpn_service_plugin/vpn_service_plugin.dart';

/// Astral2 侧 VPN：委托 [AndroidVpnSession]，日志走 [LogService]。
class VpnManager {
  VpnManager(P2PService p2p)
      : _session = AndroidVpnSession(
          applyTunFd: p2p.setTunFd,
          log: (level, message) {
            final logger = GetIt.I.isRegistered<LogService>()
                ? GetIt.I<LogService>()
                : null;
            if (level == 'error') {
              logger?.error('VpnManager', message);
            } else if (level == 'warn') {
              logger?.warn('VpnManager', message);
            } else {
              logger?.info('VpnManager', message);
            }
          },
        );

  final AndroidVpnSession _session;

  set onRevokedBySystem(Future<void> Function(String instanceId)? cb) {
    _session.onRevokedBySystem = cb;
  }

  Future<bool> ensurePermission() => _session.ensurePermission();

  Future<bool> start({
    required String instanceId,
    required String ipv4Addr,
  }) =>
      _session.start(instanceId: instanceId, ipv4Addr: ipv4Addr);

  Future<void> stop({String? instanceId}) =>
      _session.stop(instanceId: instanceId);

  void startListening() => _session.startListening();

  Future<void> dispose() => _session.dispose();
}
