import 'dart:async';
import 'dart:io';

import 'package:astral/config/app_dimensions.dart';
import 'package:astral/config/theme.dart';
import 'package:astral/data/services/dashboard_layout_service.dart';
import 'package:astral/data/services/instance_catalog_service.dart';
import 'package:astral/data/services/log_service.dart';
import 'package:astral/data/services/platform_path_service.dart';
import 'package:astral/data/services/update_service.dart';
import 'package:astral/data/state/update_state.dart';
import 'package:astral/di.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral/ui/pages/dashboard/models/dashboard_layout.dart';
import 'package:astral/ui/pages/instance_peers_helpers.dart';
import 'package:astral/ui/pages/instance_peers_page.dart';
import 'package:astral/ui/shell/shell_content_controller.dart';
import 'package:astral/ui/shell/shell_navigation_controller.dart';
import 'package:astral/ui/widgets/dashboard_grid.dart';
import 'package:astral/utils/formatters.dart';
import 'package:astral_rust_core/astral_rust_core.dart' show KVNodeInfo;
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

part 'dashboard/cards/_metrics.dart';
part 'dashboard/cards/traffic_card.dart';
part 'dashboard/cards/memory_card.dart';
part 'dashboard/cards/quality_card.dart';
part 'dashboard/cards/nodes_pulse_card.dart';
part 'dashboard/cards/duplex_card.dart';
part 'dashboard/cards/uptime_card.dart';
part 'dashboard/cards/logs_summary_card.dart';
part 'dashboard/cards/shortcuts_card.dart';
part 'dashboard/cards/update_card.dart';
part 'dashboard/cards/core_card.dart';
part 'dashboard/cards/peer_info_card.dart';
part 'dashboard/widgets/dashboard_card.dart';
part 'dashboard/widgets/page_header.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final InstanceCatalogService _catalogService;
  late final InstanceRuntimeStore _runtimeStore;
  late final DashboardLayoutService _layoutService;
  Future<InstanceCatalogSnapshot>? _snapshotFuture;
  InstanceCatalogSnapshot? _cachedSnapshot;
  bool _isEditingLayout = false;
  DashboardLayout? _layout;

  @override
  void initState() {
    super.initState();
    _catalogService = getIt<InstanceCatalogService>();
    _runtimeStore = getIt<InstanceRuntimeStore>();
    _layoutService = DashboardLayoutService(getIt<PlatformPathService>());
    _loadLayout();
    _loadSnapshot();
  }

  Future<void> _loadLayout() async {
    final raw = await _layoutService.load();
    final layout = DashboardLayout.normalize(raw);
    if (layout.toJson() != raw.toJson()) {
      await _layoutService.save(layout);
    }
    if (mounted) {
      setState(() => _layout = layout);
    }
  }

  Future<void> _saveLayoutOrder(List<String> orderedIds) async {
    final base = _layout ?? DashboardLayout.defaultLayout;
    final byId = {for (final w in base.widgets) w.id: w};
    final defaults = {for (final w in DashboardLayout.catalog) w.id: w};
    final newWidgets = <DashboardWidgetConfig>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final existing = byId[id];
      final fallback = defaults[id];
      if (existing != null) {
        newWidgets.add(existing.copyWith(order: i));
      } else if (fallback != null) {
        newWidgets.add(fallback.copyWith(order: i));
      }
    }
    final newLayout = DashboardLayout.normalize(
      base.copyWith(widgets: newWidgets),
    );
    await _layoutService.save(newLayout);
    if (mounted) {
      setState(() => _layout = newLayout);
    }
  }

  Future<void> _removeCard(String id) async {
    final base = _layout ?? DashboardLayout.defaultLayout;
    final remaining = [
      for (final w in base.widgets)
        if (w.id != id) w,
    ];
    final newLayout = DashboardLayout.normalize(
      base.copyWith(widgets: remaining),
    );
    await _layoutService.save(newLayout);
    if (mounted) {
      setState(() => _layout = newLayout);
    }
  }

  Future<void> _addCard(String type) async {
    final base = _layout ?? DashboardLayout.defaultLayout;
    if (!DashboardLayout.allowsMultiple(type) &&
        base.widgets.any((w) => w.catalogType == type)) {
      return;
    }
    final entry = DashboardLayout.catalogEntry(type);
    if (entry == null) return;
    final slotId = DashboardLayout.allowsMultiple(type)
        ? DashboardLayout.newSlotId(type)
        : type;
    final newWidgets = [
      ...base.widgets,
      entry.copyWith(id: slotId, type: type, order: base.widgets.length),
    ];
    final newLayout = DashboardLayout.normalize(
      base.copyWith(widgets: newWidgets),
    );
    await _layoutService.save(newLayout);
    if (mounted) {
      setState(() => _layout = newLayout);
    }
    if (type == DashboardLayout.peerInfoType && mounted) {
      await _pickAndBindInstance(slotId);
    }
  }

  Future<void> _bindCardInstance(String slotId, String instancePath) async {
    final base = _layout ?? DashboardLayout.defaultLayout;
    final newWidgets = [
      for (final w in base.widgets)
        if (w.id == slotId) w.copyWith(instancePath: instancePath) else w,
    ];
    final newLayout = DashboardLayout.normalize(
      base.copyWith(widgets: newWidgets),
    );
    await _layoutService.save(newLayout);
    if (mounted) {
      setState(() => _layout = newLayout);
    }
  }

  String _instanceName(String path) {
    for (final item in _cachedSnapshot?.items ?? const <InstanceCatalogItem>[]) {
      if (item.path == path) return item.name;
    }
    return path.split(Platform.pathSeparator).last;
  }

  Future<void> _pickAndBindInstance(String slotId) async {
    String? current;
    for (final w in (_layout ?? DashboardLayout.defaultLayout).widgets) {
      if (w.id == slotId) {
        current = w.instancePath;
        break;
      }
    }
    final path = await _showInstancePicker(currentPath: current);
    if (path == null) return;
    await _bindCardInstance(slotId, path);
  }

  Future<String?> _showInstancePicker({String? currentPath}) async {
    final items = _cachedSnapshot?.items ?? const <InstanceCatalogItem>[];
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有实例，先去创建')),
        );
      }
      return null;
    }
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  '选择要绑定的实例',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final item in items)
                ListTile(
                  leading: Icon(
                    _runtimeStore.isRunning(item.path)
                        ? Icons.play_circle_outline
                        : Icons.stop_circle_outlined,
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    item.relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: item.path == currentPath,
                  trailing: item.path == currentPath
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(item.path),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openPeersForCard(DashboardWidgetConfig config) {
    final path = config.instancePath?.trim();
    if (path == null || path.isEmpty) {
      _pickAndBindInstance(config.id);
      return;
    }
    final name = _instanceName(path);
    getIt<ShellContentController>().showOverlay(
      content: InstancePeersPage(
        instancePath: path,
        instanceName: name,
      ),
      title: '$name - 节点信息',
    );
  }

  Future<void> _resetLayout() async {
    final layout = DashboardLayout.normalize(DashboardLayout.defaultLayout);
    await _layoutService.save(layout);
    if (mounted) {
      setState(() => _layout = layout);
    }
  }

  List<String> get _availableCardIds {
    final presentTypes = {
      for (final w in (_layout ?? DashboardLayout.defaultLayout).widgets)
        w.catalogType,
    };
    return [
      for (final w in DashboardLayout.catalog)
        if (DashboardLayout.allowsMultiple(w.catalogType) ||
            !presentTypes.contains(w.catalogType))
          w.catalogType,
    ];
  }

  Future<void> _showAddCardSheet() async {
    final available = _availableCardIds;
    if (available.isEmpty || !mounted) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  '添加卡片',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final id in available)
                ListTile(
                  leading: const Icon(Icons.widgets_outlined),
                  title: Text(DashboardLayout.titleOf(id)),
                  subtitle: DashboardLayout.allowsMultiple(id)
                      ? const Text('可添加多张，每张绑定一个实例')
                      : null,
                  onTap: () => Navigator.of(context).pop(id),
                ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      await _addCard(selected);
    }
  }

  void _loadSnapshot() {
    setState(() {
      _snapshotFuture = _catalogService.loadSnapshot();
    });
  }

  List<DashboardGridItem> _buildGridItems(List<InstanceCatalogItem> items) {
    void go(int tab) => getIt<ShellNavigationController>().navigateTo(tab);

    final layout = DashboardLayout.normalize(
      _layout ?? DashboardLayout.defaultLayout,
    );
    final ordered = [...layout.widgets]
      ..sort((a, b) => a.order.compareTo(b.order));

    return [
      for (final w in ordered)
        if (DashboardLayout.catalogEntry(w.catalogType) != null)
          DashboardGridItem(
            id: w.id,
            widthSpan: w.widthSpan,
            heightSpan: w.heightSpan,
            child: _cardForWidget(w, items, go),
          ),
    ];
  }

  Widget _cardForWidget(
    DashboardWidgetConfig w,
    List<InstanceCatalogItem> items,
    void Function(int tab) go,
  ) {
    switch (w.catalogType) {
      case 'traffic':
        return _TrafficCard(runtimeStore: _runtimeStore);
      case 'memory':
        return const _MemoryCard();
      case 'quality':
        return _QualityCard(runtimeStore: _runtimeStore);
      case 'nodes':
        return _NodesPulseCard(runtimeStore: _runtimeStore);
      case 'duplex':
        return _DuplexCard(runtimeStore: _runtimeStore);
      case 'uptime':
        return _UptimeCard(runtimeStore: _runtimeStore);
      case 'logs':
        return _LogsSummaryCard(onOpenInstances: () => go(ShellTab.instances));
      case 'shortcuts':
        return _ShortcutsCard(onNavigate: go);
      case 'update':
        return const _UpdateCard();
      case 'core':
        return const _CoreCard();
      case DashboardLayout.peerInfoType:
        return _PeerInfoCard(
          key: ValueKey(w.id),
          instancePath: w.instancePath,
          items: items,
          runtimeStore: _runtimeStore,
          onBind: () => _pickAndBindInstance(w.id),
          onOpenPeers: () => _openPeersForCard(w),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                  style: TextStyle(color: colorScheme.error),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _loadSnapshot, child: const Text('重试')),
              ],
            ),
          );
        }

        if (snapshot.hasData) {
          _cachedSnapshot = snapshot.data;
        }

        final items = _cachedSnapshot?.items ?? const <InstanceCatalogItem>[];

        return Watch((context) {
          final runningCount = items
              .where((item) => _runtimeStore.isRunning(item.path))
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              _PageHeader(
                instanceCount: items.length,
                runningCount: runningCount,
                isEditingLayout: _isEditingLayout,
                canAddCard: _availableCardIds.isNotEmpty,
                onAddCard: _showAddCardSheet,
                onResetLayout: _resetLayout,
                onEditLayout: () {
                  setState(() => _isEditingLayout = !_isEditingLayout);
                },
              ),
              const SizedBox(height: 16),
              DashboardGrid(
                unitWidth: 120,
                unitHeight: 156,
                spacing: 16,
                isEditing: _isEditingLayout,
                onReorder: _saveLayoutOrder,
                onRemove: _removeCard,
                items: _buildGridItems(items),
              ),
              if (_isEditingLayout &&
                  (_layout ?? DashboardLayout.defaultLayout)
                      .widgets
                      .isEmpty) ...[
                const SizedBox(height: 24),
                Center(
                  child: FilledButton.tonalIcon(
                    onPressed: _availableCardIds.isEmpty
                        ? null
                        : _showAddCardSheet,
                    icon: const Icon(Icons.add),
                    label: const Text('添加卡片'),
                  ),
                ),
              ],
              if (items.isEmpty) ...[
                const SizedBox(height: 24),
                Center(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      getIt<ShellNavigationController>().navigateTo(
                        ShellTab.instances,
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('还没有实例，去创建'),
                  ),
                ),
              ],
            ],
          );
        });
      },
    );
  }
}
