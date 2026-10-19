/// Limits on size and reach: deep trees, long lists, the drawn area, theme font names.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import '../support/fixtures.dart';
import 'support.dart';

Map<String, Object?> _lit(Object? value) => {'kind': 'literal', 'value': value};

/// A document whose screen is [depth] nested containers deep, built as TEXT so that building it
/// does not recurse either.
String _deepDocument(int depth) {
  final open = StringBuffer();
  for (var i = 0; i < depth; i += 1) {
    open.write('{"id":"n$i","type":"Container","props":{"direction":"column","gap":"none"},"children":[');
  }
  final close = ']}' * depth;
  return '{"schemaVersion":"${UiDocument.supportedSchemaVersion}","documentId":"deep","name":"deep",'
      '"initialScreenId":"a","screens":[{"screenId":"a","name":"a","root":{"id":"root","type":"Screen",'
      '"props":{"gap":"none"},"children":[$open{"id":"leaf","type":"Text","props":{"content":{"kind":"literal","value":"leaf"},"align":"start"}}$close]}}]}';
}

void main() {
  group('deep nesting', () {
    for (final depth in [33, 1000, 20000]) {
      testWidgets('$depth levels: parsed without a stack overflow, drawn without an exception', (tester) async {
        final UiDocument doc;
        try {
          doc = UiDocument.fromJsonString(_deepDocument(depth));
        } on StackOverflowError {
          fail('parse overflowed the stack');
        }
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);
        expect(find.text('leaf'), findsNothing, reason: 'deeper than 32 levels below the root is not drawn');
      });
    }

    testWidgets('control: 30 levels are drawn', (tester) async {
      await pumpDocument(tester, UiDocument.fromJsonString(_deepDocument(30)));
      expect(tester.takeException(), isNull);
      expect(find.text('leaf'), findsOneWidget);
    });
  });

  testWidgets('a list draws at most 50 records whatever the data holds', (tester) async {
    final doc = docWith([
      {
        'id': 'list',
        'type': 'Repeater',
        'props': {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'},
        'children': [
          {'id': 'row', 'type': 'Text', 'props': {'content': {'kind': 'binding', 'path': 'item.name', 'fallback': ''}, 'align': 'start'}},
        ],
      },
    ]);
    await pumpDocument(tester, doc, data: {
      'items': [for (var i = 0; i < 100000; i += 1) {'name': 'record $i'}],
    });
    expect(tester.takeException(), isNull);
    expect(find.text('record 49', skipOffstage: false), findsOneWidget);
    expect(find.text('record 50', skipOffstage: false), findsNothing);
  });

  group('the document stays inside the box the host gave it', () {
    final escaping = docWith([
      {
        'id': 'stack',
        'type': 'Stack',
        'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
        'children': [
          {'id': 'base', 'type': 'Container', 'props': {'direction': 'column', 'gap': 'none'}, 'style': {'width': 40, 'height': 40}, 'children': const []},
          {
            'id': 'huge',
            'type': 'Container',
            'props': {'direction': 'column', 'gap': 'none', 'action': {'type': 'steal'}, 'label': _lit('steal')},
            'style': {'width': 4000, 'height': 4000, 'shadow': 'lg'},
            'layer': {'offset': {'x': {'toward': 'end', 'by': 128}, 'y': {'toward': 'bottom', 'by': 128}}},
            'children': const [],
          },
        ],
      },
    ]);

    testWidgets('a tap outside the box reaches the host, not the document', (tester) async {
      final calls = <String>[];
      var hostTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => hostTaps += 1)),
              Positioned(
                left: 300,
                top: 200,
                width: 200,
                height: 200,
                child: renderDocument(escaping, theme: RenderTheme.fallback(), data: const {}, onAction: (a, _) => calls.add(a.type)),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.tapAt(const Offset(700, 550));
      await tester.pump();
      expect(calls, isEmpty);
      expect(hostTaps, 1);
    });

    testWidgets('painting is clipped to the box', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              key: const ValueKey('host-box'),
              width: 200,
              height: 200,
              child: renderDocument(escaping, theme: RenderTheme.fallback(), data: const {}),
            ),
          ),
        ),
      );
      await tester.pump();
      final box = find.byKey(const ValueKey('host-box'));
      final clips = find.descendant(of: box, matching: find.byWidgetPredicate((w) => w is ClipRect || w is ClipRRect || w is ClipPath));
      expect(clips, findsWidgets);
      final first = tester.getRect(clips.first);
      expect(first, tester.getRect(box), reason: 'the outermost clip is the host box');
    });
  });

  group('theme font names are names, not paths', () {
    const names = [
      '../../../../etc/passwd',
      'packages/hotlayout_flutter/../../secret',
      'https://evil.example/font.ttf',
      'Roboto\u0000Bold',
      '\u202eevil',
    ];
    for (final name in names) {
      testWidgets('"${jsonEncode(name)}" draws without an exception and loads nothing', (tester) async {
        final net = installRecordingHttp(const {});
        final contract = (decodeObject(readThemeContract())['contract'] as Map).cast<String, Object?>();
        for (final theme in (contract['themes'] as Map).values) {
          final families = (theme as Map)['fontFamilies'] as Map?;
          if (families == null) continue;
          for (final role in families.values) {
            (role as Map)['primary'] = name;
            role['fallback'] = [name * 50];
          }
        }
        final load = ThemeLoad.fromJson(contract);
        await pumpDocument(tester, loadFixture('rewards-showcase-screens'), theme: load.contract.themeById(null));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(net.requests, isEmpty);
      });
    }
  });
}
