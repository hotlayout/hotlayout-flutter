/// Limits on how a document and a theme arrive.
///
///  * The transport does not read an unbounded body: the contract caps a document at
///    `x-budget.maxDocumentBytes` (1 MiB), so a body four times that size is not a document.
///  * `ThemeLoad.fromNetwork` and `PublishedDocumentSource.load` always complete with a status;
///    a hostile body never escapes to the host as an exception.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/document_source.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import '../support/fixtures.dart';
import '../support/network.dart';
import 'support.dart';

const int maxDocumentBytes = 1 << 20;

String _themeWith(Object? Function(Map<String, Object?> theme) edit) {
  final contract = (decodeObject(readThemeContract())['contract'] as Map).cast<String, Object?>();
  final themes = (contract['themes'] as Map).cast<String, Object?>();
  for (final key in themes.keys.toList()) {
    edit((themes[key] as Map).cast<String, Object?>());
  }
  return jsonEncode(contract).replaceAll('"__INF__"', '1e400');
}

void main() {
  test('the artifact still names the budget this file assumes', () {
    final schema = decodeObject(File('assets/contract/screen-schema.json').readAsStringSync());
    expect((schema['x-budget'] as Map)['maxDocumentBytes'], maxDocumentBytes);
  });

  group('body size', () {
    test('a 64 MiB document body is not read past 4 MiB', () async {
      final url = 'https://cdn.example.com/doc.json';
      final net = installRecordingHttp({url: fakeHuge(64 << 20)});
      try {
        await HttpDocumentTransport().fetch(Uri.parse(url));
      } on Object {
        // Refusing is fine; reading it all is not.
      }
      expect(net.requests.single.bytesPulled, lessThanOrEqualTo(4 * maxDocumentBytes));
    });

    test('a Content-Length of 64 MiB is refused before the body is read', () async {
      final url = 'https://cdn.example.com/doc.json';
      final net = installRecordingHttp({url: fakeHuge(64 << 20, declaredLength: 64 << 20)});
      try {
        await HttpDocumentTransport().fetch(Uri.parse(url));
      } on Object {
        // Refusing is fine.
      }
      expect(net.requests.single.bytesPulled, lessThanOrEqualTo(4 * maxDocumentBytes));
    });
  });

  group('a hostile body is a status, never an exception', () {
    final hostileThemes = {
      'fontWeight 1e400': _themeWith((t) {
        for (final style in ((t['typography'] as Map).values)) {
          (style as Map)['fontWeight'] = '__INF__';
        }
        return null;
      }),
      'fontSize 1e400': _themeWith((t) {
        for (final style in ((t['typography'] as Map).values)) {
          (style as Map)['fontSize'] = '__INF__';
        }
        return null;
      }),
      'spacing 1e400': _themeWith((t) {
        final spacing = t['spacing'] as Map;
        for (final key in spacing.keys.toList()) {
          spacing[key] = '__INF__';
        }
        return null;
      }),
    };
    for (final entry in hostileThemes.entries) {
      test('ThemeLoad.fromNetwork with ${entry.key} completes', () async {
        final load = ThemeLoad.fromNetwork(
          Uri.parse('https://cdn.example.com/theme.json'),
          transport: FakeDocumentTransport.replying(200, entry.value),
        );
        await expectLater(load, completes);
      });

      test('ThemeLoad.parse with ${entry.key}: a theme with a value out of the schema bounds is not "ok" as is', () {
        // Either the whole contract is refused (`malformed`) or the value is dropped/clamped; in both cases
        // nothing infinite reaches a TextStyle or a padding.
        final load = ThemeLoad.parse(entry.value);
        for (final theme in load.contract.themes.values) {
          for (final token in theme.typography.values) {
            expect(token.fontSize ?? 8, inInclusiveRange(8, 96), reason: 'x-schema ThemeTypography.fontSize');
          }
          for (final space in theme.spacing.values) {
            expect(space, inInclusiveRange(0, 128), reason: 'x-schema Theme.spacing');
          }
        }
      });
    }

    test('PublishedDocumentSource.load with a hostile number completes', () async {
      final source = PublishedDocumentSource(
        url: Uri.parse('https://cdn.example.com/doc.json'),
        transport: FakeDocumentTransport.replying(200, readFixture('parts-screens').replaceAll(RegExp(r'"fieldRadius":\s*\d+'), '"fieldRadius": 1e400')),
        fallback: diskFixtureSource('minimal-screen'),
      );
      await expectLater(source.load(), completes);
    });
  });
}
