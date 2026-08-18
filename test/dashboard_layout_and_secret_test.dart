import 'package:astral/ui/pages/dashboard/models/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardLayout.normalize', () {
    test('keeps known widgets and applies catalog spans', () {
      final old = DashboardLayout(
        widgets: [
          const DashboardWidgetConfig(
            id: 'memory',
            widthSpan: 2,
            heightSpan: 1,
            order: 0,
          ),
          const DashboardWidgetConfig(
            id: 'traffic',
            widthSpan: 2,
            heightSpan: 1,
            order: 1,
          ),
        ],
      );

      final normalized = DashboardLayout.normalize(old);

      expect(
        normalized.widgets.map((w) => w.id).toList(),
        ['memory', 'traffic'],
      );
      expect(
        normalized.widgets.firstWhere((w) => w.id == 'traffic').widthSpan,
        4,
      );
    });

    test('drops unknown ids and dedupes', () {
      final old = DashboardLayout(
        widgets: const [
          DashboardWidgetConfig(
            id: 'quality',
            widthSpan: 2,
            heightSpan: 1,
            order: 0,
          ),
          DashboardWidgetConfig(
            id: 'unknown_card',
            widthSpan: 1,
            heightSpan: 1,
            order: 1,
          ),
          DashboardWidgetConfig(
            id: 'quality',
            widthSpan: 2,
            heightSpan: 1,
            order: 2,
          ),
        ],
      );

      final normalized = DashboardLayout.normalize(old);
      expect(normalized.widgets.map((w) => w.id).toList(), ['quality']);
    });

    test('empty layout falls back to default', () {
      const empty = DashboardLayout(widgets: []);
      final normalized = DashboardLayout.normalize(empty);
      expect(
        normalized.widgets.map((w) => w.id).toList(),
        DashboardLayout.defaultLayout.widgets.map((w) => w.id).toList(),
      );
    });

    test('default layout stays slim', () {
      expect(
        DashboardLayout.defaultLayout.widgets.map((w) => w.id).toList(),
        ['traffic', 'quality', 'core', 'shortcuts'],
      );
    });

    test('persists only id and order', () {
      final json = DashboardLayout.defaultLayout.toJson();
      final map = DashboardLayout.fromJson(json).toMap();
      expect(map.containsKey('version'), isFalse);
      expect(map.containsKey('columns'), isFalse);
      expect(map.containsKey('unitHeight'), isFalse);
      final widgets = map['widgets'] as List;
      expect(widgets, isNotEmpty);
      final first = widgets.first as Map<String, dynamic>;
      expect(first.keys.toSet(), {'id', 'order'});
    });

    test('fromMap ignores legacy span fields', () {
      final layout = DashboardLayout.fromMap({
        'widgets': [
          {
            'id': 'traffic',
            'order': 0,
            'widthSpan': 99,
            'heightSpan': 99,
          },
        ],
      });
      final normalized = DashboardLayout.normalize(layout);
      expect(normalized.widgets.single.widthSpan, 4);
    });

    test('keeps multiple peer_info cards with bindings', () {
      const layout = DashboardLayout(
        widgets: [
          DashboardWidgetConfig(
            id: 'peer_info_a',
            type: 'peer_info',
            instancePath: '/tmp/a.toml',
            order: 0,
          ),
          DashboardWidgetConfig(
            id: 'peer_info_b',
            type: 'peer_info',
            instancePath: '/tmp/b.toml',
            order: 1,
          ),
          DashboardWidgetConfig(
            id: 'quality',
            order: 2,
          ),
          DashboardWidgetConfig(
            id: 'quality',
            order: 3,
          ),
          DashboardWidgetConfig(
            id: 'peer_info_a',
            type: 'peer_info',
            instancePath: '/tmp/dup.toml',
            order: 4,
          ),
        ],
      );

      final normalized = DashboardLayout.normalize(layout);
      expect(
        normalized.widgets.map((w) => w.id).toList(),
        ['peer_info_a', 'peer_info_b', 'quality'],
      );
      expect(
        normalized.widgets.firstWhere((w) => w.id == 'peer_info_a').instancePath,
        '/tmp/a.toml',
      );
      expect(
        normalized.widgets.firstWhere((w) => w.id == 'peer_info_b').widthSpan,
        4,
      );
      expect(
        normalized.widgets.firstWhere((w) => w.id == 'peer_info_b').heightSpan,
        2,
      );
    });

    test('persists type and instancePath for repeatable cards', () {
      const layout = DashboardLayout(
        widgets: [
          DashboardWidgetConfig(
            id: 'peer_info_1',
            type: 'peer_info',
            instancePath: '/tmp/home.toml',
            order: 0,
          ),
        ],
      );
      final map = DashboardLayout.fromJson(layout.toJson()).toMap();
      final widget = (map['widgets'] as List).single as Map<String, dynamic>;
      expect(widget['id'], 'peer_info_1');
      expect(widget['type'], 'peer_info');
      expect(widget['instancePath'], '/tmp/home.toml');
      expect(widget.containsKey('widthSpan'), isFalse);
    });
  });
}
