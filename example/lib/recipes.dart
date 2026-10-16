// Pieces a host adds when it needs them. Every snippet of the README and of
// the integrator documentation that is not in main.dart lives here, so that
// it is compiled and analyzed like any other code.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:http/http.dart' as http;

/// Draws a document with the data of one record behind its details screen.
Widget drawWithScope(
  UiDocument document,
  RenderTheme theme,
  Map<String, Object?> data,
  Map<String, Map<String, Object?>> itemsById,
) {
  // A list row opens a details screen and carries its own record, so the
  // screen already shows the tapped row. The host adds what the row does not
  // have: it finds the full record by the id the row carries.
  Map<String, Object?> scopeFor(ScreenScopeRequest request) {
    final id = request.record?['item.id'];
    final record = id is String ? itemsById[id] : null;
    return record == null ? const {} : {'item': record};
  }

  return renderDocument(document, theme: theme, data: data, scopeFor: scopeFor);
}

/// A host with its own "back" control. Without any of this the system back
/// button already goes one screen back inside the document.
class FlowWithOwnBack extends StatefulWidget {
  const FlowWithOwnBack({required this.document, required this.theme, required this.data, super.key});

  final UiDocument document;
  final RenderTheme theme;
  final Map<String, Object?> data;

  @override
  State<FlowWithOwnBack> createState() => _FlowWithOwnBackState();
}

class _FlowWithOwnBackState extends State<FlowWithOwnBack> {
  // A handle on the document's screen stack.
  final _flow = ScreenFlowController();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The host's own arrow: one screen back inside the document, and out
        // of the flow from its first screen.
        leading: BackButton(
          onPressed: () {
            if (!_flow.goBack()) Navigator.of(context).maybePop();
          },
        ),
        // The controller notifies when the stack changes.
        title: ListenableBuilder(
          listenable: _flow,
          builder: (context, _) => Text(_flow.canGoBack ? 'Details' : 'Rewards'),
        ),
      ),
      body: renderDocument(
        widget.document,
        theme: widget.theme,
        data: widget.data,
        controller: _flow,
      ),
    );
  }
}

/// A flow that asks before the system "back" leaves a screen.
Widget drawWithBackGuard(
  UiDocument document,
  RenderTheme theme,
  Map<String, Object?> data, {
  required bool Function() hasUnsavedInput,
  required VoidCallback askToDiscard,
}) {
  return renderDocument(
    document,
    theme: theme,
    data: data,
    // Called only when the document has a screen to go back to. Return true
    // when you handled the event yourself; false lets the flow step back.
    onSystemBack: () {
      if (!hasUnsavedInput()) return false;
      askToDiscard();
      return true;
    },
  );
}

/// A document whose screens change without motion: the host runs its own
/// transitions around the flow.
Widget withoutTransitions(UiDocument document, RenderTheme theme, Map<String, Object?> data) {
  return renderDocument(
    document,
    theme: theme,
    data: data,
    // Every change of screen, modal layer and tab is instant.
    transitions: HotlayoutTransitions.none,
  );
}

/// Keeps the document object that is on screen when a refresh brings the
/// same document: nothing to redraw.
DocumentLoad apply(DocumentLoad? previous, DocumentLoad next) {
  final unchanged = previous != null && previous.signature == next.signature;
  return unchanged ? next.reusing(previous.document) : next;
}

/// A document obtained without a `DocumentSource` — from your own API, a
/// cache, a push payload — is checked before it is drawn.
Widget drawChecked(String json, RenderTheme theme, Map<String, Object?> data) {
  final document = UiDocument.fromJsonString(json); // throws FormatException
  final verdict = document.versionVerdict;

  if (!verdict.canRender) {
    // This renderer cannot read the document. Only a NEWER document is cured
    // by an app update; an older one has to be republished from the builder.
    debugPrint('document ${document.schemaVersion}, renderer $kSupportedSchemaVersion: $verdict');
    return Center(
      child: Text(
        verdict == VersionVerdict.newerMajor
            ? 'Update the app to see this screen.'
            : 'This screen is not available right now.',
      ),
    );
  }
  return renderDocument(document, theme: theme, data: data);
}

/// The renderer's own words in the language of your app. English by default.
const germanLabels = RendererLabels(
  back: 'Zurück',
  imageUnavailable: 'Bild nicht verfügbar',
  updateRequired: 'Bitte aktualisieren Sie die App, um diesen Bildschirm zu sehen.',
  screenUnavailable: 'Dieser Bildschirm ist gerade nicht verfügbar.',
);

/// What a given device locale gets from a document.
void describeLocale(UiDocument document, String deviceLocale) {
  final answer = document.localeResolution(deviceLocale);
  debugPrint('text: ${answer.translation}'); // ar — the document's own tag
  debugPrint('formats: ${answer.formatting}'); // ar-EG — the requested locale
  debugPrint('direction: ${directionOfLocale(answer.directionLocale)}'); // TextDirection.rtl
  debugPrint('found: ${answer.matched}');
}

/// Draws a document whose "days left" texts are counted from a clock of your
/// own — the server's time, or a fixed moment in a test.
Widget drawAt(UiDocument document, RenderTheme theme, Map<String, Object?> data, DateTime serverNow) {
  // Without `now` the device clock is read each time the screen is built.
  // The screen does not redraw itself at midnight: rebuild to refresh it.
  return renderDocument(document, theme: theme, data: data, now: serverNow);
}

/// The theme to draw with: the user's pick, or the one for the system
/// brightness.
RenderTheme pickTheme(ThemeContract contract, Brightness system, {String? userChoice}) {
  if (userChoice != null && contract.hasTheme(userChoice)) {
    return contract.themeById(userChoice);
  }
  return contract.themeForBrightness(system);
}

/// A transport over your own HTTP client: authentication, pinning, logging.
final class AuthorizedTransport implements DocumentTransport {
  AuthorizedTransport(this.client, this.token);

  final http.Client client;
  final String Function() token;

  @override
  Future<DocumentResponse> fetch(Uri url) async {
    // Let the exception through when the request did not happen; the source
    // applies the timeout. In a web build a custom header makes the browser
    // send a CORS preflight, which your server must then allow.
    final response = await client.get(url, headers: {'Authorization': 'Bearer ${token()}'});
    return (statusCode: response.statusCode, body: utf8.decode(response.bodyBytes));
  }
}

/// Performs the standard actions of the catalog (contract 9.8.0). The renderer
/// opens nothing by itself: it hands over `openUrl`, `deeplink` and `close`
/// checked, and `runStandardAction` runs them with the executors you give.
/// `openBrowser` is where your `url_launcher` goes (the package has none).
bool performStandard(
  ButtonAction action, {
  required void Function(String url) openBrowser,
  required void Function(String url) openAppLink,
  required VoidCallback closeFlow,
}) {
  return runStandardAction(
    action,
    openUrl: openBrowser,
    // The schemes your app owns. Without the list a `deeplink` is never run,
    // whatever the document says.
    deeplinkSchemes: const ['myapp'],
    openDeeplink: openAppLink,
    close: closeFlow,
  );
}

/// Analytics: a tap event (`action.track`) and a screen view.
Widget drawWithAnalytics(
  UiDocument document,
  RenderTheme theme,
  Map<String, Object?> data,
  void Function(String name, Map<String, String> params) log,
) {
  return renderDocument(
    document,
    theme: theme,
    data: data,
    onTrack: (event, nodeId, record) => log(event.event, event.params),
    onScreenShown: (shown) => log('screen_view', {
      'screen': shown.screenId,
      'cause': shown.cause.name, // entry | forward | back
      'depth': '${shown.depth}',
      if (shown.entry != null) 'entry': shown.entry!,
    }),
  );
}

/// Carries out the status bar request of a screen (contract 9.9.0). The package
/// never touches the system status bar: the request of the top screen arrives
/// in `ScreenShown.statusBarIcons` — `'light'` (light icons, for a dark screen)
/// or `'dark'` — only when the screen asked, and carrying it out is yours.
class StatusBarIconsHost extends StatefulWidget {
  const StatusBarIconsHost({super.key, required this.document, required this.theme});

  final UiDocument document;
  final RenderTheme theme;

  @override
  State<StatusBarIconsHost> createState() => _StatusBarIconsHostState();
}

class _StatusBarIconsHostState extends State<StatusBarIconsHost> {
  String? _icons;

  @override
  Widget build(BuildContext context) {
    final screen = renderDocument(
      widget.document,
      theme: widget.theme,
      data: const {},
      onScreenShown: (shown) => setState(() => _icons = shown.statusBarIcons),
    );
    final style = switch (_icons) {
      'light' => SystemUiOverlayStyle.light,
      'dark' => SystemUiOverlayStyle.dark,
      _ => null, // the screen asks for nothing: the system decides
    };
    if (style == null) return screen;
    return AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: screen);
  }
}
