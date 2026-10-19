/// Limit: no value of the host's data reaches the log.
///
/// The data is the user's (names, balances, links with tokens). `debugPrint` is NOT removed from
/// release builds — it writes to the device log, which other tools and crash reporters collect — so
/// a line that carries a data value leaks it. Document values (ids, token names) may be named; data
/// values may not.
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/demo_data.dart';
import '../support/fixtures.dart';
import '../support/http.dart';
import 'support.dart';

const String marker = 'PRIVATE-7f3a';

/// [tree] with every string replaced by a marked one; shapes that matter for drawing (a URL
/// for a picture) keep their form so that the code path that logs a failure is reached.
Object? _mark(Object? tree, [String? key]) {
  if (tree is Map) return {for (final e in tree.entries) e.key: _mark(e.value, e.key as String)};
  if (tree is List) return [for (final item in tree) _mark(item, key)];
  if (tree is String) {
    if (tree.startsWith('data:') || tree.startsWith('https://')) return 'https://cdn.example.com/$marker/x.svg';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(tree)) return tree;
    return '$marker-$tree';
  }
  return tree;
}

void main() {
  testWidgets('a failed SVG whose address came from the data does not log the address (this line is not debug-only)', (tester) async {
    installFakeHttp(const {});
    final lines = await captureDebugPrint(() async {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'pic',
            'type': 'Image',
            'props': {'source': {'kind': 'binding', 'path': 'user.avatar', 'fallback': 'placeholder'}, 'aspectRatio': '1:1', 'fit': 'cover'},
          },
        ]),
        data: {'user.avatar': 'https://cdn.example.com/u/42/avatar.svg?token=$marker'},
      );
      for (var i = 0; i < 10; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    expect(lines.where((l) => l.contains(marker)), isEmpty);
  });

  group('sweep: every fixture with marked data, debug log included', () {
  for (final id in fixtureIds) {
    testWidgets('$id: no data value in the log', (tester) async {
      installFakeHttp(const {});
      final data = (_mark(sampleScreenData) as Map).cast<String, Object?>();
      final lines = await captureDebugPrint(() async {
        final doc = loadFixture(id);
        for (final screen in doc.screens) {
          await pumpDocument(tester, doc, data: data, entry: screen.screenId, theme: fixtureTheme(id));
          for (var i = 0; i < 10; i += 1) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
      });
      tester.takeException();
      expect(lines.where((l) => l.contains(marker)), isEmpty);
    });
  }
  });
}
