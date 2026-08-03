import 'package:flutter/foundation.dart';

/// Shell 主导航 tab 下标（与 [Shell] 中 `_navigationItems` 顺序一致）。
abstract final class ShellTab {
  static const dashboard = 0;
  static const instances = 1;
  static const tools = 2;
  static const settings = 3;
}

class ShellNavigationController extends ChangeNotifier {
  int _selectedIndex = ShellTab.dashboard;

  int get selectedIndex => _selectedIndex;

  void navigateTo(int index) {
    if (_selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
  }
}
