import 'dart:async';

import 'package:flutter/material.dart';

class ShellContentController extends ChangeNotifier {
  Widget? _overlayContent;
  String? _overlayTitle;
  VoidCallback? _onClose;
  Future<bool> Function()? _canClose;
  bool _closing = false;

  Widget? get overlayContent => _overlayContent;
  String? get overlayTitle => _overlayTitle;
  bool get hasOverlay => _overlayContent != null;

  void showOverlay({
    required Widget content,
    required String title,
    VoidCallback? onClose,
    Future<bool> Function()? canClose,
  }) {
    _overlayContent = content;
    _overlayTitle = title;
    _onClose = onClose;
    _canClose = canClose;
    notifyListeners();
  }

  /// 尝试关闭 overlay；[canClose] 返回 false 时中止。
  Future<bool> tryCloseOverlay() async {
    if (_overlayContent == null || _closing) return true;
    _closing = true;
    try {
      if (_canClose != null) {
        final ok = await _canClose!();
        if (!ok) return false;
      }
      _forceClose();
      return true;
    } finally {
      _closing = false;
    }
  }

  /// 无条件关闭（仅内部兜底；外部请用 [tryCloseOverlay]）。
  void _forceClose() {
    final onClose = _onClose;
    _overlayContent = null;
    _overlayTitle = null;
    _onClose = null;
    _canClose = null;
    onClose?.call();
    notifyListeners();
  }
}
