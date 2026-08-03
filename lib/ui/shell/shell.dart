import 'dart:async';
import 'dart:io';

import 'package:astral/config/app_dimensions.dart';
import 'package:astral/config/theme.dart';
import 'package:astral/data/services/update_service.dart';
import 'package:astral/data/state/settings_state.dart';
import 'package:astral/data/state/update_state.dart';
import 'package:astral/di.dart';
import 'package:astral/data/state/instance_runtime_store.dart';
import 'package:astral/ui/pages/dashboard_page.dart';
import 'package:astral/ui/pages/instances_page.dart';
import 'package:astral/ui/pages/settings_page.dart';
import 'package:astral/ui/pages/tools_page.dart';
import 'package:astral/ui/shell/shell_content_controller.dart';
import 'package:astral/ui/shell/shell_navigation_controller.dart';
import 'package:astral/ui/shell/shell_title_bar.dart';
import 'package:astral/ui/shell/shell_tray_controller.dart';
import 'package:astral/ui/widgets/navigation/bottom_nav.dart';
import 'package:astral/ui/widgets/navigation/left_nav.dart';
import 'package:astral/ui/widgets/navigation/navigation_item.dart';
import 'package:astral/ui/widgets/shell_tab_pane.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WindowListener, TrayListener {
  late final ShellNavigationController _navController;
  late final ShellContentController _contentController;
  late final List<NavigationItem> _navigationItems;
  late final ShellTrayController _trayController;
  final TrayManager _trayManager = TrayManager.instance;

  @override
  void initState() {
    super.initState();
    _navController = getIt<ShellNavigationController>();
    _contentController = getIt<ShellContentController>();
    _trayController = ShellTrayController(_trayManager);

    _navigationItems = [
      NavigationItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        label: '面板',
        page: const DashboardPage(key: PageStorageKey('dashboard')),
      ),
      NavigationItem(
        icon: Icons.developer_board_outlined,
        activeIcon: Icons.developer_board,
        label: '实例',
        page: const InstancesPage(key: PageStorageKey('instances')),
      ),
      NavigationItem(
        icon: Icons.build_outlined,
        activeIcon: Icons.build,
        label: '工具',
        page: const ToolsPage(key: PageStorageKey('tools')),
      ),
      NavigationItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: '设置',
        page: const SettingsPage(key: PageStorageKey('settings')),
      ),
    ];

    _navController.addListener(_onNavigationChanged);
    _contentController.addListener(_onContentChanged);
    _syncNetworkPolling();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final updateState = getIt<UpdateState>();
      if (updateState.autoCheckUpdate.value) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            getIt<UpdateService>().checkForUpdates(
              context,
              showNoUpdateMessage: false,
              showFailureMessage: false,
            );
          }
        });
      }
    });

    _setupDesktopCloseBehavior();
  }

  @override
  void dispose() {
    _navController.removeListener(_onNavigationChanged);
    _contentController.removeListener(_onContentChanged);
    if (_isDesktopPlatform) {
      windowManager.removeListener(this);
      _trayManager.removeListener(this);
    }
    super.dispose();
  }

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _setupDesktopCloseBehavior() async {
    if (!_isDesktopPlatform) return;

    windowManager.addListener(this);
    _trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _trayController.init();
  }

  Future<void> _handleCloseRequested() async {
    if (!_isDesktopPlatform) return;
    final closeMinimize = getIt<SettingsState>().closeMinimize.value;
    if (closeMinimize) {
      await windowManager.hide();
      return;
    }
    await _trayController.exitApp();
  }

  @override
  void onWindowClose() {
    unawaited(_handleCloseRequested());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_trayController.showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_trayController.showWindow());
      case 'exit':
        unawaited(_trayController.exitApp());
    }
  }

  void _onNavigationChanged() {
    _syncNetworkPolling();
    setState(() {});
  }

  void _onContentChanged() {
    _syncNetworkPolling();
    setState(() {});
  }

  /// Dashboard / Instances / overlay：拉秒级流量指标。
  /// 切到其它 Tab 只停指标采样，存活探测仍继续。
  void _syncNetworkPolling() {
    if (!getIt.isRegistered<InstanceRuntimeStore>()) return;
    final need = _navController.selectedIndex <= ShellTab.instances ||
        _contentController.hasOverlay;
    getIt<InstanceRuntimeStore>().setPollingEnabled(need, forcePoll: need);
  }

  Future<void> _handleDestinationSelected(int index) async {
    if (_contentController.hasOverlay) {
      final closed = await _contentController.tryCloseOverlay();
      if (!closed) return;
    }
    if (!mounted) return;
    if (_navController.selectedIndex != index) {
      _navController.navigateTo(index);
    } else {
      setState(() {});
    }
  }

  Future<void> _handleOverlayBack() async {
    await _contentController.tryCloseOverlay();
  }

  Future<void> _handleSystemPop() async {
    if (_contentController.hasOverlay) {
      await _contentController.tryCloseOverlay();
    }
  }

  Widget _buildTabBody(bool isCompact, int selectedIndex) {
    final pages = [for (final item in _navigationItems) item.page];
    final stack = ShellTabStack(index: selectedIndex, children: pages);

    if (!isCompact) return stack;

    return SafeArea(
      bottom: false,
      child: stack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final sidebarColor = palette.sidebar;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < AppDimensions.narrowBreakpoint;

    final selectedIndex = _navController.selectedIndex;
    final hasOverlay = _contentController.hasOverlay;
    final overlayTitle = _contentController.overlayTitle;

    const contentRadius = BorderRadius.only(
      topLeft: Radius.circular(AppDimensions.radiusMd),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_handleSystemPop());
      },
      child: Scaffold(
        backgroundColor: sidebarColor,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isCompact)
              LeftNav(
                items: _navigationItems,
                selectedIndex: selectedIndex,
                onSelected: (index) =>
                    unawaited(_handleDestinationSelected(index)),
              ),
            Expanded(
              child: ColoredBox(
                color: sidebarColor,
                child: Column(
                  children: [
                    if (_isDesktopPlatform)
                      ShellTitleBar(
                        height: 44,
                        title: hasOverlay ? overlayTitle! : 'Astral',
                        showBackButton: hasOverlay,
                        onBack: hasOverlay
                            ? () => unawaited(_handleOverlayBack())
                            : null,
                        onClose: () => unawaited(_handleCloseRequested()),
                      ),
                    if (isCompact && hasOverlay)
                      ShellCompactOverlayAppBar(
                        title: overlayTitle!,
                        onBack: () => unawaited(_handleOverlayBack()),
                      ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: isCompact && hasOverlay
                            ? BorderRadius.zero
                            : contentRadius,
                        child: ColoredBox(
                          color: palette.background,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: hasOverlay
                                ? KeyedSubtree(
                                    key: const ValueKey('shell-overlay'),
                                    child: _contentController.overlayContent!,
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('shell-tabs'),
                                    child: _buildTabBody(
                                      isCompact,
                                      selectedIndex,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: isCompact && !hasOverlay
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.card,
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadowSoft,
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: BottomNav(
                    navigationItems: _navigationItems,
                    selectedIndex: selectedIndex,
                    onSelected: (index) =>
                        unawaited(_handleDestinationSelected(index)),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
