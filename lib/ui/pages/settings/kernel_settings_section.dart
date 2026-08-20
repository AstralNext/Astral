import 'dart:async';

import 'package:astral/data/kernel/core_host.dart';
import 'package:astral/data/kernel/core_service_controller.dart';
import 'package:astral/data/kernel/kernel_engine.dart';
import 'package:astral/di.dart';
import 'package:astral/ui/widgets/astral_settings_section.dart';
import 'package:astral/ui/widgets/astral_snack.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class KernelSettingsSection extends StatefulWidget {
  const KernelSettingsSection({super.key});

  @override
  State<KernelSettingsSection> createState() => _KernelSettingsSectionState();
}

class _KernelSettingsSectionState extends State<KernelSettingsSection> {
  KernelEngine get _engine => getIt<KernelEngine>();

  CoreServiceController get _core => getIt<CoreServiceController>();

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<CoreServiceController>()) {
      unawaited(_core.refresh());
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_core.busy.value) return;
    try {
      final msg = await action();
      if (mounted) showAstralSnack(context, msg);
    } catch (e) {
      if (mounted) showAstralSnack(context, '$e');
    }
  }

  Future<bool> _confirmUninstall() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('卸载后台内核'),
          content: const Text('卸载后关闭软件时，网络内核不会继续在后台运行。确定继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('卸载'),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  String _statusText({
    required CoreInstallState state,
    required String version,
    required bool hasUpdate,
    required KernelEngine engine,
    required CoreServiceController core,
  }) {
    if (hasUpdate) return '版本与当前软件不一致';
    if (engine.statusMessage != null &&
        engine.statusMessage!.contains('已连接')) {
      return '已连接并在后台运行';
    }
    if (state == CoreInstallState.running) {
      return version.isEmpty ? '已在后台运行' : '已在后台运行 · $version';
    }
    if (state == CoreInstallState.stopped) {
      return version.isEmpty ? '已安装，当前未运行' : '已安装，当前未运行 · $version';
    }
    if (state == CoreInstallState.notInstalled) {
      return '尚未安装后台服务';
    }
    if (state == CoreInstallState.missingBinary) {
      return '未找到内核程序';
    }
    final last = core.lastMessage.value;
    if (last != null && last.isNotEmpty) return last;
    return state.label;
  }

  @override
  Widget build(BuildContext context) {
    if (!getIt.isRegistered<CoreServiceController>()) {
      return const SizedBox.shrink();
    }

    return AstralSettingsSection(
      title: '后台内核',
      child: Watch((context) {
        final core = _core;
        final state = core.state.value;
        final busy = core.busy.value;
        final version = core.version.value;
        final hasUpdate = core.bundledDiffers.value;
        final installed = state.isInstalled;
        final engine = _engine;
        final status = _statusText(
          state: state,
          version: version,
          hasUpdate: hasUpdate,
          engine: engine,
          core: core,
        );

        return Column(
          children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            ListTile(
              leading: Icon(
                installed
                    ? (state == CoreInstallState.running
                          ? Icons.check_circle_outline
                          : Icons.pause_circle_outline)
                    : Icons.cloud_off_outlined,
              ),
              title: const Text('Astral 后台内核'),
              subtitle: Text(status),
            ),
            const AstralSettingsDivider(),
            ListTile(
              leading: Icon(
                installed
                    ? Icons.delete_outline
                    : Icons.install_desktop_outlined,
              ),
              title: Text(installed ? '卸载后台服务' : '安装后台服务'),
              subtitle: Text(
                installed
                    ? '移除系统服务，关闭软件后不再继续运行'
                    : '安装为系统服务，关闭软件后网络内核继续运行',
              ),
              enabled: !busy,
              onTap: () => unawaited(
                _run(() async {
                  if (installed) {
                    final ok = await _confirmUninstall();
                    if (!ok) return '已取消';
                    return core.uninstall();
                  }
                  return core.install();
                }),
              ),
            ),
            if (hasUpdate) ...[
              const AstralSettingsDivider(),
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: const Text('立即同步内核版本'),
                subtitle: const Text('用当前软件自带的内核覆盖后台服务'),
                enabled: !busy,
                onTap: () => unawaited(_run(() => core.syncFromBundled())),
              ),
            ],
          ],
        );
      }),
    );
  }
}
