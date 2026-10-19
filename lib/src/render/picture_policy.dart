/// What the host decides about pictures: which addresses are fetched, and how much of a body is read.
library;

import '../model/action_catalog.dart';

/// The host's decision about a picture address. Returns the address to fetch (it may be rewritten, for example
/// to a CDN), or `null` to refuse it; a refused picture draws the "image unavailable" placeholder and makes no
/// request. See `renderDocument` (`resolveImageUrl`).
typedef ImageUrlResolver = String? Function(String url);

/// The default `maxDownloadBytes`: 10 MiB (10 485 760 bytes, `x-imageSource.network.maxBodyBytes`).
const int kDefaultMaxDownloadBytes = 10 * 1024 * 1024;

/// The most pixels along the longer side a picture is decoded at, whatever the box it is drawn in.
const int kMaxDecodedSide = 4096;

/// How long one picture may take, redirects included.
const Duration kPictureTimeout = Duration(seconds: 30);

/// The most redirects one picture request follows.
const int kMaxPictureRedirects = 3;

/// The default policy: only an `https` address whose host is a name with an alphabetic top-level label — the
/// host form of the contract (`x-actions.forms.httpsUrl`). No IP literal in any notation, no single-word name
/// such as `localhost`, no user info, no other scheme.
String? defaultImageUrlPolicy(String url) =>
    paramFormProblem(ActionParamForm.httpsUrl, url) == null ? url : null;

/// The picture rules a screen is drawn with: the host's address policy and the body cap.
final class PicturePolicy {
  const PicturePolicy({
    this.resolveImageUrl,
    this.maxDownloadBytes = kDefaultMaxDownloadBytes,
  });

  /// The host's address policy, or `null` for [defaultImageUrlPolicy].
  final ImageUrlResolver? resolveImageUrl;

  /// The most bytes of one picture body that is read.
  final int maxDownloadBytes;

  /// The address to fetch for [url], or `null` when it is refused. A policy that throws refuses.
  ///
  /// The default policy applies to network addresses only: a `data:image/…` address makes no request and is
  /// bounded by size instead (see `imageContent`). A host policy sees every address, `data:` included.
  String? approve(String url, {bool isData = false}) {
    final resolver = resolveImageUrl;
    if (resolver == null) return isData ? url : defaultImageUrlPolicy(url);
    try {
      final answer = resolver(url);
      return answer == null || isNeverAnImage(answer) ? null : answer;
    } on Object {
      return null;
    }
  }
}

/// Whether [url], read as a URL parser reads it, is a `javascript:` or `vbscript:` address: leading U+0000–U+0020
/// stripped, tab, line feed and carriage return removed anywhere, the scheme compared case-insensitively. The
/// host's decision cannot make such an address a picture.
bool isNeverAnImage(String url) {
  var start = 0;
  while (start < url.length && url.codeUnitAt(start) <= 0x20) {
    start += 1;
  }
  final cleaned = url.substring(start).replaceAll(RegExp('[\t\n\r]'), '').toLowerCase();
  return cleaned.startsWith('javascript:') || cleaned.startsWith('vbscript:');
}

/// The address of a refused picture as the report may say it: an address of the document, cut to 120 characters;
/// an address from data, its scheme and host at most (the path or the query may carry a token).
String pictureReportAddress(String url, {required bool fromData}) {
  // A control character of a hostile address must not reach a log line.
  url = url.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '?');
  if (!fromData) return url.length <= 120 ? url : url.substring(0, 120);
  final match = RegExp(r'^\s*([A-Za-z][A-Za-z0-9+.-]*:)(?://([^/?#\s]*))?').firstMatch(url);
  if (match == null) return '';
  final authority = match.group(2);
  final host = authority == null ? '' : '//${authority.substring(authority.lastIndexOf('@') + 1)}';
  final head = '${match.group(1)}$host';
  return head.length <= 120 ? head : head.substring(0, 120);
}

/// A handle to stop a picture request that nobody waits for any more: the connection is closed and the timer
/// of its timeout is cancelled.
final class PictureCancel {
  void Function()? _listener;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Stops the request. The request's future completes with an error that names the cancellation.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _listener?.call();
  }

  /// Called by the loader: [listener] runs on [cancel], at once when it already happened.
  // ignore: use_setters_to_change_properties
  void onCancel(void Function() listener) {
    _listener = listener;
    if (_cancelled) listener();
  }
}
