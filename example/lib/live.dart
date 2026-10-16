// A live app: data from a stream, a new publication picked up while the app
// runs, and the app's own actions routed by type. Nothing here depends on a
// particular backend; a Firestore stream, a WebSocket or a poll of your API
// all fit the same shapes.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:http/http.dart' as http;

/// Draws the document with data that changes while it is open.
///
/// Every new map goes to `renderDocument` as is: the open screen shows it,
/// and the screen stack, the record a screen was opened with, the carousels
/// and the fields stay.
Widget drawLive(
  UiDocument document,
  RenderTheme theme,
  Stream<Map<String, Object?>> data, {
  SduiRecordActionCallback? onRecordAction,
}) {
  // With Firestore: `userDoc.snapshots().map((s) => s.data() ?? const {})`.
  return StreamBuilder<Map<String, Object?>>(
    stream: data,
    builder: (context, snapshot) => renderDocument(
      document,
      theme: theme,
      // Before the first event the screen shows the fallbacks of its texts.
      data: snapshot.data ?? const {},
      onRecordAction: onRecordAction,
    ),
  );
}

/// The app's own actions: one handler per type, the checked standard actions,
/// and one place for whatever was not performed.
HostActions appActions({
  required Future<void> Function(String rewardId) redeem,
  required Future<void> Function() askForNotifications,
  required void Function(String url) openUrl,
  required void Function(String url) openAppLink,
  required void Function(String message) say,
}) {
  return HostActions(
    handlers: {
      // Write the redemption where your data stream comes from; the screen
      // shows `redemption.status` and `redemption.code` when they arrive.
      // While the Future runs, a second tap on the same type is dropped.
      'redeem': (call) async {
        final id = call.valueOf('reward.id');
        if (id == null) return;
        await redeem(id);
      },
      'copy': (call) async {
        await Clipboard.setData(ClipboardData(text: call.valueOf('text') ?? ''));
        say('Copied');
      },
      'notify': (call) => askForNotifications(),
    },
    openUrl: openUrl,
    // A `deeplink` runs only with a scheme your app owns.
    deeplinkSchemes: const ['myapp'],
    openDeeplink: openAppLink,
    onMiss: (call, reason) => debugPrint('action ${call.type} not performed: ${reason.name}'),
  );
}

/// A transport that asks the server whether the file changed since the last
/// read (`If-None-Match`) and gets `304 Not Modified` instead of the body when
/// it did not. The source then sees the same text and the same signature.
///
/// A mobile app only: in a web build the header makes the browser send a CORS
/// preflight, which your storage must then allow.
final class EtagTransport implements DocumentTransport {
  EtagTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, ({String etag, String body})> _last = {};

  @override
  Future<DocumentResponse> fetch(Uri url) async {
    // The source adds a fresh `_req` to every address; the file is the same.
    final key = url.replace(queryParameters: {...url.queryParameters}..remove('_req')).toString();
    final cached = _last[key];
    final response = await _client.get(url, headers: {if (cached != null) 'If-None-Match': cached.etag});
    if (response.statusCode == 304 && cached != null) {
      return (statusCode: 200, body: cached.body);
    }
    final body = utf8.decode(response.bodyBytes);
    final etag = response.headers['etag'];
    if (response.statusCode == 200 && etag != null) _last[key] = (etag: etag, body: body);
    return (statusCode: response.statusCode, body: body);
  }
}

/// The published document and theme, read again every [interval] and when
/// the app comes back to the foreground.
///
/// What it keeps on screen:
///  * a refresh that brings the same document changes nothing;
///  * a new publication replaces the document; the screen stack stays when
///    its screens are still in the new version;
///  * a refresh that failed (no network, a timeout) keeps the published
///    document on screen instead of going back to the bundled copy.
class LivePublication extends ChangeNotifier with WidgetsBindingObserver {
  LivePublication({
    required this.document,
    required ThemeLoad theme,
    this.themeUrl,
    this.transport,
    this.interval = const Duration(minutes: 1),
  }) : _theme = theme;

  /// Where the document comes from.
  final DocumentSource document;

  /// Where the published theme lives; `null` keeps [theme] as it was given.
  final Uri? themeUrl;
  final DocumentTransport? transport;

  /// How often to ask; `null` asks only on start and on returning to the app.
  final Duration? interval;

  DocumentLoad? _load;
  ThemeLoad _theme;
  String? _themeText;
  Timer? _timer;
  bool _refreshing = false;

  /// What to draw; `null` before the first read.
  DocumentLoad? get load => _load;

  /// The themes to draw with.
  ThemeContract get theme => _theme.contract;

  /// Shows the bundled copy at once, asks the network, then keeps asking.
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    final seed = document.seed;
    if (seed != null) _accept(await seed.load());
    await refresh();
    final every = interval;
    if (every != null && document.isRefreshable) {
      _timer = Timer.periodic(every, (_) => refresh());
    }
  }

  /// Reads the document and the theme once.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      _accept(await document.load());
      await _refreshTheme();
    } finally {
      _refreshing = false;
    }
  }

  void _accept(DocumentLoad next) {
    final previous = _load;
    if (previous != null) {
      // A failed refresh is not news: the published document stays on screen.
      if (next.isFallback && !previous.isFallback) return;
      if (previous.signature == next.signature) return;
    }
    _load = next;
    notifyListeners();
  }

  Future<void> _refreshTheme() async {
    final url = themeUrl;
    final pipe = transport;
    if (url == null || pipe == null) return;
    // The theme is compared by its text: a republished theme with the same
    // values is not a change.
    final DocumentResponse response;
    try {
      response = await pipe.fetch(url).timeout(kThemeFetchTimeout);
    } on Object {
      return;
    }
    if (response.statusCode != 200 || response.body == _themeText) return;
    final next = ThemeLoad.parse(response.body);
    if (next.isFallback) return;
    _themeText = response.body;
    _theme = next;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Draws what [LivePublication] holds, with live data.
class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key, required this.publication, required this.data, this.actions});

  final LivePublication publication;
  final Map<String, Object?> data;
  final HostActions? actions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: publication,
      builder: (context, _) {
        final load = publication.load;
        if (load == null) return const SizedBox.shrink();
        return renderDocument(
          load.document,
          theme: publication.theme.themeForBrightness(MediaQuery.platformBrightnessOf(context)),
          data: data,
          onRecordAction: actions?.handle,
        );
      },
    );
  }
}
