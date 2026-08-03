import 'dart:convert';

class DashboardWidgetConfig {
  final String id;
  final int widthSpan;
  final int heightSpan;
  final int order;

  const DashboardWidgetConfig({
    required this.id,
    this.widthSpan = 1,
    this.heightSpan = 1,
    this.order = 0,
  });

  DashboardWidgetConfig copyWith({
    String? id,
    int? widthSpan,
    int? heightSpan,
    int? order,
  }) {
    return DashboardWidgetConfig(
      id: id ?? this.id,
      widthSpan: widthSpan ?? this.widthSpan,
      heightSpan: heightSpan ?? this.heightSpan,
      order: order ?? this.order,
    );
  }

  /// 持久化只存 id + order；span 运行时取自 catalog。
  Map<String, dynamic> toMap() => {'id': id, 'order': order};

  factory DashboardWidgetConfig.fromMap(Map<String, dynamic> map) {
    return DashboardWidgetConfig(
      id: map['id'] as String,
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
      widthSpan: widthSpan,
      heightSpan: heightSpan,
      order: order,
    );
  }

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
      ];

  /// 默认启用：流量、连接质量、内核、快捷入口。
  static DashboardLayout get defaultLayout => DashboardLayout(
        widgets: [
          _w('traffic', widthSpan: 4, order: 0),
          _w('quality', order: 1),
          _w('core', order: 2),
          _w('shortcuts', order: 3),
        ],
      );

  static final knownIds = {for (final w in catalog) w.id};

  static const titles = <String, String>{
    'traffic': '流量',
    'memory': '内存',
    'quality': '连接质量',
    'nodes': '节点脉搏',
    'duplex': '上下行',
    'uptime': '运行时长',
    'logs': '日志摘要',
    'shortcuts': '快捷入口',
    'update': '更新',
    'core': '内核',
  };

  static String titleOf(String id) => titles[id] ?? id;

  static DashboardWidgetConfig? catalogEntry(String id) {
    for (final w in catalog) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// 去未知/重复，并用 catalog 填充 span；空布局回退默认。
  static DashboardLayout normalize(DashboardLayout layout) {
    final catalogById = {for (final w in catalog) w.id: w};
    final seen = <String>{};
    final ordered = [...layout.widgets]
      ..sort((a, b) => a.order.compareTo(b.order));

    final kept = <DashboardWidgetConfig>[];
    for (final w in ordered) {
      final def = catalogById[w.id];
      if (def == null || !seen.add(w.id)) continue;
      kept.add(def.copyWith(order: kept.length));
    }

    if (kept.isEmpty) return defaultLayout;
    return DashboardLayout(widgets: kept);
  }
}
