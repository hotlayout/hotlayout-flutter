// The HotLayout quickstart, complete: a published document on screen, with a
// bundled copy underneath, data from the host, a host action and the device
// language.
//
//   flutter run                                   # bundled copies only
//   flutter run --dart-define=documentUrl=https://… --dart-define=themeUrl=https://…
import 'package:flutter/material.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

import 'backend.dart';

/// The bundled copies, declared under `flutter: assets:` in pubspec.yaml.
const documentAsset = 'assets/hotlayout/document.json';
const themeAsset = 'assets/hotlayout/theme.json';

/// Where the published files live. Empty: the bundled copies are shown.
const documentUrl = String.fromEnvironment('documentUrl');
const themeUrl = String.fromEnvironment('themeUrl');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final transport = HttpDocumentTransport();

  // The theme is read BEFORE the first frame: replacing colors after the
  // screen is drawn is a visible jump. Neither call throws.
  final themeLoad = themeUrl.isEmpty
      ? await ThemeLoad.fromBundle(assetPath: themeAsset)
      : await ThemeLoad.fromNetwork(
          Uri.parse(themeUrl),
          transport: transport,
          assetPath: themeAsset,
        );
  if (themeLoad.isFallback) {
    debugPrint('theme fallback: ${themeLoad.status.name} ${themeLoad.detail ?? ''}');
  }

  const bundled = BundledDocumentSource(title: 'Bundled copy', assetPath: documentAsset);
  final DocumentSource source = documentUrl.isEmpty
      ? bundled
      : PublishedDocumentSource(
          url: Uri.parse(documentUrl),
          fallback: bundled,
          transport: transport,
        );

  runApp(
    MaterialApp(
      title: 'HotLayout example',
      debugShowCheckedModeBanner: false,
      home: HotLayoutScreen(source: source, themeLoad: themeLoad, data: backendData),
    ),
  );
}

/// One HotLayout document as a screen of the app.
class HotLayoutScreen extends StatefulWidget {
  const HotLayoutScreen({
    super.key,
    required this.source,
    required this.themeLoad,
    required this.data,
    this.locale,
  });

  final DocumentSource source;
  final ThemeLoad themeLoad;

  /// Values for the paths the document is bound to.
  final Map<String, Object?> data;

  /// The language the user chose in the app; `null` follows the device.
  final String? locale;

  @override
  State<HotLayoutScreen> createState() => _HotLayoutScreenState();
}

class _HotLayoutScreenState extends State<HotLayoutScreen> with WidgetsBindingObserver {
  DocumentLoad? _load;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _read() async {
    // 1. Draw the bundled copy at once: no loading state.
    final seed = widget.source.seed;
    if (seed != null) _show(await seed.load());

    // 2. Ask the network. This never throws because of the network.
    _show(await widget.source.load());
  }

  void _show(DocumentLoad next) {
    if (!mounted) return;
    // A fallback is silent on screen by design, so say it in the log.
    debugPrint('document: ${next.status.name} ${next.detail ?? ''}');

    // A new UiDocument object resets the screen stack. Most re-reads bring
    // the same document: keep the object that is already on screen.
    final previous = _load;
    final unchanged = previous != null && previous.signature == next.signature;
    setState(() => _load = unchanged ? next.reusing(previous.document) : next);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background: a manager may have published meanwhile.
    if (state == AppLifecycleState.resumed && widget.source.isRefreshable) {
      widget.source.load().then(_show);
    }
  }

  // `record` is the record of the node that was tapped: the list row, or the
  // row that opened this screen. A flat map of paths, or null.
  void _onAction(ButtonAction action, String nodeId, Map<String, Object?>? record) {
    switch (action.type) {
      case ButtonAction.navigateBack:
        // "Back" on the first screen of the document: leave the flow.
        Navigator.of(context).maybePop();
      case 'share':
        _say('Your share sheet opens here');
      case 'redeem':
        // Which reward? The row says so. Check the id on your backend like
        // any user input before you spend points on it.
        _say('Redeem ${record?['item.name']} (${record?['item.id']})?');
      default:
        debugPrint('unhandled action ${action.type} from $nodeId');
    }
  }

  // What the user typed or switched in a `TextField`, `Switch`, `Checkbox` or
  // `ChoiceGroup`: the data path of the field and a String, a bool or (a number
  // `TextField`) a num; an empty String when the number was cleared. Called on
  // every change, at once. It is user input: check it on your backend like any
  // other, and throttle here if a network stands behind it.
  void _onWrite(String path, Object? value) {
    switch (value) {
      case String text:
        debugPrint('text field $path: ${text.length} characters');
      case bool on:
        debugPrint('switch or checkbox $path: $on');
      case num number:
        debugPrint('number field $path: $number');
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // The contract marks every theme light or dark: no theme ids in app code.
    final theme = widget.themeLoad.contract.themeForBrightness(
      MediaQuery.platformBrightnessOf(context),
    );

    final load = _load;
    if (load == null) return ColoredBox(color: theme.toMaterialTheme().colorScheme.surface);
    final document = load.document;

    // The document matches the device languages against its own list:
    // `ar-EG` finds `ar`. A user's choice wins over the device.
    final locale =
        widget.locale ??
        document.localization?.localeFor(WidgetsBinding.instance.platformDispatcher.locales);

    return Theme(
      data: theme.toMaterialTheme(),
      // The renderer draws only the document: the Scaffold and the safe area
      // are the host's.
      child: Scaffold(
        body: SafeArea(
          child: renderDocument(
            document,
            theme: theme,
            data: widget.data,
            locale: locale,
            onRecordAction: _onAction,
            onWrite: _onWrite,
            // Documents from a source you do not fully trust: no autofill hints.
            // autofill: false,
          ),
        ),
      ),
    );
  }
}
