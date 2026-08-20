import 'dart:async';

import 'package:astral/config/app_dimensions.dart';
import 'package:astral/config/theme.dart';
import 'package:astral/data/services/instance_catalog_service.dart';
import 'package:astral/data/services/instance_connection_service.dart';
import 'package:astral/di.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral/ui/pages/configs_dialogs.dart';
import 'package:astral/ui/pages/instance_logs_page.dart';
import 'package:astral/ui/pages/instance_peers_page.dart';
import 'package:astral/ui/shell/shell_content_controller.dart';
import 'package:astral/ui/widgets/astral_confirm_dialog.dart';
import 'package:astral/ui/widgets/astral_snack.dart';
import 'package:astral/ui/widgets/open_config_editor.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

part 'instances_widgets.dart';

/// 本机实例管理。
class InstancesPage extends StatefulWidget {
  const InstancesPage({super.key});

  @override
  State<InstancesPage> createState() => _InstancesPageState();
}

class _InstancesPageState extends State<InstancesPage> {
  late final InstanceCatalogService _catalogService;
  late final InstanceConnectionService _connectionService;
  late final InstanceRuntimeStore _runtimeStore;
  Future<InstanceCatalogSnapshot>? _snapshotFuture;
  InstanceCatalogSnapshot? _cachedSnapshot;

  @override
  void initState() {
    super.initState();
    _catalogService = getIt<InstanceCatalogService>();
    _connectionService = getIt<InstanceConnectionService>();
    _runtimeStore = getIt<InstanceRuntimeStore>();
    _reload();
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _catalogService.loadSnapshot();
    });
  }

  Future<void> _refresh() async {
    final future = _catalogService.loadSnapshot();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showAstralSnack(context, message);
  }

  Future<void> _createInstance() async {
    final name = await promptConfigsName(
      context,
      title: '新建实例',
      hintText: '例如 home',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final path = await _catalogService.createInstanceFile(name.trim());
      _showMessage('已创建');
      _reload();
      if (!mounted) return;
      openConfigEditorOverlay(
        context: context,
        path: path,
        title: name.trim(),
        onClose: () {
          if (mounted) _reload();
        },
      );
    } catch (e) {
      _showMessage('创建失败：$e');
    }
  }

  Future<void> _deleteInstance(InstanceCatalogItem item) async {
    final ok = await showAstralConfirm(
      context,
      title: '删除实例？',
      message: '将删除「${item.name}」。运行中的实例会一并停止。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      // 始终走 stop（串行队列会排在进行中的启动之后）。
      final stopped = await _connectionService.stop(
        path: item.path,
        name: item.name,
      );
      if (!stopped) {
        _showMessage('无法停止「${item.name}」，删除已取消');
        return;
      }
      await _catalogService.deleteEntry(item.path);
      _showMessage('已删除');
      _reload();
    } catch (e) {
      _showMessage('删除失败：$e');
    }
  }

  Future<void> _toggleRun(InstanceCatalogItem item) async {
    final wasRunning = _runtimeStore.isRunning(item.path);
    if (wasRunning) {
      final ok = await showAstralConfirm(
        context,
        title: '停止实例？',
        message: '确定停止 ${item.name}？停止后将断开网络连接。',
        confirmLabel: '停止',
        destructive: true,
      );
      if (!ok || !mounted) return;
      final stopped = await _connectionService.stop(
        path: item.path,
        name: item.name,
      );
      if (!mounted) return;
      _showMessage(stopped ? '已停止: ${item.name}' : '停止失败: ${item.name}');
      return;
    }

    final started = await _connectionService.startFromFile(
      path: item.path,
      name: item.name,
    );
    if (!mounted) return;
    if (!started) {
      _showMessage('启动失败: ${item.name}');
      return;
    }
    final note = _connectionService.consumeLastStartNote();
    _showMessage(note ?? '已启动: ${item.name}');
  }

  void _openConfig(InstanceCatalogItem item) {
    openConfigEditorOverlay(
      context: context,
      path: item.path,
      title: item.name,
      onClose: () {
        if (mounted) _reload();
      },
    );
  }

  void _openLogs(InstanceCatalogItem item) {
    getIt<ShellContentController>().showOverlay(
      content: InstanceLogsPage(
        instancePath: item.path,
        instanceName: item.name,
      ),
      title: '${item.name} - 运行日志',
    );
  }

  int _resolveColumns(double width) {
    if (width >= 1400) return 4;
    if (width >= 1000) return 3;
    if (width >= 680) return 2;
    return 1;
  }

  Widget _buildCard(BuildContext context, InstanceCatalogItem item) {
    return _ReactiveInstanceCard(
      key: ValueKey(item.path),
      item: item,
      runtimeStore: _runtimeStore,
      onToggleRun: () => _toggleRun(item),
      onOpenConfig: () => _openConfig(item),
      onOpenLogs: () => _openLogs(item),
      onOpenPeers: () {
        getIt<ShellContentController>().showOverlay(
          content: InstancePeersPage(
            instancePath: item.path,
            instanceName: item.name,
          ),
          title: '${item.name} - 节点信息',
        );
      },
      onDelete: () => _deleteInstance(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return FutureBuilder<InstanceCatalogSnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _cachedSnapshot == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError && _cachedSnapshot == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '加载失败: ${snapshot.error}',
                  style: TextStyle(color: palette.error),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          );
        }

        if (snapshot.hasData) {
          _cachedSnapshot = snapshot.data;
        }
        final data = snapshot.data ?? _cachedSnapshot;
        if (data == null) {
          return const SizedBox.shrink();
        }

        final headerActionStyle = IconButton.styleFrom(
          backgroundColor: palette.background.computeLuminance() < 0.45
              ? palette.accent
              : Color.lerp(palette.accent, palette.textPrimary, 0.36),
          foregroundColor: palette.onAccent,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.pagePaddingH,
            AppDimensions.pagePaddingV,
            AppDimensions.pagePaddingH,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '实例',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${data.items.length} 个实例',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: '新建实例',
                    onPressed: _createInstance,
                    style: headerActionStyle,
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '刷新',
                    onPressed: _refresh,
                    style: headerActionStyle,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: data.items.isEmpty
                      ? ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            const SizedBox(height: 120),
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 36,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                '还没有实例。',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: FilledButton.icon(
                                onPressed: _createInstance,
                                icon: const Icon(Icons.add),
                                label: const Text('新建实例'),
                              ),
                            ),
                          ],
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            const spacing = 10.0;
                            const tileHeight = 168.0;
                            final columns = _resolveColumns(
                              constraints.maxWidth,
                            );

                            return GridView.builder(
                              padding: EdgeInsets.zero,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                                mainAxisExtent: tileHeight,
                              ),
                              itemCount: data.items.length,
                              itemBuilder: (context, index) {
                                return _buildCard(
                                  context,
                                  data.items[index],
                                );
                              },
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
