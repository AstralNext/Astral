import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:astral/ui/widgets/astral_card.dart';
import 'package:flutter/material.dart';

enum DiagnosticStatus { pending, running, success, fail }

class _DiagnosticItem {
  final String label;
  final String description;
  DiagnosticStatus status = DiagnosticStatus.pending;
  String? detail;
  int? latencyMs;

  _DiagnosticItem({
    required this.label,
    required this.description,
  });
}

/// 精简网络诊断：接口 / IPv4 连通 / DNS / 公网 IP。
class NetworkDiagnosticPage extends StatefulWidget {
  const NetworkDiagnosticPage({super.key});

  @override
  State<NetworkDiagnosticPage> createState() => _NetworkDiagnosticPageState();
}

class _NetworkDiagnosticPageState extends State<NetworkDiagnosticPage> {
  bool _isRunning = false;
  late final List<_DiagnosticItem> _items = [
    _DiagnosticItem(label: '网络接口', description: '本机 IPv4 接口'),
    _DiagnosticItem(label: 'IPv4 连通', description: 'TCP 连通性'),
    _DiagnosticItem(label: 'DNS', description: 'IPv4 DNS 解析'),
    _DiagnosticItem(label: '公网 IP', description: '本机公网 IPv4'),
  ];

  Future<void> _runDiagnostic() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      for (final item in _items) {
        item.status = DiagnosticStatus.pending;
        item.detail = null;
        item.latencyMs = null;
      }
    });

    await _testNetworkInfo();
    await _testIPv4();
    await _testDns();
    await _testPublicIp();

    if (mounted) setState(() => _isRunning = false);
  }

  Future<void> _testNetworkInfo() async {
    final item = _items[0];
    setState(() => item.status = DiagnosticStatus.running);
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      final details = <String>[];
      for (final iface in interfaces) {
        if (iface.addresses.isEmpty) continue;
        details.add('[${iface.name}]');
        for (final addr in iface.addresses) {
          details.add('  ${addr.address}');
        }
      }
      setState(() {
        item.status = DiagnosticStatus.success;
        item.detail =
            details.isEmpty ? '未检测到网络接口' : details.join('\n');
      });
    } catch (_) {
      setState(() {
        item.status = DiagnosticStatus.fail;
        item.detail = '获取网络接口失败';
      });
    }
  }

  Future<void> _testIPv4() async {
    final item = _items[1];
    setState(() => item.status = DiagnosticStatus.running);
    try {
      final sw = Stopwatch()..start();
      await Socket.connect('baidu.com', 80, timeout: const Duration(seconds: 5));
      sw.stop();
      setState(() {
        item.status = DiagnosticStatus.success;
        item.latencyMs = sw.elapsedMilliseconds;
        item.detail = '延迟 ${sw.elapsedMilliseconds} ms';
      });
    } catch (_) {
      setState(() {
        item.status = DiagnosticStatus.fail;
        item.detail = '连接失败';
      });
    }
  }

  Future<void> _testDns() async {
    final item = _items[2];
    setState(() => item.status = DiagnosticStatus.running);
    try {
      final sw = Stopwatch()..start();
      final addresses = await InternetAddress.lookup(
        'baidu.com',
        type: InternetAddressType.IPv4,
      );
      sw.stop();
      if (addresses.isEmpty) {
        setState(() {
          item.status = DiagnosticStatus.fail;
          item.detail = '解析结果为空';
        });
        return;
      }
      setState(() {
        item.status = DiagnosticStatus.success;
        item.latencyMs = sw.elapsedMilliseconds;
        item.detail =
            '${addresses.map((a) => a.address).join(', ')} (${sw.elapsedMilliseconds} ms)';
      });
    } on SocketException catch (_) {
      setState(() {
        item.status = DiagnosticStatus.fail;
        item.detail = 'DNS 解析失败';
      });
    }
  }

  Future<void> _testPublicIp() async {
    final item = _items[3];
    setState(() => item.status = DiagnosticStatus.running);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse('https://api.ip.sb/ip'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final ip = body.trim();
      setState(() {
        if (ip.contains(':') || ip.isEmpty) {
          item.status = DiagnosticStatus.fail;
          item.detail = '未分配公网 IPv4';
        } else {
          item.status = DiagnosticStatus.success;
          item.detail = ip;
        }
      });
    } catch (_) {
      setState(() {
        item.status = DiagnosticStatus.fail;
        item.detail = '获取公网 IP 失败';
      });
    }
  }

  Color _statusColor(DiagnosticStatus s, ColorScheme cs) {
    switch (s) {
      case DiagnosticStatus.success:
        return Colors.green;
      case DiagnosticStatus.fail:
        return cs.error;
      case DiagnosticStatus.running:
        return cs.primary;
      case DiagnosticStatus.pending:
        return cs.outline;
    }
  }

  IconData _statusIcon(DiagnosticStatus s) {
    switch (s) {
      case DiagnosticStatus.success:
        return Icons.check_circle_outline;
      case DiagnosticStatus.fail:
        return Icons.error_outline;
      case DiagnosticStatus.running:
        return Icons.hourglass_top;
      case DiagnosticStatus.pending:
        return Icons.radio_button_unchecked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('网络诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AstralCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '检测本机网络接口、连通性与公网 IP。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isRunning ? null : _runDiagnostic,
                    icon: _isRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_isRunning ? '诊断中…' : '开始诊断'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AstralCard(
                child: ListTile(
                  leading: Icon(
                    _statusIcon(item.status),
                    color: _statusColor(item.status, cs),
                  ),
                  title: Text(item.label),
                  subtitle: Text(
                    item.detail ?? item.description,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
