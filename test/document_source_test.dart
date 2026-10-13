import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/document_source.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/node.dart';

import 'support/fixtures.dart';
import 'support/network.dart';

/// Document source: the network with a fallback to the embedded copy.
///
/// The main requirement for this piece is not "fast" or "pretty" but that **the screen
/// must never break**. So what is checked here is less the success than each kind of
/// failure separately: all of them must end with a document on screen and
/// an honest status saying why.
void main() {
  // The embedded copy is read from DISK (`fixtureSource`), not from `rootBundle`:
  // the package declares no assets, so its test bundle has no fixtures.
  TestWidgetsFlutterBinding.ensureInitialized();

  final url = Uri.parse('https://example.test/o/documents%2Freward-catalog%2Fpublished.json?alt=media');

  /// The embedded copy is the same fixture the app uses.
  BundledDocumentSource fallback() =>
      diskFixtureSource('reward-catalog-screens', title: 'Вбудована');

  PublishedDocumentSource published(
    DocumentTransport transport, {
    Duration timeout = const Duration(seconds: 5),
  }) => PublishedDocumentSource(
    url: url,
    fallback: fallback(),
    transport: transport,
    timeout: timeout,
  );

  /// Text of the first `Text` in the document - the shortest way to ask "which
  /// document is on screen".
  String firstText(DocumentLoad load) {
    final node = flattenDocument(load.document).whereType<TextNode>().first;
    return node.content.resolve(const ScreenData({})).toString();
  }

  group('embedded source', () {
    test('a bundle fixture is read and calls itself embedded', () async {
      final load = await fallback().load();

      expect(load.status, DocumentLoadStatus.bundled);
      expect(load.isFallback, isFalse, reason: 'the asset was asked for and the asset was given; it is not a substitution');
      expect(load.document.documentId, isNotEmpty);
    });

    test('the embedded source is not refreshed: between reads it stays the same', () {
      expect(fallback().isRefreshable, isFalse);
      expect(fallback().seed, isNull);
    });
  });

  group('the network returned a document', () {
    test('the network document is shown, not the embedded one', () async {
      final source = published(
        FakeDocumentTransport.replying(200, publishedDocumentJson(text: 'Свіже з конструктора')),
      );

      final load = await source.load();

      expect(load.status, DocumentLoadStatus.network);
      expect(load.isFallback, isFalse);
      expect(firstText(load), 'Свіже з конструктора');
    });

    test('a newer MINOR is read, not rolled back', () async {
      // Compatibility rule: the major must match, and the reader may read an
      // older minor tolerantly. Falling back here would mean the app ignores
      // publications exactly when the builder has released a minor - that is,
      // regularly.
      final source = published(
        FakeDocumentTransport.replying(
          200,
          publishedDocumentJson(text: 'З майбутнього мінора', schemaVersion: futureMinorVersion),
        ),
      );

      final load = await source.load();

      expect(load.status, DocumentLoadStatus.network);
      expect(firstText(load), 'З майбутнього мінора');
    });

    test('every read goes to a NEW address - the cache has nothing to answer with', () async {
      final transport = FakeDocumentTransport.replying(200, publishedDocumentJson());
      final source = published(transport);

      await source.load();
      await source.load();

      expect(transport.requests, hasLength(2));
      expect(
        transport.requests[0],
        isNot(transport.requests[1]),
        reason: 'an identical address would let the cache serve yesterday\'s publication',
      );
      for (final request in transport.requests) {
        expect(request.path, url.path, reason: 'cache busting must not change the document itself');
        expect(request.queryParameters['alt'], 'media');
        expect(request.queryParameters['_req'], isNotNull);
      }
    });
  });

  group('the network gave no document - the show goes on with the embedded copy', () {
    /// Shared check for every kind of failure: the screen shows the embedded copy,
    /// the status says why, and this is visible as DATA, not only in the console.
    Future<void> expectFallback(
      PublishedDocumentSource source,
      DocumentLoadStatus status, {
      required String because,
    }) async {
      final bundled = await fallback().load();
      final load = await source.load();

      expect(load.status, status);
      expect(load.isFallback, isTrue);
      expect(load.detail, isNotNull, reason: 'a silent fallback is what must not exist');
      expect(load.detail, contains(because));
      expect(
        load.document.documentId,
        bundled.document.documentId,
        reason: 'the embedded copy must remain on screen',
      );
      expect(load.signature, bundled.signature);
    }

    test('404: the manager has not pressed "Publish" yet', () async {
      await expectFallback(
        published(FakeDocumentTransport.replying(404, '{"error":{"code":404}}')),
        DocumentLoadStatus.notPublished,
        because: '404',
      );
    });

    test('another response code is also a fallback, but with a different reason', () async {
      await expectFallback(
        published(FakeDocumentTransport.replying(503, 'Service Unavailable')),
        DocumentLoadStatus.serverError,
        because: '503',
      );
    });

    test('the network is silent: the timeout fires, not an endless wait', () async {
      final source = published(
        FakeDocumentTransport.silent(),
        timeout: const Duration(milliseconds: 20),
      );

      final started = DateTime.now();
      await expectFallback(source, DocumentLoadStatus.timedOut, because: 'no answer within');
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 2)),
        reason: 'the fallback must happen by timeout, not "eventually"',
      );
    });

    test('the request did not happen at all (no network)', () async {
      await expectFallback(
        published(FakeDocumentTransport.failing(const SocketException('немає маршруту'))),
        DocumentLoadStatus.unreachable,
        because: 'the request did not happen',
      );
    });

    test('the response is not JSON', () async {
      await expectFallback(
        published(FakeDocumentTransport.replying(200, '<html>сторінка входу</html>')),
        DocumentLoadStatus.malformed,
        because: 'is not a document',
      );
    });

    test('JSON is present but there is no document: no usable screen', () async {
      await expectFallback(
        published(FakeDocumentTransport.replying(200, '{"schemaVersion":"7.0.0","screens":[]}')),
        DocumentLoadStatus.malformed,
        because: 'is not a document',
      );
    });

    // One status for both sides (the fallback is the same), while the reason in `detail`
    // differs: it tells the developer WHAT to do, and those are different actions.
    test('an OLDER schema major: fallback, and the reason says "republish"', () async {
      await expectFallback(
        published(
          FakeDocumentTransport.replying(
            200,
            publishedDocumentJson(text: 'З іншого мажора', schemaVersion: previousMajorVersion),
          ),
        ),
        DocumentLoadStatus.incompatible,
        because: 'older major',
      );
      final load = await published(
        FakeDocumentTransport.replying(200, publishedDocumentJson(schemaVersion: previousMajorVersion)),
      ).load();
      expect(load.detail, contains('republish the document from the builder'));
      expect(load.detail, isNot(contains('update the hotlayout_flutter package')));
    });

    test('a NEWER schema major: fallback, and the reason says "update the package"', () async {
      await expectFallback(
        published(
          FakeDocumentTransport.replying(
            200,
            publishedDocumentJson(text: 'З іншого мажора', schemaVersion: foreignMajorVersion),
          ),
        ),
        DocumentLoadStatus.incompatible,
        because: 'update the hotlayout_flutter package',
      );
    });
  });

  group('repeated read', () {
    test('"refresh" after publishing shows the NEW document', () async {
      final transport = FakeDocumentTransport.replying(200, publishedDocumentJson(text: 'До'));
      final source = published(transport);

      final before = await source.load();
      expect(firstText(before), 'До');

      // The manager pressed "Publish" - the storage already holds a different file.
      transport.respond = (_) async => (statusCode: 200, body: publishedDocumentJson(text: 'Після'));
      final after = await source.load();

      expect(firstText(after), 'Після');
      expect(after.status, DocumentLoadStatus.network);
      expect(
        after.signature,
        isNot(before.signature),
        reason: 'a different document means a different fingerprint, otherwise the host will not repaint the screen',
      );
    });

    test('an unchanged document has the same fingerprint', () async {
      // The silent refresh on returning from the background relies on exactly this: if
      // nothing changed, the host must not reset the screen stack under
      // the manager.
      final source = published(FakeDocumentTransport.replying(200, publishedDocumentJson()));

      final first = await source.load();
      final second = await source.load();

      expect(second.signature, first.signature);
    });
  });
}
