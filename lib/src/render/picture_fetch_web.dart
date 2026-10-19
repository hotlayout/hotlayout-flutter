/// The picture loader on the web, where there is no `dart:io`.
///
/// The browser makes the request: it sends no cookies cross-origin, and follows redirects itself, so the host
/// policy cannot see a redirect target here (the browser's own rules, CORS included, apply). The body is read as
/// a stream and cut at the cap.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'picture_policy.dart';

/// Why a picture was not fetched. The text names the class of the failure and never carries the address.
final class PictureFetchException implements Exception {
  const PictureFetchException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Reads one picture from [url] (already approved by the policy). [cancel] stops the wait when nobody needs
/// the picture any more.
Future<Uint8List> fetchPictureBytes(
  Uri url, {
  required String? Function(String url) approve,
  required int maxBytes,
  Duration timeout = kPictureTimeout,
  PictureCancel? cancel,
}) {
  final client = http.Client();
  final result = Completer<Uint8List>();
  void fail(String reason) {
    if (!result.isCompleted) result.completeError(PictureFetchException(reason));
  }

  final timer = Timer(timeout, () => fail('timeout'));
  cancel?.onCancel(() => fail('cancelled'));
  _fetch(client, url, maxBytes).then(
    (bytes) {
      if (!result.isCompleted) result.complete(bytes);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  return result.future.whenComplete(() {
    timer.cancel();
    client.close();
  });
}

Future<Uint8List> _fetch(http.Client client, Uri url, int maxBytes) async {
  final response = await client.send(http.Request('GET', url));
  if (response.statusCode != 200) {
    unawaited(response.stream.listen(null).cancel());
    throw PictureFetchException('HTTP ${response.statusCode}');
  }
  final declared = response.contentLength;
  if (declared != null && declared > maxBytes) {
    unawaited(response.stream.listen(null).cancel());
    throw const PictureFetchException('body too large');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.stream) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) {
      throw const PictureFetchException('body too large');
    }
  }
  return bytes.takeBytes();
}
