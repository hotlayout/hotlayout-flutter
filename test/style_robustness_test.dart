import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// NO VALID DOCUMENT MAY THROW.
///
/// The 9.0.0 style gave every node sizes, margins and a border - and with them new
/// ways to put Flutter in a state where it does not "draw oddly" but crashes:
/// infinite scroll width, `Wrap`, a tight grid cell, a row share,
/// a stack layer. There are no claims about the look here - only that every contract widget
/// in each of these places and with each size set survives to the frame.
///
/// Nodes come from the `full-catalog-screen` fixture - one of each type,
/// real ones, not built for the test: a new contract widget will get in here
/// by itself.
void main() {
  final samples = _oneOfEachType(jsonFixture('full-catalog-screen'));

  test('the sample has every child type of the contract', () {
    expect(samples.keys.toSet(), {
      'AppBar', 'Column', 'Row', 'Container', 'Grid', 'Stack', 'Tabs', 'Accordion',
      'ChoiceGroup', 'Repeater', 'Spacer', 'Divider', 'Text', 'Image', 'Icon', 'Button',
      'ListTile', 'ProgressBar', 'CircularProgress', 'Badge',
    });
  });

  // Style sets that most easily bring Flutter to an assert.
  const styles = <String, Map<String, Object?>?>{
    'no style': null,
    'set width': {'width': 140},
    'width larger than the screen': {'width': 1200},
    'set height': {'height': 24},
    'both sizes and margins': {'width': 90, 'height': 60, 'padding': 'lg', 'margin': 'md'},
    'min larger than max': {'minWidth': 300, 'maxWidth': 100, 'minHeight': 80, 'maxHeight': 20},
    'bounds only': {'minWidth': 10, 'maxWidth': 60, 'minHeight': 4, 'maxHeight': 30},
    'size from data that is absent': {
      'width': {'kind': 'binding', 'path': 'nowhere.width', 'fallback': 120},
      'height': {'kind': 'binding', 'path': 'nowhere.height', 'fallback': 40},
    },
    'full box': {
      'padding': {'top': 20, 'start': 'lg'},
      'margin': 'sm',
      'radius': {'topStart': 32, 'bottomEnd': 'pill'},
      'border': {'width': 4, 'color': 'primary'},
      'background': {
        'kind': 'gradient',
        'gradient': {
          'angle': 135,
          'stops': [
            {'color': 'primary', 'position': 0},
            {'color': {'token': 'accent', 'opacity': 0.4}, 'position': 1},
          ],
        },
      },
      'shadow': 'medium',
      'opacity': 0,
      'color': 'onPrimary',
      'typography': {'token': 'titleM', 'fontSize': 22},
    },
    'background image in a small box': {
      'width': 20,
      'height': 20,
      'radius': 'sm',
      'background': {
        'kind': 'image',
        'source': {'kind': 'url', 'url': 'https://cdn.example.com/missing.png'},
        'fit': 'cover',
      },
    },
    'everything unknown': {
      'padding': 'spaceFromFuture',
      'radius': 'radiusFromFuture',
      'shadow': 'shadowFromFuture',
      'color': 'colorFromFuture',
      'typography': 'fontFromFuture',
      'border': {'width': 1, 'color': 'colorFromFuture'},
      'background': {'kind': 'gradient', 'gradient': 'gradientFromFuture'},
    },
  };

  // Places where the child size is determined differently.
  final contexts = <String, Map<String, Object?> Function(Map<String, Object?> child)>{
    'screen column': (child) => child,
    'scrollable row': (child) => _row([child, _filler()], scrollable: true),
    'wrapping row': (child) => _row([child, _filler()], wrap: true),
    'row': (child) => _row([child, _filler()]),
    'row, child with a weight': (child) => _row([
      {...child, 'weight': 2},
      {..._filler(), 'weight': 1},
    ]),
    'scrollable row, child with a weight': (child) => _row([
      {...child, 'weight': 2},
      _filler(),
    ], scrollable: true),
    'container row': (child) => {
      'id': 'host',
      'type': 'Container',
      'props': {'direction': 'row', 'gap': 'sm'},
      'style': {'height': 48},
      'children': [child, _filler()],
    },
    'grid cell': (child) => {
      'id': 'host',
      'type': 'Grid',
      'props': {'columns': 3, 'gap': 'sm'},
      'children': [child, _filler()],
    },
    'stack layer': (child) => _stack([_filler(), child]),
    'layer stretched over the stack': (child) => _stack([
      _filler(),
      {...child, 'fill': true},
    ]),
    'the only layer, and it is stretched': (child) => _stack([
      {...child, 'fill': true},
    ]),
    'row inside a scrollable row': (child) => _row([
      _row([child, _filler(id: 'inner-filler')], id: 'inner'),
      _filler(),
    ], scrollable: true),
  };

  for (final context in contexts.entries) {
    testWidgets('every widget with every style: ${context.key}', (tester) async {
      // We collect ALL the crashes rather than stopping at the first: otherwise one place
      // would hide the rest, and fixing would be by touch.
      final failures = <String>[];
      for (final sample in samples.entries) {
        for (final style in styles.entries) {
          final child = <String, Object?>{...sample.value, 'style': ?style.value};
          await pumpDocument(
            tester,
            docWith([context.value(child)]),
            data: const {'tasks': <Object?>[]},
          );
          Object? error;
          while (true) {
            final next = tester.takeException();
            if (next == null) break;
            error ??= next;
          }
          if (error != null) {
            failures.add('${sample.key} · ${style.key}: ${'$error'.split('\n').first}');
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }

  testWidgets('every widget in right-to-left writing', (tester) async {
    for (final sample in samples.entries) {
      final child = <String, Object?>{...sample.value, 'style': styles['full box']};
      await pumpDocument(tester, docWith([_row([child, _filler()], scrollable: true)]), locale: 'ar');
      expect(tester.takeException(), isNull, reason: sample.key);
    }
  });
}

Map<String, Object?> _filler({String id = 'filler'}) => textNode('Сусід', id: id);

Map<String, Object?> _row(
  List<Map<String, Object?>> children, {
  bool scrollable = false,
  bool wrap = false,
  String id = 'host',
}) => {
  'id': id,
  'type': 'Row',
  'props': {
    'gap': 'sm',
    'align': 'center',
    'justify': 'start',
    'wrap': wrap,
    'scrollable': scrollable,
  },
  'children': children,
};

Map<String, Object?> _stack(List<Map<String, Object?>> layers) => {
  'id': 'host',
  'type': 'Stack',
  'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
  'children': layers,
};

/// The first node of each type from the raw fixture (without `Screen` and without `Tab`:
/// a tab is legal only inside `Tabs`, and gets there together with it).
Map<String, Map<String, Object?>> _oneOfEachType(Map<String, Object?> document) {
  final found = <String, Map<String, Object?>>{};
  void walk(Object? node) {
    if (node is! Map) return;
    final type = node['type'];
    if (type is String && type != 'Screen' && type != 'Tab') {
      found.putIfAbsent(type, () {
        final copy = Map<String, Object?>.from(node);
        // The fixture style, weight and stretch are redundant here: the test supplies them.
        copy
          ..remove('style')
          ..remove('styleWhen')
          ..remove('weight')
          ..remove('fill')
          ..remove('visibleIf');
        return copy;
      });
    }
    final children = node['children'];
    if (children is List) children.forEach(walk);
  }

  for (final screen in document['screens']! as List<Object?>) {
    walk((screen! as Map)['root']);
  }
  return found;
}
