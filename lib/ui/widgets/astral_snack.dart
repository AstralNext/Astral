import 'package:flutter/material.dart';

/// 统一 SnackBar 提示（需已 mounted）。
void showAstralSnack(
  BuildContext context,
  String message, {
  Color? backgroundColor,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
    ),
  );
}
