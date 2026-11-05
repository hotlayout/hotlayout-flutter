/// A scale with a `glow` is not clipped by the box of its own node (schema 9.25.0, `x-progressGlow.clip`): the glow
/// lies outside the scale by its blur, and only an ancestor that clips may cut it, as it cuts a shadow. A node
/// without a glow keeps the clip of its radius.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

Map<String, Object?> _scale(String type, {String? glow, Object? border}) => {
  'id': 'scale',
  'type': type,
  'props': {
    'value': {'kind': 'literal', 'value': 60},
    'max': {'kind': 'literal', 'value': 100},
    'glow': ?glow,
  },
  'style': {
    'radius': 'lg',
    'width': 220,
    'height': 220,
    'border': ?border,
    'background': {'kind': 'color', 'color': 'surface'},
  },
};

Finder _clipsAround(Finder scale) =>
    find.ancestor(of: scale, matching: find.byWidgetPredicate((w) => w is ClipRRect || w is ClipRect || w is ClipPath));

void main() {
  Future<int> clips(WidgetTester tester, Map<String, Object?> node, Finder Function() scale) async {
    await pumpDocument(tester, docWith([node]));
    return _clipsAround(scale()).evaluate().length;
  }

  for (final (type, finder) in <(String, Finder Function())>[
    ('ProgressBar', () => find.byType(ProgressTrack)),
    ('CircularProgress', () => find.byType(CustomPaint).last),
  ]) {
    group(type, () {
      testWidgets('with a glow and a radius the box of the node adds no clip', (tester) async {
        final plain = await clips(tester, _scale(type), finder);
        final glowing = await clips(tester, _scale(type, glow: 'strong'), finder);
        expect(plain, greaterThan(0));
        expect(glowing, plain - 1, reason: 'the clip of the radius of the node is gone, the clips above it stay');
      });

      testWidgets('with a glow, a radius and a border the box adds no clip either', (tester) async {
        final border = {'color': 'primary', 'width': 2};
        final plain = await clips(tester, _scale(type, border: border), finder);
        final glowing = await clips(tester, _scale(type, glow: 'soft', border: border), finder);
        expect(glowing, lessThan(plain));
      });

      testWidgets('an unknown word is no glow: the clip stays', (tester) async {
        final plain = await clips(tester, _scale(type), finder);
        expect(await clips(tester, _scale(type, glow: 'huge'), finder), plain);
      });
    });
  }

  testWidgets('the content of an ordinary node with a radius is still clipped', (tester) async {
    await pumpDocument(
      tester,
      docWith([
        {
          'id': 'card',
          'type': 'Container',
          'props': {'direction': 'column', 'gap': 'none'},
          'style': {
            'radius': 'lg',
            'background': {'kind': 'color', 'color': 'surface'},
          },
          'children': [
            {
              'id': 'text',
              'type': 'Text',
              'props': {
                'content': {'kind': 'literal', 'value': 'Inside'},
                'align': 'start',
                'overflow': 'ellipsis',
              },
            },
          ],
        },
      ]),
    );
    expect(_clipsAround(find.text('Inside')), findsWidgets);
  });
}
