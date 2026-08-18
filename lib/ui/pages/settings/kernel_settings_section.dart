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
          title: const Text('卸载内核服务'),
          content: const Text('卸载后开机不再自动运行内核。确定继续？'),
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

  @override
  Widget build(BuildContext context) {
    if (!getIt.isRegistered<CoreServiceController>()) {
      return const SizedBox.shrink();
    }

    return AstralSettingsSection(
      title: '内核服务',
      child: Watch((context) {
        final core = _core;
        final state = core.state.value;
        final busy = core.busy.value;
        final version = core.version.value;
        final hasUpdate = core.hasUpdate.value;
        final installed = state.isInstalled;
        final engine = _engine;

        final statusBits = <String>[
          state.label,
          if (version.isNotEmpty) version,
          if (engine.statusMessage != null) engine.statusMessage!,
          if (core.lastMessage.value != null) core.lastMessage.value!,
        ];

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
              title: const Text('astral-core'),
              subtitle: Text(statusBits.join(' · ')),
            ),
            const AstralSettingsDivider(),
            ListTile(
              leading: Icon(
                installed
                    ? Icons.delete_outline
                    : Icons.install_desktop_outlined,
              ),
              title: Text(installed ? '卸载服务' : '安装服务'),
              subtitle: Text(
                installed ? '移除系统服务，开机不再自启' : '安装为系统服务并开机自启（关 GUI 内核继续运行）',
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
            const AstralSettingsDivider(),
            ListTile(
              leading: Icon(
                hasUpdate ? Icons.system_update_alt : Icons.sync_outlined,
              ),
              title: Text(hasUpdate ? '同步携带的内核' : '内核已与软件一致'),
              subtitle: Text(
                hasUpdate ? '用本软件自带的 astral-core 覆盖系统服务' : '启动时会自动对比，无需从网上更新内核',
              ),
              enabled: !busy && hasUpdate,
              onTap: () => unawaited(_run(() => core.syncFromBundled())),
            ),
          ],
        );
      }),
    );
  }
}
