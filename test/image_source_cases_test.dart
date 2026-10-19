/// THE ADDRESS OF A PICTURE (`x-imageSource`): the shared table
/// `assets/contract/fixtures/image-source/image-source-cases.json`, row by row.
///
///  1. `defaultCases` -- which address is loaded WITHOUT a word from the host: by the rule and by a real screen
///     (an address that is refused makes no request, one that passes does);
///  2. `neverAnImageCases` -- `javascript:` and `vbscript:`, read as a URL parser reads them, are no picture even
///     when the host's own decision returns them: by the rule, by the policy and by a real screen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/render/picture_policy.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/svg_image.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'hardening/support.dart';
import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = jsonDecode(File('assets/contract/fixtures/image-source/image-source-cases.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

String _urlOf(_Row row) {
  final long = row['urlOfLength'] as _Row?;
  if (long == null) return row['url']! as String;
  final prefix = long['prefix']! as String;
  return prefix + (long['pad']! as String) * ((long['length']! as int) - prefix.length);
}

Map<String, Object?> _image(String url) => {
  'id': 'pic',
  'type': 'Image',
  'props': {
    'source': {'kind': 'url', 'url': url},
    'aspectRatio': '1:1',
    'fit': 'cover',
  },
};

/// Routes the framework's image client to a fake that records the requests; the hook is reset before the framework
/// checks that a test left no painting debug variable set.
void _netTest(String description, Future<void> Function(WidgetTester tester, RecordingHttp net) body) {
  testWidgets(description, (tester) async {
    final net = installRecordingHttp({});
    painting.debugNetworkImageHttpClientProvider = () => net.createHttpClient(null);
    painting.imageCache.clear();
    debugClearSvgStore();
    try {
      await body(tester, net);
    } finally {
      painting.debugNetworkImageHttpClientProvider = null;
    }
  });
}

void main() {
  test('the table has the promised rows', () {
    expect(_rows('defaultCases'), hasLength(78));
    expect(_rows('neverAnImageCases'), hasLength(16));
  });

  group('defaultCases -- the address the reader loads without the host', () {
    for (final row in _rows('defaultCases')) {
      final name = row['name']! as String;
      final problem = row['problem'] as String?;

      test('rule: $name', () {
        final url = _urlOf(row);
        expect(paramFormProblem(ActionParamForm.httpsUrl, url)?.wire, problem);
        expect(defaultImageUrlPolicy(url), problem == null ? url : isNull);
        expect(const PicturePolicy().approve(url), problem == null ? url : isNull);
      });

      // A real screen: a refused address makes no request at all.
      _netTest('screen: $name', (tester, net) async {
        final url = _urlOf(row);
        await pumpDocument(tester, docWith([_image(url)]));
        for (var i = 0; i < 4; i += 1) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        if (problem == null) {
          expect(net.requests, isNotEmpty, reason: 'an address that passes is requested');
        } else {
          expect(net.requests, isEmpty, reason: 'a refused address makes no request');
        }
      });
    }
  });

  group('neverAnImageCases -- a script is no picture, whatever the host says', () {
    for (final row in _rows('neverAnImageCases')) {
      final name = row['name']! as String;
      final url = row['url']! as String;
      final never = row['never']! as bool;

      test('rule: $name', () => expect(isNeverAnImage(url), never));

      test('policy: $name', () {
        final policy = PicturePolicy(resolveImageUrl: (address) => address);
        expect(policy.approve(url), never ? isNull : url, reason: 'the host\'s answer is final, but for a script');
      });

      if (never) {
        // The host's decision returns the script itself: the screen still draws the placeholder and asks nothing.
        _netTest('screen: $name', (tester, net) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: renderDocument(
                  docWith([_image('https://cdn.example.com/a.png')]),
                  theme: RenderTheme.fallback(),
                  data: const {},
                  resolveImageUrl: (_) => url,
                ),
              ),
            ),
          );
          for (var i = 0; i < 4; i += 1) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(net.requests, isEmpty);
          expect(find.text('Image unavailable'), findsOneWidget);
        });
      }
    }
  });
}
