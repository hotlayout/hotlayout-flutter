/// What the host decides about pictures: which addresses are fetched, and how much of a body is read.
library;

import '../model/action_catalog.dart';

/// The host's decision about a picture address. Returns the address to fetch (it may be rewritten, for example
/// to a CDN), or `null` to refuse it; a refused picture draws the "image unavailable" placeholder and makes no
/// request. See `renderDocument` (`resolveImageUrl`).
typedef ImageUrlResolver = String? Function(String url);

/// The default `maxDownloadBytes`: 10 MB.
const int kDefaultMaxDownloadBytes = 10 * 1000 * 1000;

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
      return resolver(url);
    } on Object {
      return null;
    }
  }
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
