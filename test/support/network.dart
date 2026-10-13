import 'dart:async';
import 'dart:convert';

import 'package:hotlayout_flutter/src/data/document_source.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'fixtures.dart';

/// A network faked through the port.
///
/// A real "bad Wi-Fi" cannot be reproduced in a test, yet its consequences must be
/// checked: 404 before the first publication, a timeout, garbage instead of a document.
/// That is why [DocumentTransport] exists — this is its fake.
final class FakeDocumentTransport implements DocumentTransport {
  FakeDocumentTransport(this.respond);

  /// A ready reply with status code and body.
  factory FakeDocumentTransport.replying(int statusCode, String body) =>
      FakeDocumentTransport((_) async => (statusCode: statusCode, body: body));

  /// The request fails outright: no connectivity, DNS, TLS.
  factory FakeDocumentTransport.failing(Object error) =>
      FakeDocumentTransport((_) async => throw error);

  /// A network that never answers — what a timeout is cured with.
  factory FakeDocumentTransport.silent() =>
      FakeDocumentTransport((_) => Completer<DocumentResponse>().future);

  Future<DocumentResponse> Function(Uri url) respond;

  /// All addresses requested. Needed to check cache bypass: two reads must
  /// not go to the same address.
  final List<Uri> requests = [];

  @override
  Future<DocumentResponse> fetch(Uri url) {
    requests.add(url);
    return respond(url);
  }
}

/// A document as it lies in storage — a JSON string.
///
/// Its own, not an asset fixture: a network test must see the DIFFERENCE between what
/// came over HTTP and what lies in the bundle. Identical text would hide exactly the
/// mistake we are looking for.
String publishedDocumentJson({
  String text = 'З мережі',
  String documentId = 'reward-catalog',
  String name = 'Опублікований',
  String schemaVersion = UiDocument.supportedSchemaVersion,
}) => jsonEncode({
  'schemaVersion': schemaVersion,
  'documentId': documentId,
  'name': name,
  'initialScreenId': 'published',
  'screens': [
    screenEntry('published', [textNode(text)]),
  ],
});
