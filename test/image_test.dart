import 'package:hotlayout_flutter/src/render/icon_glyph.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/image_frame.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';

import 'support/fixtures.dart';

UiDocument _docWithImage(Map<String, Object?> source) => docWith([
  {
    'id': 'img-1',
    'type': 'Image',
    'props': {'source': source, 'aspectRatio': '16:9'},
  },
]);

void main() {
  group('Image', () {
    test('both kinds parse into their union branches', () {
      final asset = _docWithImage({'kind': 'asset', 'asset': 'banner'});
      final url = _docWithImage({'kind': 'url', 'url': 'https://cdn.example.com/a.png'});

      expect(
        (flatten(rootOf(asset)).whereType<ImageNode>().single.source as AssetImageSource).asset,
        AssetToken.banner,
      );
      expect(
        (flatten(rootOf(url)).whereType<ImageNode>().single.source as UrlImageSource).url,
        'https://cdn.example.com/a.png',
      );
    });

    testWidgets('kind=asset paints the bundled placeholder', (tester) async {
      await pumpDocument(tester, _docWithImage({'kind': 'asset', 'asset': 'placeholder'}));

      expect(tester.takeException(), isNull);
      expect(find.byWidgetPredicate((w) => w is IconGlyph && identical(w.icon, IconToken.parse('image'))), findsOneWidget);
      expect(find.byType(ImageFrame), findsOneWidget);
    });

    testWidgets('kind=url paints Image.network', (tester) async {
      await pumpDocument(tester, _docWithImage({'kind': 'url', 'url': 'https://cdn.example.com/a.png'}));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).url, 'https://cdn.example.com/a.png');
    });

    test('kind=binding parses into the third union branch', () {
      final bound = _docWithImage({
        'kind': 'binding',
        'path': 'item.image',
        'fallback': 'placeholder',
      });
      final source =
          flatten(rootOf(bound)).whereType<ImageNode>().single.source as BoundImageSource;

      expect(source.path, 'item.image');
      // The fallback is an asset TOKEN, not an address: there is no fallback address.
      expect(source.fallback, AssetToken.placeholder);
    });

    testWidgets('a bound address paints Image.network from data', (tester) async {
      await pumpDocument(
        tester,
        _docWithImage({'kind': 'binding', 'path': 'item.image', 'fallback': 'placeholder'}),
        data: const {'item.image': 'https://cdn.example.com/dji.png'},
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://cdn.example.com/dji.png');
    });

    testWidgets('a binding without data paints the fallback placeholder', (tester) async {
      await pumpDocument(
        tester,
        _docWithImage({'kind': 'binding', 'path': 'item.image', 'fallback': 'banner'}),
      );

      // The `banner` placeholder, not an empty space and not a broken `Image.network('')`.
      expect(find.byWidgetPredicate((w) => w is IconGlyph && identical(w.icon, IconToken.parse('megaphone'))), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('an empty string in the data is also "no data"', (tester) async {
      // `Image.network('')` is not an image but a network error, so an empty string
      // must give the placeholder, not a crossed-out square.
      await pumpDocument(
        tester,
        _docWithImage({'kind': 'binding', 'path': 'item.image', 'fallback': 'placeholder'}),
        data: const {'item.image': ''},
      );

      expect(find.byWidgetPredicate((w) => w is IconGlyph && identical(w.icon, IconToken.parse('image'))), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a binding also works in a row thumbnail - one source', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          listTileNode(
            'DJI OSMO Pocket 4',
            leading: {
              'kind': 'image',
              'source': {'kind': 'binding', 'path': 'item.image', 'fallback': 'placeholder'},
            },
          ),
        ]),
        data: const {'item.image': 'https://cdn.example.com/dji.png'},
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://cdn.example.com/dji.png');
    });

    test('the renderer knows EXACTLY the branches that are in the artifact', () {
      // Synchronisation guard. A fourth branch added by the builder would otherwise
      // silently degrade to a placeholder: `parse` returns `placeholder` for anything
      // unfamiliar, and on screen that would look like "the photo did not arrive", not like
      // "the app is behind the contract".
      final schema =
          jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync())
              as Map<String, Object?>;
      final branches = {
        for (final branch
            in ((schema[r'$defs']! as Map<String, Object?>)['ImageSource']!
                    as Map<String, Object?>)['oneOf']! as List<Object?>)
          (((branch! as Map<String, Object?>)['properties']! as Map<String, Object?>)['kind']!
                  as Map<String, Object?>)['const']
              as String,
      };

      expect(branches, {'asset', 'url', 'binding'});
    });

    test('fallback is required in the schema, but its absence does not break the node', () {
      // Here the reader is deliberately softer than the schema: the contract will not emit a document
      // without `fallback`, but anything may arrive from the network, and we have
      // only one "nothing" placeholder anyway - `placeholder`.
      final broken = _docWithImage({'kind': 'binding', 'path': 'item.image'});
      final source =
          flatten(rootOf(broken)).whereType<ImageNode>().single.source as BoundImageSource;

      expect(source.fallback, AssetToken.placeholder);
    });

    testWidgets('a broken URL shows a visible placeholder, not emptiness', (tester) async {
      await pumpDocument(tester, _docWithImage({'kind': 'url', 'url': 'https://cdn.example.com/404.png'}));
      // In tests the HTTP client always returns 400 - that is the "link does not work" scenario.
      await tester.pumpAndSettle();

      expect(find.text('Image unavailable'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is IconGlyph && identical(w.icon, IconToken.parse('image'))), findsOneWidget);
    });
  });
}
