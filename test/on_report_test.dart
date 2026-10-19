/// `onReport`: what the reader ignored, replaced or refused reaches the host on a real widget, once per
/// cause, and a rebuild does not repeat it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

import 'support/fixtures.dart';

Map<String, Object?> _list(String name, {List<Map<String, Object?>>? inside}) => {
  'id': name,
  'type': 'Repeater',
  'props': {'source': 'rows', 'item': 'i$name', 'direction': 'column', 'gap': 'none'},
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
  'rows': [
    for (var i = 0; i < 50; i += 1) {'n': i},
  ],
};

/// Pumps [doc] and then rebuilds the host [rebuilds] times with a new data map. Returns what `onReport` heard.
Future<List<HotlayoutReport>> _hear(
  WidgetTester tester,
  UiDocument doc, {
  RenderTheme? theme,
  Map<String, Object?> data = const {},
  String? entry,
  int rebuilds = 2,
  bool listen = true,
}) async {
  final heard = <HotlayoutReport>[];
  final resolved = theme ?? ThemeContract.fallback().defaultTheme;
  var tick = 0;
  late StateSetter rebuild;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return renderDocument(
              doc,
              theme: resolved,
              data: {...data, 'tick': tick},
              entry: entry,
              onReport: listen ? heard.add : null,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < rebuilds; i += 1) {
    rebuild(() => tick += 1);
    await tester.pump();
  }
  return heard;
}

Map<String, Object?> _screenWith(List<Map<String, Object?>> children) => {
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': 'inline',
  'name': 'inline',
  'initialScreenId': 'inline',
  'screens': [screenEntry('inline', children)],
};

void main() {
  testWidgets('an unknown widget is reported once as ignored-input, and a rebuild does not repeat it', (tester) async {
    final doc = docWith([
      {'id': 'odd', 'type': 'FutureWidget', 'props': <String, Object?>{}},
      textNode('hello'),
    ]);
    final heard = await _hear(tester, doc, rebuilds: 3);
    final mine = heard.whereType<IgnoredInputReport>().where((r) => r.where == 'node "odd"').toList();
    expect(mine, hasLength(1));
    expect(mine.single.kind, 'ignored-input');
    expect(mine.single.reason, contains('FutureWidget'));
    expect(heard.toSet(), hasLength(heard.length), reason: 'no report twice');
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('the list budget is reported once per screen show, not on every build', (tester) async {
    final doc = docWith([
      _list('shown', inside: [_list('inner')]),
      _list('after'),
    ]);
    final heard = await _hear(tester, doc, data: _rows, rebuilds: 4);
    final budget = heard.whereType<IgnoredInputReport>().where((r) => r.reason.contains('list budget')).toList();
    expect(budget, hasLength(1));
    expect(budget.single.where, 'screen "inline"');
    expect(budget.single.message, contains('were not drawn'));
  });

  testWidgets('a refused picture address is reported with the address as the report may say it', (tester) async {
    final doc = docWith([
      {
        'id': 'pic',
        'type': 'Image',
        'props': {
          'source': {'kind': 'url', 'url': 'http://insecure.example/a.png'},
          'aspectRatio': '1:1',
          'fit': 'cover',
        },
      },
    ]);
    final heard = await _hear(tester, doc);
    final refused = heard.whereType<IgnoredInputReport>().where((r) => r.where == 'picture').toList();
    expect(refused, hasLength(1));
    expect(refused.single.reason, contains('insecure.example'));
  });

  testWidgets('an unknown entry point is reported as unknown-entry', (tester) async {
    final heard = await _hear(tester, docWith([textNode('x')]), entry: 'nowhere');
    expect(heard.whereType<UnknownEntryReport>().map((r) => r.entry), ['nowhere']);
    expect(heard.whereType<UnknownEntryReport>().single.kind, 'unknown-entry');
  });

  testWidgets('a document of a major the reader cannot read: incompatible-document, older and newer', (tester) async {
    final older = await _hear(tester, docWith([textNode('x')], schemaVersion: '1.0.0'));
    final olderReport = older.whereType<IncompatibleDocumentReport>().single;
    expect(olderReport.documentIsOlder, isTrue);
    expect(olderReport.documentVersion, '1.0.0');
    expect(olderReport.readerVersion, UiDocument.supportedSchemaVersion);

    final newer = await _hear(tester, docWith([textNode('x')], schemaVersion: '99.0.0'));
    expect(newer.whereType<IncompatibleDocumentReport>().single.documentIsOlder, isFalse);
  });

  testWidgets('a document of a newer minor is drawn and reported as newer-minor-document', (tester) async {
    final heard = await _hear(tester, docWith([textNode('hello')], schemaVersion: '9.99.0'));
    expect(heard.whereType<NewerMinorDocumentReport>().single.documentVersion, '9.99.0');
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('a screen without a root is reported while the document is parsed', (tester) async {
    final json = _screenWith([textNode('x')]);
    (json['screens']! as List).add({'screenId': 'broken'});
    final heard = await _hear(tester, UiDocument.fromJson(json));
    expect(heard.whereType<IgnoredInputReport>().where((r) => r.where == 'screen "broken"'), hasLength(1));
  });

  testWidgets('theme values outside the schema are reported as one invalid-theme-values', (tester) async {
    final contract = ThemeLoad.fromJson({
      'themeContractVersion': kSupportedThemeContractVersion,
      'defaultThemeId': 'light',
      'themes': {
        'light': {
          'id': 'light',
          'brightness': 'light',
          'color': {'brand': 'not-a-colour', 'ink': 12},
        },
      },
    }).contract;
    final heard = await _hear(tester, docWith([textNode('x')]), theme: contract.defaultTheme);
    final invalid = heard.whereType<InvalidThemeValuesReport>().toList();
    expect(invalid, hasLength(1));
    expect(invalid.single.paths, containsAll(['color.brand (malformed)', 'color.ink (malformed)']));
  });

  testWidgets('an unreadable theme file: theme-fallback; an unknown theme id: unknown-theme-id', (tester) async {
    final load = ThemeLoad.parse('this is not JSON');
    final fallback = await _hear(tester, docWith([textNode('x')]), theme: load.contract.defaultTheme);
    expect(fallback.whereType<ThemeFallbackReport>().single.reason, contains('not JSON'));

    final unknown = ThemeContract.fallback().themeById('does-not-exist');
    final heard = await _hear(tester, docWith([textNode('x')]), theme: unknown);
    final report = heard.whereType<UnknownThemeIdReport>().single;
    expect(report.themeId, 'does-not-exist');
  });

  testWidgets('without onReport nothing breaks and nothing is delivered', (tester) async {
    final heard = await _hear(
      tester,
      docWith([
        {'id': 'odd', 'type': 'FutureWidget', 'props': <String, Object?>{}},
      ]),
      listen: false,
    );
    expect(heard, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renderScreen takes onReport too: theme findings and what drawing finds', (tester) async {
    final doc = docWith([
      {
        'id': 'pic',
        'type': 'Image',
        'props': {
          'source': {'kind': 'url', 'url': 'http://insecure.example/a.png'},
          'aspectRatio': '1:1',
          'fit': 'cover',
        },
      },
    ]);
    final theme = ThemeContract.fallback().themeById('does-not-exist');
    final heard = <HotlayoutReport>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: renderScreen(doc.screens.first, theme: theme, data: const {}, onReport: heard.add),
        ),
      ),
    );
    await tester.pump();
    expect(heard.whereType<UnknownThemeIdReport>(), hasLength(1));
    expect(heard.whereType<IgnoredInputReport>().where((r) => r.where == 'picture'), hasLength(1));
  });
}
