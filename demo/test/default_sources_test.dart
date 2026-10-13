import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_demo/main.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

import '../../test/support/network.dart';

/// Document sources the demo starts with when no parameters are given.
///
/// This used to be a group in the package's `document_source_test.dart` while the demo was part of it;
/// it checks the DEMO code (`defaultDocumentSources`), so it moved
/// together with it.
void main() {
  group('default sources', () {
    test('without a storage address no source reads the network', () {
      final sources = defaultDocumentSources(transport: FakeDocumentTransport.silent(), documentUrl: '');

      expect(sources, everyElement(isA<BundledDocumentSource>()));
      expect(sources, hasLength(kFixtures.length));
      expect((sources.first as BundledDocumentSource).assetPath, contains(kStartFixture));
    });

    test('first source is the network with a fallback to the bundled copy', () {
      const url = 'https://storage.example/o/documents%2Freward-catalog%2Fpublished.json?alt=media';
      final sources = defaultDocumentSources(transport: FakeDocumentTransport.silent(), documentUrl: url);
      final first = sources.first;

      expect(first, isA<PublishedDocumentSource>());
      final network = first as PublishedDocumentSource;
      expect(network.url.toString(), url);
      expect(network.url.queryParameters['alt'], 'media');
      expect(network.isRefreshable, isTrue);
      // While the network thinks there is something to draw - the same as was shown before.
      expect(network.seed, same(network.fallback));
      expect(network.fallback.assetPath, contains(kStartFixture));
      // The rest of the list is bundled fixtures, so the presentation stays possible
      // even without any network.
      expect(sources.skip(1), everyElement(isA<BundledDocumentSource>()));
      expect(sources.skip(1), hasLength(kFixtures.length));
    });
  });
}
