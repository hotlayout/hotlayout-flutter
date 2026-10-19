/// Limits on loading pictures. A picture address comes from the document or from the data, both
/// untrusted, and the request is made by the device of the user — inside the network of the
/// user, with the reach of the app.
///
///  * Default policy: only `https` with a host name whose last label is letters — the same host
///    form as the contract's `openUrl` (`x-actions.forms.httpsUrl`). No IP literal in any base, no
///    single-word name (`localhost`, `intranet`), no user info, no plain `http`.
///  * The decode is bounded: a 20 kB PNG that says 30000 × 30000 must not become 3.6 GB of pixels.
///  * The body is bounded: a server that never stops sending must not fill the memory.
///  * The request carries nothing of the host (cookies, authorization).
///  * A redirect is not followed blindly: its target would skip the host policy.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/svg_image.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import '../support/fixtures.dart';
import 'support.dart';

Map<String, Object?> _image(Object source, {String id = 'pic'}) => {
  'id': id,
  'type': 'Image',
  'props': {'source': source, 'aspectRatio': '1:1', 'fit': 'cover'},
};

Map<String, Object?> _url(String url) => {'kind': 'url', 'url': url};

const Map<String, Object?> _bound = {'kind': 'binding', 'path': 'item.image', 'fallback': 'placeholder'};

/// Addresses the default policy must refuse, with the reason.
const Map<String, String> refused = {
  'http://cdn.example.com/a.png': 'plain http',
  'https://127.0.0.1/a.png': 'IPv4 loopback',
  'https://2130706433/a.png': 'IPv4 as one decimal number (127.0.0.1)',
  'https://0x7f000001/a.png': 'IPv4 in hexadecimal',
  'https://0177.0.0.1/a.png': 'IPv4 in octal',
  'https://127.1/a.png': 'IPv4 short form',
  'https://10.0.0.5/a.png': 'private network',
  'https://192.168.1.1/a.png': 'private network',
  'https://169.254.169.254/latest/meta-data/': 'cloud metadata address',
  'https://[::1]/a.png': 'IPv6 loopback',
  'https://[fd00::1]/a.png': 'IPv6 unique local',
  'https://localhost/a.png': 'single-word name',
  'https://intranet/a.png': 'single-word name',
  'https://user:secret@cdn.example.com/a.png': 'user info',
  'https://cdn.example.com@127.0.0.1/a.png': 'user info that hides the real host',
  'https://127.0.0.1/a.svg': 'IPv4 loopback, SVG branch',
  'https://localhost/a.svg': 'single-word name, SVG branch',
  'file:///etc/hosts': 'file scheme',
};

const String allowed = 'https://cdn.example.com/a.png';
const String allowedSvg = 'https://cdn.example.com/a.svg';

/// A 1 × 1 PNG.
final List<int> onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

RecordingHttp _network(WidgetTester tester, Map<String, FakeBody> replies) {
  final net = installRecordingHttp(replies);
  // The framework keeps ONE `HttpClient` for every `NetworkImage` of the isolate; route it to the fake.
  painting.debugNetworkImageHttpClientProvider = () => net.createHttpClient(null);
  return net;
}

/// A widget test that may route the framework's image client to a fake; the debug hook is reset
/// before the framework checks that the test left no painting debug variable set.
void netTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      painting.debugNetworkImageHttpClientProvider = null;
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    painting.imageCache.clear();
    painting.imageCache.clearLiveImages();
    debugClearSvgStore();
  });

  group('default policy: the address from the DOCUMENT', () {
    netTest('control: an https address with a letter TLD is requested', (tester) async {
      final net = _network(tester, {allowed: fakeBytes(onePixelPng)});
      await pumpDocument(tester, docWith([_image(_url(allowed))]));
      await _settle(tester);
      expect(net.requests.map((r) => '${r.url}'), contains(allowed));
    });

    for (final entry in refused.entries) {
      netTest('${entry.value}: ${entry.key} is never requested', (tester) async {
        final net = _network(tester, const {});
        await pumpDocument(tester, docWith([_image(_url(entry.key))]));
        await _settle(tester);
        expect(net.requests.map((r) => '${r.url}'), isEmpty);
      });
    }
  });

  group('default policy: the address from the DATA', () {
    for (final entry in refused.entries) {
      netTest('${entry.value}: ${entry.key} is never requested', (tester) async {
        final net = _network(tester, const {});
        await pumpDocument(tester, docWith([_image(_bound)]), data: {'item.image': entry.key});
        await _settle(tester);
        expect(net.requests.map((r) => '${r.url}'), isEmpty);
      });
    }
  });

  group('the decode is bounded', () {
    netTest('a network raster picture is decoded at a bounded size (ResizeImage)', (tester) async {
      _network(tester, {allowed: fakeBytes(onePixelPng)});
      await pumpDocument(tester, docWith([_image(_url(allowed))]));
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.image, isA<ResizeImage>(), reason: 'Image.network without cacheWidth/cacheHeight decodes the full header size');
    });

    netTest('a data: raster picture is decoded at a bounded size (ResizeImage)', (tester) async {
      await pumpDocument(
        tester,
        docWith([_image(_bound)]),
        data: {'item.image': 'data:image/png;base64,${base64Encode(onePixelPng)}'},
      );
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.image, isA<ResizeImage>(), reason: 'Image.memory without cacheWidth/cacheHeight decodes the full header size');
    });
  });

  group('the body is bounded', () {
    const huge = 64 << 20;
    const cap = 16 << 20;

    netTest('raster: a 64 MiB body without Content-Length is not read past 16 MiB', (tester) async {
      final net = _network(tester, {allowed: fakeHuge(huge)});
      await pumpDocument(tester, docWith([_image(_url(allowed))]));
      await _settle(tester);
      expect(net.requests, isNotEmpty);
      expect(net.requests.first.bytesPulled, lessThanOrEqualTo(cap));
    });

    netTest('raster: a Content-Length of 64 MiB is refused before the body is read', (tester) async {
      final net = _network(tester, {allowed: fakeHuge(huge, declaredLength: huge)});
      await pumpDocument(tester, docWith([_image(_url(allowed))]));
      await _settle(tester);
      expect(net.requests, isNotEmpty);
      expect(net.requests.first.bytesPulled, lessThanOrEqualTo(cap));
    });

    netTest('SVG: a 64 MiB body without Content-Length is not read past 16 MiB', (tester) async {
      final net = _network(tester, {allowedSvg: fakeHuge(huge)});
      await pumpDocument(tester, docWith([_image(_url(allowedSvg))]));
      await _settle(tester);
      expect(net.requests, isNotEmpty);
      expect(net.requests.first.bytesPulled, lessThanOrEqualTo(cap));
    });
  });

  group('the request carries nothing of the host', () {
    netTest('raster: no cookie, no authorization header', (tester) async {
      final net = _network(tester, {allowed: fakeBytes(onePixelPng)});
      await pumpDocument(tester, docWith([_image(_url(allowed))]));
      await _settle(tester);
      final seen = net.requests.single;
      expect(seen.cookies, isEmpty);
      expect(seen.headers.keys, isNot(anyOf(contains('cookie'), contains('authorization'))));
    });

    netTest('SVG: no cookie, no authorization header', (tester) async {
      final net = _network(tester, {allowedSvg: fakeBytes(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>'))});
      await pumpDocument(tester, docWith([_image(_url(allowedSvg))]));
      await _settle(tester);
      final seen = net.requests.single;
      expect(seen.cookies, isEmpty);
      expect(seen.headers.keys, isNot(anyOf(contains('cookie'), contains('authorization'))));
    });
  });

  group('redirects are not followed past the policy', () {
    netTest('raster: the client does not follow redirects by itself', (tester) async {
      final net = _network(tester, {allowed: fakeBytes(onePixelPng)});
      await pumpDocument(tester, docWith([_image(_url(allowed))]));
      await _settle(tester);
      expect(net.requests.single.followRedirects, isFalse,
          reason: 'a 302 to https://169.254.169.254/ would be fetched without the host policy seeing it');
    });

    netTest('SVG: the client does not follow redirects by itself', (tester) async {
      final net = _network(tester, {allowedSvg: fakeBytes(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>'))});
      await pumpDocument(tester, docWith([_image(_url(allowedSvg))]));
      await _settle(tester);
      expect(net.requests.single.followRedirects, isFalse,
          reason: 'a 302 to https://169.254.169.254/ would be fetched without the host policy seeing it');
    });
  });

  group('the host can override the policy', () {
    netTest('an internal CDN the host allows is requested; an address the host refuses is not', (tester) async {
      const internal = 'https://10.0.0.5/a.png';
      final net = _network(tester, {internal: fakeBytes(onePixelPng), allowed: fakeBytes(onePixelPng)});
      final doc = docWith([_image(_url(internal), id: 'a'), _image(_url(allowed), id: 'b')]);
      late Widget screen;
      try {
        // Called dynamically so that the file compiles while the parameter does not exist.
        screen = Function.apply(renderDocument, [doc], {
          #theme: RenderTheme.fallback(),
          #data: const <String, Object?>{},
          #resolveImageUrl: (String url) => url.startsWith('https://10.0.0.5/') ? url : null,
        }) as Widget;
      } on NoSuchMethodError {
        fail('renderDocument has no image policy parameter: the host cannot narrow or widen what is fetched');
      }
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
      await _settle(tester);
      expect(net.requests.map((r) => '${r.url}'), [internal]);
    });
  });
}
