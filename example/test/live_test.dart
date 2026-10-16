import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter_example/live.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _documentJson(String detailsTitle) => jsonEncode({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'live',
  'name': 'live',
  'initialScreenId': 'home',
  'screens': [
    _screen('home', [
      _text('home-title', 'Home'),
      {
        'id': 'to-details',
        'type': 'Button',
        'props': {
          'label': {'kind': 'literal', 'value': 'Open details'},
          'variant': 'primary',
          'action': {
            'type': 'navigate',
            'params': {'screenId': 'details'},
          },
        },
      },
    ]),
    _screen('details', [
      _text('details-title', detailsTitle),
      {
        'id': 'points',
        'type': 'Text',
        'props': {
          'content': {'kind': 'binding', 'path': 'user.points', 'fallback': '—'},
        },
      },
    ]),
  ],
});

Map<String, Object?> _screen(String id, List<Map<String, Object?>> children) => {
  'screenId': id,
  'name': id,
  'root': {'id': '$id-root', 'type': 'Screen', 'props': {'gap': 'none'}, 'children': children},
};

Map<String, Object?> _text(String id, String value) => {
  'id': id,
  'type': 'Text',
  'props': {
    'content': {'kind': 'literal', 'value': value},
  },
};

DocumentLoad _load(String json, DocumentLoadStatus status) => DocumentLoad(
  document: UiDocument.fromJsonString(json),
  status: status,
  receivedAt: DateTime.utc(2026),
  signature: '${json.length}:${json.hashCode}',
);

/// A source whose next answer the test sets.
final class _ScriptedSource implements DocumentSource {
  _ScriptedSource(this.next);

  DocumentLoad next;

  @override
  String get title => 'scripted';

  @override
  bool get isRefreshable => true;

  @override
  DocumentSource? get seed => null;

  @override
  Future<DocumentLoad> load() async => next;
}

void main() {
  testWidgets('a new publication is drawn mid-flow; a failed refresh keeps it; the stack stays', (tester) async {
    final source = _ScriptedSource(_load(_documentJson('Details v1'), DocumentLoadStatus.network));
    final publication = LivePublication(
      document: source,
      theme: ThemeLoad(contract: ThemeContract.fallback(), status: ThemeLoadStatus.ok),
      interval: null,
    );
    addTearDown(publication.dispose);
    await publication.start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LiveScreen(publication: publication, data: const {'user.points': 7})),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(find.text('Details v1'), findsOneWidget);

    var notified = 0;
    publication.addListener(() => notified += 1);

    // The same text again: nothing to tell.
    source.next = _load(_documentJson('Details v1'), DocumentLoadStatus.network);
    await publication.refresh();
    expect(notified, 0);

    // A new publication: drawn at once, on the same screen.
    source.next = _load(_documentJson('Details v2'), DocumentLoadStatus.network);
    await publication.refresh();
    await tester.pumpAndSettle();
    expect(notified, 1);
    expect(find.text('Details v2'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    // No network: the bundled copy does not replace the publication.
    source.next = _load(_documentJson('Bundled'), DocumentLoadStatus.unreachable);
    await publication.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Details v2'), findsOneWidget);
    expect(notified, 1);
  });

  test('EtagTransport turns 304 into the text it already has', () async {
    final seen = <String?>[];
    final client = MockClient((request) async {
      seen.add(request.headers['If-None-Match']);
      if (request.headers['If-None-Match'] == '"v1"') return http.Response('', 304);
      return http.Response('{"a":1}', 200, headers: {'etag': '"v1"'});
    });
    final transport = EtagTransport(client: client);
    final first = await transport.fetch(Uri.parse('https://example.com/published.json?_req=1'));
    final second = await transport.fetch(Uri.parse('https://example.com/published.json?_req=2'));
    expect(seen, [null, '"v1"']);
    expect(first, (statusCode: 200, body: '{"a":1}'));
    expect(second, (statusCode: 200, body: '{"a":1}'));
  });

  test('appActions: redeem by the record of the row, copy, a deeplink only with the app scheme', () async {
    final redeemed = <String>[];
    final opened = <String>[];
    final actions = appActions(
      redeem: (id) async => redeemed.add(id),
      askForNotifications: () async {},
      openUrl: opened.add,
      openAppLink: opened.add,
      say: (_) {},
    );
    ButtonAction action(String type, [Map<String, String> params = const {}]) =>
        ButtonAction.parse({'type': type, 'params': params}).handOver((_) => null);

    actions.handle(action('redeem'), 'row-button', {'reward.id': 'mug'});
    actions.handle(action('deeplink', {'url': 'myapp://wallet'}), 'n', null);
    actions.handle(action('deeplink', {'url': 'other://wallet'}), 'n', null);
    await Future<void>.delayed(Duration.zero);
    expect(redeemed, ['mug']);
    expect(opened, ['myapp://wallet']);
  });
}
