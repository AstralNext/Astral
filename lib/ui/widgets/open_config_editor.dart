import 'package:astral/di.dart';
import 'package:astral/ui/pages/config_editor_page.dart';
import 'package:astral/ui/shell/shell_content_controller.dart';
import 'package:flutter/material.dart';

/// 打开配置编辑 overlay；返回时自动保存。
void openConfigEditorOverlay({
  required BuildContext context,
  required String path,
  required String title,
  VoidCallback? onClose,
}) {
  final editorKey = GlobalKey<ConfigEditorPageState>();
  getIt<ShellContentController>().showOverlay(
    content: ConfigEditorPage(key: editorKey, path: path),
    title: title,
    onClose: onClose,
    canClose: () async {
      final state = editorKey.currentState;
      if (state == null) return true;
      return state.flushSaveOnClose();
    },
  );
}
