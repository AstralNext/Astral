import 'dart:io';

/// 内核运行模式：内嵌 FFI 或独立 astral-core 服务。
enum KernelMode {
  embedded,
  service;

  /// Android 内嵌，其它平台一律服务。
  static KernelMode forPlatform() =>
      Platform.isAndroid ? KernelMode.embedded : KernelMode.service;

  String get label => this == KernelMode.service ? '服务' : '内嵌';
}
