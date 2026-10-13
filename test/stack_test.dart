import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';

import 'support/fixtures.dart';

/// Stack (8.6.0) - the first contract container whose children occupy the SAME
/// place.
///
/// Together with the 8.5.0 grid this closes the layout table: "how many children in a
/// row" x "how wide each one is" has four answers, and all four are now named by
/// widgets rather than guessed by the reader.
void main() {
  _fillTests();

  Map<String, Object?> stack(
    List<Map<String, Object?>> children, {
    String alignHorizontal = 'center',
    String alignVertical = 'center',
    String? padding,
  }) => {
    'id': 'stack',
    'type': 'Stack',
    'props': {
      'alignHorizontal': alignHorizontal,
      'alignVertical': alignVertical,
    },
    // 9.0.0: stack fields live in `style`, like any node.
    if (padding != null) 'style': {'padding': padding},
    'children': children,
  };

  /// An illustration 1:1 - a layer that takes the whole stack width and sets its height.
  Map<String, Object?> cover(String id) => {
    'id': id,
    'type': 'Image',
    'props': {
      'source': {'kind': 'asset', 'asset': 'placeholder'},
      'alt': id,
      'aspectRatio': '1:1',
    },
  };

  Rect rectOf(WidgetTester tester, String text) => tester.getRect(find.text(text));

  /// The box of OUR stack: `MaterialApp` has its own `Stack`s, so they cannot be
  /// searched by type over the whole tree - we take the nearest ancestor of the layer.
  Rect overlayRect(WidgetTester tester, String layerText) => tester.getRect(
    find.ancestor(of: find.text(layerText), matching: find.byType(Stack)).first,
  );

  group('model', () {
    StackNode parse(Map<String, Object?> node) =>
        flattenDocument(docWith([node])).whereType<StackNode>().single;

    test('the two alignment axes are read independently', () {
      final node = parse(
        stack([textNode('А', id: 'a')], alignHorizontal: 'end', alignVertical: 'start'),
      );

      expect(node.alignHorizontal, AlignToken.end);
      expect(node.alignVertical, AlignToken.start);
    });

    test('an unknown value degrades to center, not failing the node', () {
      // The field default is from the artifact, not from memory: `center` is in the schema.
      final node = parse(
        stack([textNode('А', id: 'a')], alignHorizontal: 'діагональ', alignVertical: 'діагональ'),
      );

      expect(node.alignHorizontal, AlignToken.center);
      expect(node.alignVertical, AlignToken.center);
    });
  });

  group('layout', () {
    testWidgets('layers lie on top of each other, not one under another', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          stack([textNode('Низ', id: 'back'), textNode('Верх', id: 'front')]),
        ]),
      );

      final back = rectOf(tester, 'Низ');
      final front = rectOf(tester, 'Верх');

      // Equal centres mean a layer did not push its neighbour - that is how
      // stacking differs from a column.
      expect(front.center.dy, closeTo(back.center.dy, 0.01));
      expect(front.center.dx, closeTo(back.center.dx, 0.01));
    });

    testWidgets('the stack takes the full width - like a column, not like the widest layer', (tester) async {
      // This is a compatibility requirement with the builder preview model: it gives a layer ALL
      // the available width, and if Flutter shrank the stack to its child, two readers
      // would answer "does this text fit" differently.
      await pumpDocument(
        tester,
        docWith([
          stack([textNode('Вузький', id: 'only')], alignHorizontal: 'start'),
        ]),
      );
      final atStart = rectOf(tester, 'Вузький');
      final overlay = overlayRect(tester, 'Вузький');

      await pumpDocument(
        tester,
        docWith([
          stack([textNode('Вузький', id: 'only')], alignHorizontal: 'end'),
        ]),
      );
      final atEnd = rectOf(tester, 'Вузький');

      // The stack is wider than its only layer - otherwise "at start" and "at end"
      // would give the same place.
      expect(overlay.width, greaterThan(atStart.width));
      expect(atStart.left, closeTo(overlay.left, 0.01));
      expect(atEnd.right, closeTo(overlay.right, 0.01));
    });

    testWidgets('alignment puts a small layer into the named corner', (tester) async {
      for (final corner in [
        (h: 'start', v: 'start'),
        (h: 'end', v: 'start'),
        (h: 'start', v: 'end'),
        (h: 'end', v: 'end'),
      ]) {
        await pumpDocument(
          tester,
          docWith([
            stack([
              cover('base'),
              textNode('Мітка', id: 'mark'),
            ], alignHorizontal: corner.h, alignVertical: corner.v),
          ]),
        );

        final base = overlayRect(tester, 'Мітка');
        final mark = rectOf(tester, 'Мітка');
        final reason = '${corner.h}/${corner.v}';

        if (corner.h == 'start') {
          expect(mark.left, closeTo(base.left, 0.01), reason: reason);
        } else {
          expect(mark.right, closeTo(base.right, 0.01), reason: reason);
        }
        if (corner.v == 'start') {
          expect(mark.top, closeTo(base.top, 0.01), reason: reason);
        } else {
          expect(mark.bottom, closeTo(base.bottom, 0.01), reason: reason);
        }
      }
    });

    testWidgets('a hidden layer leaves no room behind', (tester) async {
      final hidden = textNode(
        'Верх',
        id: 'front',
        visibleIf: {'path': 'task.completed', 'op': 'isTrue'},
      );
      await pumpDocument(
        tester,
        docWith([
          stack([textNode('Низ', id: 'back'), hidden]),
        ]),
        data: const {'task': {'completed': false}},
      );

      expect(find.text('Верх'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty stack draws nothing and does not crash the screen', (tester) async {
      await pumpDocument(tester, docWith([stack(const [])]));

      expect(tester.takeException(), isNull);
    });
  });
}

/*
 * A LAYER OVER THE WHOLE STACK (8.14.0).
 *
 * What is checked is exactly why this field was needed: a gradient bar has no content
 * of its own, so without `fill` its width is zero - the layer does not "look different",
 * it is not visible at all.
 */
void _fillTests() {
  Map<String, Object?> band({bool fill = false}) => {
    'id': 'band',
    'type': 'Container',
    'props': {'gap': 'none'},
    'style': {
      'background': {'kind': 'gradient', 'gradient': 'brandBackdrop'},
      'height': 40,
    },
    'children': <Map<String, Object?>>[],
    if (fill) 'fill': true,
  };

  Map<String, Object?> panorama() => {
    'id': 'photo',
    'type': 'Image',
    'props': {
      'source': {'kind': 'asset', 'asset': 'banner'},
      'aspectRatio': '16:9',
      'alt': 'Панорама',
    },
  };

  Map<String, Object?> overlay(List<Map<String, Object?>> layers) => {
    'id': 'stack',
    'type': 'Stack',
    'props': {'alignHorizontal': 'center', 'alignVertical': 'end'},
    'children': layers,
  };

  group('a layer over the whole stack', () {
    testWidgets('parsing: no field - an ordinary layer', (tester) async {
      final node = flattenDocument(docWith([overlay([panorama(), band()])]))
          .whereType<ContainerNode>()
          .single;

      expect(node.fill, isFalse);
    });

    testWidgets('parsing: `fill: true` reaches the model', (tester) async {
      final node = flattenDocument(docWith([overlay([panorama(), band(fill: true)])]))
          .whereType<ContainerNode>()
          .single;

      expect(node.fill, isTrue);
    });

    /*
     * The main test of the field. Without it the bar has ZERO width - and that is why
     * "a gradient over a panorama" was not expressible by any combination of existing fields.
     */
    testWidgets('without fill the bar has zero width, with fill - the stack width', (tester) async {
      await pumpDocument(tester, docWith([overlay([panorama(), band()])]));
      final own = tester.getSize(find.byType(DecoratedBox).last).width;

      await pumpDocument(tester, docWith([overlay([panorama(), band(fill: true)])]));
      final stretched = tester.getSize(find.byType(DecoratedBox).last).width;

      expect(own, 0);
      expect(stretched, greaterThan(0));
    });

    /*
     * A stretched layer ACCEPTS the size rather than sets it: the stack is still measured by
     * the panorama. Otherwise a bar 40 tall would shrink the stack to itself, and the photo
     * would vanish - the field would break exactly the screen it exists for.
     */
    testWidgets('the stack is measured by the non-stretched layer, not the stretched one', (tester) async {
      await pumpDocument(tester, docWith([overlay([panorama()])]));
      final withoutBand = tester.getSize(find.byType(Stack).last).height;

      await pumpDocument(tester, docWith([overlay([panorama(), band(fill: true)])]));
      final withBand = tester.getSize(find.byType(Stack).last).height;

      expect(withBand, withoutBand);
    });
  });
}
