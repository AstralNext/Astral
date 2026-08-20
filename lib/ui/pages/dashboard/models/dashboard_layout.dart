import 'dart:convert';

class DashboardWidgetConfig {
  final String id;
  final String? type;
  final String? instancePath;
  final int widthSpan;
  final int heightSpan;
  final int order;

  const DashboardWidgetConfig({
    required this.id,
    this.type,
    this.instancePath,
    this.widthSpan = 1,
    this.heightSpan = 1,
    this.order = 0,
  });

  String get catalogType {
    final t = type?.trim();
    if (t == null || t.isEmpty) return id;
    return t;
  }

  DashboardWidgetConfig copyWith({
    String? id,
    String? type,
    String? instancePath,
    bool clearInstancePath = false,
    int? widthSpan,
    int? heightSpan,
    int? order,
  }) {
    return DashboardWidgetConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      instancePath:
          clearInstancePath ? null : (instancePath ?? this.instancePath),
      widthSpan: widthSpan ?? this.widthSpan,
      heightSpan: heightSpan ?? this.heightSpan,
      order: order ?? this.order,
    );
  }

  /// 单例卡只存 id + order；可重复卡额外存 type / instancePath。
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'id': id, 'order': order};
    if (catalogType != id) map['type'] = catalogType;
    final path = instancePath?.trim();
    if (path != null && path.isNotEmpty) map['instancePath'] = path;
    return map;
  }

  factory DashboardWidgetConfig.fromMap(Map<String, dynamic> map) {
    return DashboardWidgetConfig(
      id: map['id'] as String,
      type: map['type'] as String?,
      instancePath: map['instancePath'] as String?,
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }
}

class DashboardLayout {
  final List<DashboardWidgetConfig> widgets;

  const DashboardLayout({required this.widgets});

  DashboardLayout copyWith({List<DashboardWidgetConfig>? widgets}) {
    return DashboardLayout(widgets: widgets ?? this.widgets);
  }

  Map<String, dynamic> toMap() {
    return {
      'widgets': widgets.map((w) => w.toMap()).toList(),
    };
  }

  factory DashboardLayout.fromMap(Map<String, dynamic> map) {
    final raw = map['widgets'];
    if (raw is! List) {
      throw const FormatException('dashboard layout missing widgets');
    }
    return DashboardLayout(
      widgets: [
        for (final w in raw)
          DashboardWidgetConfig.fromMap(w as Map<String, dynamic>),
      ],
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DashboardLayout.fromJson(String source) =>
      DashboardLayout.fromMap(jsonDecode(source) as Map<String, dynamic>);

  static DashboardWidgetConfig _w(
    String id, {
    int widthSpan = 2,
    int heightSpan = 1,
    required int order,
  }) {
    return DashboardWidgetConfig(
      id: id,
      type: id,
      widthSpan: widthSpan,
      heightSpan: heightSpan,
      order: order,
    );
  }

  static const peerInfoType = 'peer_info';

  static bool allowsMultiple(String type) => type == peerInfoType;

  /// 全部可选卡片（添加面板用）。装饰卡已移除（hitokoto/tips/today）。
  static List<DashboardWidgetConfig> get catalog => [
        _w('traffic', widthSpan: 4, order: 0),
        _w('memory', order: 1),
        _w('quality', order: 2),
        _w('core', order: 3),
        _w('uptime', order: 4),
        _w('shortcuts', order: 5),
        _w('update', order: 6),
        _w('nodes', order: 7),
        _w('duplex', order: 8),
        _w('logs', order: 9),
        _w(peerInfoType, widthSpan: 2, heightSpan: 2, order: 10),
      ];

  /// 默认：全宽流量 + 两列小卡（连接质量 / 节点、内存 / 内核）。
  static DashboardLayout get defaultLayout => DashboardLayout(
        widgets: [
          _w('traffic', widthSpan: 4, order: 0),
          _w('quality', order: 1),
          _w('nodes', order: 2),
          _w('memory', order: 3),
          _w('core', order: 4),
        ],
      );

  static final knownIds = {for (final w in catalog) w.catalogType};

  static const titles = <String, String>{
    'traffic': '网络速度',
    'memory': '内存信息',
    'quality': '连接质量',
    'nodes': '活跃连接',
    'duplex': '上下行',
    'uptime': '运行时长',
    'logs': '日志摘要',
    'shortcuts': '快捷入口',
    'update': '更新',
    'core': '内核',
    peerInfoType: '节点信息',
  };

  static String titleOf(String type) => titles[type] ?? type;

  static DashboardWidgetConfig? catalogEntry(String type) {
    for (final w in catalog) {
      if (w.catalogType == type) return w;
    }
    return null;
  }

  static String newSlotId(String type) =>
      '${type}_${DateTime.now().microsecondsSinceEpoch}';

  /// 去未知；单例卡去重；可重复卡按 id 保留并带上绑定。
  static DashboardLayout normalize(DashboardLayout layout) {
    final catalogByType = {for (final w in catalog) w.catalogType: w};
    final seenSingleton = <String>{};
    final seenIds = <String>{};
    final ordered = [...layout.widgets]
      ..sort((a, b) => a.order.compareTo(b.order));

    final kept = <DashboardWidgetConfig>[];
    for (final w in ordered) {
      final type = w.catalogType;
      final def = catalogByType[type];
      if (def == null) continue;
      if (!allowsMultiple(type)) {
        if (!seenSingleton.add(type)) continue;
        kept.add(def.copyWith(order: kept.length));
        continue;
      }
      if (!seenIds.add(w.id)) continue;
      kept.add(
        def.copyWith(
          id: w.id,
          type: type,
          instancePath: w.instancePath,
          order: kept.length,
        ),
      );
    }

    if (kept.isEmpty) return defaultLayout;
    return DashboardLayout(widgets: kept);
  }
}
