import '../report/report_hub.dart';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vgc;

import 'picture_fetch.dart';
import 'picture_policy.dart';

/// Whether the address points to an SVG.
///
/// The question is asked of the PATH EXTENSION, not of the whole string: a media library
/// address looks like `…/o/orgs%2Fa%2Fmedia%2Flogo.svg?alt=media`, where the substring `.svg`
/// sits in the middle, and `…/photo.png?name=a.svg` contains it although the image is raster.
/// So query and fragment are dropped by parsing the address, not by searching characters.
///
/// The path is taken DECODED (`pathSegments`): Firebase Storage encodes the object path whole,
/// slashes included, so the last segment of the address is the whole file path, and its end is
/// the name.
///
/// `.svgz` is NOT SVG for us: it is gzip, and nobody here decompresses it. It is more honest
/// to give such an address to the raster branch, where it yields the ordinary "image
/// unavailable" placeholder, than to pretend support.
///
/// The content type (`image/svg+xml`) is deliberately not consulted: it is known only AFTER the
/// request, while the choice of what to draw with must be made before it. The consequence is
/// documented at hotlayout.com/docs/integrator/flutter-reference: an SVG at an address with no extension is not drawn.
bool isSvgUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  try {
    final segments = uri.pathSegments;
    return segments.isNotEmpty && segments.last.toLowerCase().endsWith('.svg');
  } on Object {
    // `%FF` is a legal percent-escape but not UTF-8: parsing the address succeeds while decoding
    // the segment throws. An address that cannot be read is not an SVG.
    return false;
  }
}

/// An SVG from a network address, with the same three states as a raster image: loading,
/// painted, failed.
///
/// **Why not `SvgPicture.network`.** It does everything needed except two things, and both
/// concern failure:
///
///  * it does not look at the response status at all: the body of a 404 goes to the XML
///    parser, and it becomes an error by accident, not by rule;
///  * a failed load does NOT stay inside the widget. `errorBuilder` fires, but the same
///    exception also escapes uncaught into the zone (the derived `Future` in the library's
///    cache has no listener), and the record of the failure sticks in the cache for good, so
///    the same address is not re-read until the app restarts. One network drop would break the
///    image for the rest of the session. Verified on 2.3.0 with a probe test.
///
/// So the network and the parsing are ours, and the library is handed READY bytes: it paints,
/// but has nothing to fail on.
class NetworkSvg extends StatefulWidget {
  const NetworkSvg({
    super.key,
    required this.url,
    required this.fit,
    this.policy = const PicturePolicy(),
    required this.loading,
    required this.error,
  });

  final String url;
  final BoxFit fit;

  /// The host's rules: the body cap and the address policy that every redirect passes again.
  final PicturePolicy policy;

  /// What to show while the file is on its way, and what when it did not arrive or did not
  /// parse. They come from outside because the placeholders are shared with the raster path:
  /// two copies would drift apart.
  final Widget loading;
  final Widget error;

  @override
  State<NetworkSvg> createState() => _NetworkSvgState();
}

class _NetworkSvgState extends State<NetworkSvg> {
  ByteData? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NetworkSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _release();
      _load();
    }
  }

  /// The address this widget is waiting for, so that a request nobody waits for is stopped.
  String? _waitingFor;

  void _release() {
    final url = _waitingFor;
    _waitingFor = null;
    if (url != null) _SvgStore.instance.release(url);
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _load() {
    final url = widget.url;
    // What is already loaded is taken SYNCHRONOUSLY: otherwise a list row that returned to the
    // screen after scrolling would flash the indicator for one frame every time.
    _bytes = _SvgStore.instance.peek(url);
    _failed = false;
    if (_bytes != null) return;

    _waitingFor = url;
    _SvgStore.instance
        .load(url, widget.policy)
        .then(
          (bytes) {
            if (_waitingFor == url) _waitingFor = null;
            // The address may have changed while the file was on its way (new data under the binding).
            if (!mounted || widget.url != url) return;
            setState(() => _bytes = bytes);
          },
          // `Object`, not `Exception`: parsing SVG also throws `StateError`, and the widget tree must
          // not fall over because of the content of someone else's file.
          onError: (Object error, StackTrace stack) {
            // The class of the failure only: the address may carry a token or a user id, and the text of
            // the error repeats it. Nothing is logged in a release build.
            if (_waitingFor == url) _waitingFor = null;
            ReportHub.ignored('picture', 'SVG not drawn: ${error is PictureFetchException ? error.reason : 'parse error'}');
            if (!mounted || widget.url != url) return;
            setState(() => _failed = true);
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (_failed) return widget.error;
    if (bytes == null) return widget.loading;
    return SvgPicture(
      _CompiledSvg(widget.url, bytes),
      fit: widget.fit,
      // The size is NOT set: like a raster image, it takes the frame the parent gave
      // (`AspectRatio` in `Image`, a square in a row thumbnail). The part that sticks out of the
      // frame under `cover` is clipped by the library itself (`clipBehavior` is hardEdge).
      placeholderBuilder: (_) => widget.loading,
      errorBuilder: (_, _, _) => widget.error,
    );
  }
}

/// An already parsed SVG: the library only has to paint it.
///
/// Equality is by address AND the same bytes: the key of live pictures in the library is
/// computed from the loader, and without equality every rebuild of the tree would decode the
/// picture again.
@immutable
final class _CompiledSvg extends BytesLoader {
  const _CompiledSvg(this.url, this.bytes);

  final String url;
  final ByteData bytes;

  @override
  Future<ByteData> loadBytes(BuildContext? context) => SynchronousFuture(bytes);

  @override
  bool operator ==(Object other) =>
      other is _CompiledSvg &&
      other.url == url &&
      identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(url, identityHashCode(bytes));

  @override
  String toString() => 'NetworkSvg($url)';
}

/// Loaded and parsed SVGs: the session's memory.
///
/// A raster image has the framework's `ImageCache`; this plays its role. Without it a list of
/// twenty rows with one icon would make twenty requests, and as many again on every scroll.
///
/// **Failures are not remembered**: the next display tries again. That is the second reason the
/// network is our own here (see [NetworkSvg]).
final class _SvgStore {
  _SvgStore._();

  static final _SvgStore instance = _SvgStore._();

  /// The same number the library's own cache holds; there is no basis for inventing a number
  /// of our own.
  static const int _capacity = 100;

  final LinkedHashMap<String, ByteData> _loaded = LinkedHashMap();
  final Map<String, Future<ByteData>> _pending = {};

  ByteData? peek(String url) {
    final bytes = _loaded.remove(url);
    // Taken out and put back, i.e. moved to the end: the one asked for longest ago is evicted.
    if (bytes != null) _loaded[url] = bytes;
    return bytes;
  }

  final Map<String, PictureCancel> _cancels = {};
  final Map<String, int> _waiters = {};

  /// One widget stopped waiting for [url]. When the last one did, the request is stopped: nobody needs the file,
  /// and its connection and timer would only live on.
  void release(String url) {
    final left = (_waiters[url] ?? 0) - 1;
    if (left > 0) {
      _waiters[url] = left;
    } else {
      _waiters.remove(url);
      _cancels.remove(url)?.cancel();
    }
  }

  Future<ByteData> load(String url, PicturePolicy policy) {
    _waiters[url] = (_waiters[url] ?? 0) + 1;
    return _pending[url] ??= _start(url, policy);
  }

  Future<ByteData> _start(String url, PicturePolicy policy) {
    final cancel = _cancels[url] = PictureCancel();
    return _fetch(url, policy, cancel)
      .then((bytes) {
        _loaded[url] = bytes;
        if (_loaded.length > _capacity) _loaded.remove(_loaded.keys.first);
        return bytes;
        // The body is a block, not an arrow, ON PURPOSE: `remove` returns this very Future, and
        // `whenComplete` waits for what the callback returned, i.e. for itself.
      })
      .whenComplete(() {
        _pending.remove(url);
        _cancels.remove(url);
        _waiters.remove(url);
      });
  }

  void clear() {
    _loaded.clear();
    _pending.clear();
    _cancels.clear();
    _waiters.clear();
  }

  static Future<ByteData> _fetch(String url, PicturePolicy policy, PictureCancel cancel) async {
    // The picture loader: its own client, a capped body, redirects checked by the host's policy.
    final body = await fetchPictureBytes(Uri.parse(url), approve: policy.approve, maxBytes: policy.maxDownloadBytes, cancel: cancel);
    // `allowMalformed`: broken bytes must reach the XML parser and become a format error there,
    // not an encoding exception with different text.
    final xml = utf8.decode(body, allowMalformed: true);
    final compiled = await _compile(xml);
    return ByteData.sublistView(compiled);
  }

  /// Parses the SVG off the main thread where possible.
  ///
  /// In debug builds and on the web it runs in place: the web has no isolates, and in tests a real
  /// isolate does not finish under fake time. `flutter_svg` follows the same rule.
  static Future<Uint8List> _compile(String xml) => kDebugMode || kIsWeb
      ? Future.sync(() => _compileSvg(xml))
      : compute(_compileSvg, xml, debugLabel: 'SVG');
}

/// Top-level because it goes into an isolate: a closure would drag in everything it sees.
///
/// This is the trust boundary. The parser takes ONLY geometry and paint from the file:
/// `<script>` and event handlers (`onload`) are unknown elements and attributes to it,
/// `<image>` is read only from a `data:` address, external references are not resolved. It has
/// no network at all; the only request is made by `_fetch` above. This is not a promise from
/// documentation but what a test guards (`svg_image_test.dart`, "hostile file"): a library
/// update that changes it will fail there.
Uint8List _compileSvg(String xml) => vgc.encodeSvg(
  xml: xml,
  debugName: 'NetworkSvg',
  // Optimizers are off, as in `flutter_svg`'s own loaders: they need a native library that the
  // device does not have.
  enableClippingOptimizer: false,
  enableMaskingOptimizer: false,
  enableOverdrawOptimizer: false,
);

/// Forget everything loaded, so that tests do not share state through the session memory.
@visibleForTesting
void debugClearSvgStore() => _SvgStore.instance.clear();
