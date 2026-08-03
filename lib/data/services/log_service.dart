import 'dart:async';

import 'package:logger/logger.dart';

/// 日志条目模型
/// 用于在内存中保存每一条日志的时间、级别、模块和内容
class LogEntry {
  /// 记录时间
  final DateTime time;

  /// 日志级别（如 Level.info 等的字符串表示）
  final String level;

  /// 产生日志的模块或来源（便于过滤和定位）
  final String module;

  /// 日志内容
  final String message;

  /// 实例路径（可选，用于按实例过滤）
  final String? instancePath;

  LogEntry({
    required this.time,
    required this.level,
    required this.module,
    required this.message,
    this.instancePath,
  });
}

/// 日志服务
/// 负责把日志输出到控制台（通过 logger 包）并在内存中保存历史，同时提供一个可订阅的流用于实时监听
class LogService {
  /// 内存环形上限，避免长期运行无限增长。
  static const int maxEntries = 3000;
  static const int maxAlerts = 64;

  // 用于控制台输出的 Logger 实例
  final Logger _logger;

  // 存放历史日志条目的内存列表（有界）
  final _entries = <LogEntry>[];
  final _alerts = <LogEntry>[];

  // 广播型 StreamController，允许多个订阅者同时监听新日志
  final _streamController = StreamController<LogEntry>.broadcast();
  final _alertController = StreamController<LogEntry>.broadcast();

  /// 用于外部订阅实时日志的流
  Stream<LogEntry> get stream => _streamController.stream;

  /// 仅 warning / error 级别，供摘要卡使用。
  Stream<LogEntry> get alertStream => _alertController.stream;

  LogService()
    : _logger = Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 5,
          lineLength: 80,
          colors: true,
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        ),
      );

  static bool isAlertLevel(Level level) {
    return level == Level.warning ||
        level == Level.error ||
        level == Level.fatal;
  }

  /// 最近告警（新→旧）。
  List<LogEntry> recentAlerts({int limit = 8}) {
    if (_alerts.isEmpty) return const [];
    final take = limit.clamp(0, _alerts.length);
    return _alerts.sublist(_alerts.length - take).reversed.toList();
  }

  /// 记录一条日志：同时输出到控制台并写入内存与流中
  void log(String module, Level level, String message, {String? instancePath}) {
    _logger.log(level, '[$module] $message');

    final entry = LogEntry(
      time: DateTime.now(),
      level: level.toString(),
      module: module,
      message: message,
      instancePath: instancePath,
    );

    _entries.add(entry);
    final overflow = _entries.length - maxEntries;
    if (overflow > 0) {
      _entries.removeRange(0, overflow);
    }
    if (!_streamController.isClosed) {
      _streamController.add(entry);
    }

    if (isAlertLevel(level)) {
      _alerts.add(entry);
      final alertOverflow = _alerts.length - maxAlerts;
      if (alertOverflow > 0) {
        _alerts.removeRange(0, alertOverflow);
      }
      if (!_alertController.isClosed) {
        _alertController.add(entry);
      }
    }
  }

  /// info 级别快捷方法
  void info(String module, String message, {String? instancePath}) =>
      log(module, Level.info, message, instancePath: instancePath);

  /// warning 级别快捷方法
  void warn(String module, String message, {String? instancePath}) =>
      log(module, Level.warning, message, instancePath: instancePath);

  /// error 级别快捷方法
  void error(String module, String message, {String? instancePath}) =>
      log(module, Level.error, message, instancePath: instancePath);

  /// 获取指定实例的日志历史
  List<LogEntry> getHistoryForInstance(String instancePath) {
    return _entries.where((e) => e.instancePath == instancePath).toList();
  }

  /// 清空指定实例的日志
  void clearForInstance(String instancePath) {
    _entries.removeWhere((e) => e.instancePath == instancePath);
    _alerts.removeWhere((e) => e.instancePath == instancePath);
  }

  /// 释放资源：关闭流控制器
  void dispose() {
    _streamController.close();
    _alertController.close();
  }
}
