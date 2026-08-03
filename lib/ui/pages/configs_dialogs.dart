import 'package:flutter/material.dart';

/// 配置页：输入名称对话框。
Future<String?> promptConfigsName(
  BuildContext context, {
  required String title,
  required String hintText,
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);

  try {
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hintText),
            onSubmitted: (input) => Navigator.of(context).pop(input),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  } finally {
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        controller.dispose();
      } catch (_) {}
    });
  }
}
