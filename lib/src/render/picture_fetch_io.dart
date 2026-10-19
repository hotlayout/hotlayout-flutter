/// The picture loader on platforms with `dart:io`.
///
/// One dedicated `HttpClient` per picture, built here, with nothing of the host in it: no cookies, no
/// credentials, no headers. Redirects are followed by hand so that every hop passes the host's address policy
/// again, with at most [kMaxPictureRedirects] hops. The body is read as a stream and cut at the cap.
///
/// A global `HttpOverrides` of the host still applies to the client this creates (`HttpClient()` honours it):
/// a proxy or certificate pinning the host installs is meant to cover pictures too.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'picture_policy.dart';

/// Why a picture was not fetched. The text names the class of the failure and never carries the address.
final class PictureFetchException implements Exception {
  const PictureFetchException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Reads one picture from [url] (already approved by the policy). [approve] re-checks every redirect target.
/// [cancel] stops the request when nobody waits for it any more.
Future<Uint8List> fetchPictureBytes(
  Uri url, {
  required String? Function(String url) approve,
  required int maxBytes,
  Duration timeout = kPictureTimeout,
  PictureCancel? cancel,
}) {
  final client = HttpClient()..connectionTimeout = timeout;
  final result = Completer<Uint8List>();
  void fail(String reason) {
    if (!result.isCompleted) result.completeError(PictureFetchException(reason));
  }

  // The timeout covers the whole request, redirects included; the client is closed by force when it fires.
  final timer = Timer(timeout, () => fail('timeout'));
  cancel?.onCancel(() => fail('cancelled'));
  _fetch(client, url, approve, maxBytes).then(
    (bytes) {
      if (!result.isCompleted) result.complete(bytes);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  return result.future.whenComplete(() {
    timer.cancel();
    client.close(force: true);
  });
}

const Set<int> _redirects = {301, 302, 303, 307, 308};

Future<Uint8List> _fetch(
  HttpClient client,
  Uri first,
  String? Function(String) approve,
  int maxBytes,
) async {
  var url = first;
  for (var hop = 0; hop <= kMaxPictureRedirects; hop += 1) {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    final response = await request.close();
    final status = response.statusCode;
    if (_redirects.contains(status)) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      unawaited(response.listen(null).cancel());
      if (location == null || hop == kMaxPictureRedirects) {
        throw const PictureFetchException('redirect refused');
      }
      final Uri target;
      try {
        target = url.resolve(location);
      } on FormatException {
        throw const PictureFetchException('redirect refused');
      }
      final approved = approve(target.toString());
      if (approved == null) {
        throw const PictureFetchException('redirect refused');
      }
      url = Uri.parse(approved);
      continue;
    }
    if (status != 200) {
      unawaited(response.listen(null).cancel());
      throw PictureFetchException('HTTP $status');
    }
    if (response.contentLength > maxBytes) {
      unawaited(response.listen(null).cancel());
      throw const PictureFetchException('body too large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        throw const PictureFetchException('body too large');
      }
    }
    return bytes.takeBytes();
  }
  throw const PictureFetchException('redirect refused');
}
