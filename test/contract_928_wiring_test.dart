/// The rules of the reader (schema 9.28.0) on real screens, beyond the shared tables: what a table row cannot say
/// because it has no tree around it -- a hidden list, a modal layer -- and the report of a refused picture.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/picture_policy.dart';

import 'hardening/support.dart';
import 'support/fixtures.dart';

Map<String, Object?> _list(String name, {Object? visibleIf, List<Map<String, Object?>>? inside}) => {
  'id': name,
  'type': 'Repeater',
  'props': {'source': 'rows', 'item': 'i$name', 'direction': 'column', 'gap': 'none'},
  'visibleIf': ?visibleIf,
  'children': [
    if (inside == null)
      textNode(name, id: '$name-text')
    else
      {
        'id': '$name-row',
        'type': 'Column',
        'props': {'gap': 'none'},
        'children': [textNode(name, id: '$name-text'), ...inside],
      },
  ],
};

final Map<String, Object?> _rows = {
  'rows': [for (var i = 0; i < 50; i += 1) {'n': i}],
};

int _count(String text) => find.text(text, skipOffstage: false).evaluate().length;

void main() {
  testWidgets('a list hidden by a condition costs what it would draw: the budget is not moved by what is shown', (tester) async {
    await pumpDocument(
      tester,
      docWith([
        _list('hidden', visibleIf: const {'path': 'flag.on', 'op': 'isNotEmpty'}, inside: [_list('inner')]),
        _list('after'),
      ]),
      data: _rows,
    );
    expect(_count('hidden'), 0, reason: 'hidden: not drawn');
    expect(_count('after'), 0, reason: 'the hidden list took the whole budget, so the list after it gets nothing');
  });

  testWidgets('the same screen with the list shown gives the same cut', (tester) async {
    await pumpDocument(
      tester,
      docWith([
        _list('shown', inside: [_list('inner')]),
        _list('after'),
      ]),
      data: _rows,
    );
    expect(_count('shown'), 50);
    expect(_count('inner'), 2500);
    expect(_count('after'), 0);
  });

  testWidgets('a modal layer has a budget of its own, besides the page under it', (tester) async {
    await pumpDocument(
      tester,
      docWithScreens([
        screenEntry('home', [
          buttonNode('Open', action: const {'type': 'navigate', 'params': {'screenId': 'sheet'}}, id: 'open'),
          _list('page', inside: [_list('pageInner')]),
        ]),
        screenEntry('sheet', [_list('layer')], presentation: 'modal'),
      ], initialScreenId: 'home'),
      data: _rows,
    );
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_count('layer'), 50, reason: 'the layer is a screen with its own budget');
  });

  group('the report of a refused picture', () {
    test('an address of the document is cut to 120 characters', () {
      final url = 'https://cdn.example.com/${'a' * 200}';
      expect(pictureReportAddress(url, fromData: false), url.substring(0, 120));
    });

    test('an address from data says its scheme and host at most', () {
      expect(pictureReportAddress('https://cdn.example.com/a.png?token=secret', fromData: true), 'https://cdn.example.com');
      expect(pictureReportAddress('https://user:pass@cdn.example.com/a.png', fromData: true), 'https://cdn.example.com');
      expect(pictureReportAddress('data:image/png;base64,AAAA', fromData: true), 'data:');
      expect(pictureReportAddress('not an address', fromData: true), '');
    });

    test('a control character never reaches a log line', () {
      expect(pictureReportAddress('https://cdn.example.com/a\n\u0000b', fromData: false), 'https://cdn.example.com/a??b');
    });

    testWidgets('a refused address is reported once, and a refused address from data without its path', (tester) async {
      final lines = await captureDebugPrint(() async {
        await pumpDocument(
          tester,
          docWith([
            {
              'id': 'pic',
              'type': 'Image',
              'props': {
                'source': {'kind': 'binding', 'path': 'item.image', 'fallback': 'placeholder'},
                'aspectRatio': '1:1',
                'fit': 'cover',
              },
            },
          ]),
          data: const {'item.image': 'https://127.0.0.1/private/token-123.png'},
        );
      });
      final reports = lines.where((line) => line.contains('address refused')).toList();
      expect(reports, isNotEmpty);
      expect(reports.join(), contains('https://127.0.0.1'));
      expect(reports.join(), isNot(contains('token-123')));
    });
  });
}
