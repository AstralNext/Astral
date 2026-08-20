import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:vm_service/vm_service.dart' hide Isolate;
import 'package:vm_service/vm_service_io.dart';

/// Dart 堆（对象 + external），不含引擎 / 内核 / GPU。
class DartHeap {
  DartHeap._();
  static final instance = DartHeap._();

  VmService? _vm;
  String? _isolateId;
  Future<void>? _connecting;
  var _gaveUp = false;

  Future<int?> sampleBytes() async {
    if (_gaveUp) return null;
    try {
      await _ensureConnected();
      final vm = _vm;
      final id = _isolateId;
      if (vm == null || id == null) {
        _gaveUp = true;
        return null;
      }
      final usage = await vm.getMemoryUsage(id).timeout(
        const Duration(seconds: 1),
      );
      return (usage.heapUsage ?? 0) + (usage.externalUsage ?? 0);
    } catch (_) {
      await _vm?.dispose();
      _vm = null;
      _isolateId = null;
      return null;
    }
  }

  Future<void> _ensureConnected() async {
    if (_vm != null) return;
    _connecting ??= _connect();
    try {
      await _connecting;
    } finally {
      _connecting = null;
    }
  }

  Future<void> _connect() async {
    var info = await developer.Service.getInfo().timeout(
      const Duration(seconds: 1),
    );
    var uri = info.serverWebSocketUri;
    if (uri == null) {
      info = await developer.Service.controlWebServer(
        enable: true,
        silenceOutput: true,
      ).timeout(const Duration(seconds: 1));
      uri = info.serverWebSocketUri;
    }
    if (uri == null) return;

    final vm = await vmServiceConnectUri(uri.toString()).timeout(
      const Duration(seconds: 2),
    );
    var isolateId = developer.Service.getIsolateId(Isolate.current);
    if (isolateId == null) {
      final isolates = (await vm.getVM()).isolates ?? const <IsolateRef>[];
      for (final iso in isolates) {
        if (iso.isSystemIsolate == true) continue;
        isolateId = iso.id;
        break;
      }
      isolateId ??= isolates.isEmpty ? null : isolates.first.id;
    }
    _vm = vm;
    _isolateId = isolateId;
  }
}
