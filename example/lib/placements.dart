// Placements: named places of the app that show the document the builder put there.
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

/// A place on the home screen.
Widget homeBanner({
  required String projectBase,
  required RenderTheme theme,
  required Map<String, Object?> data,
  required SduiActionCallback onAction,
  required void Function(String message) log,
}) {
  return HotlayoutPlacement(
    name: 'home.banner',
    projectBase: Uri.parse(projectBase), // the project folder in your storage
    theme: theme,
    data: data,
    onAction: onAction,
    onPlacementEvent: (name, event) => log('$name: ${event.show.name} ${event.report?.name}'),
  );
}

/// A banner with its own margins: when the place is empty (nothing is put there, or a pause of its
/// schedule), the margins go too, so no gap is left on the screen.
class PaddedBanner extends StatefulWidget {
  const PaddedBanner({super.key, required this.projectBase, required this.theme, required this.data});

  final String projectBase;
  final RenderTheme theme;
  final Map<String, Object?> data;

  @override
  State<PaddedBanner> createState() => _PaddedBannerState();
}

class _PaddedBannerState extends State<PaddedBanner> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _shown ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8) : EdgeInsets.zero,
      // The place stays mounted: it draws a zero-size box while empty and decides again by itself
      // when the next window of its schedule starts or ends.
      child: HotlayoutPlacement(
        name: 'home.banner',
        projectBase: Uri.parse(widget.projectBase),
        theme: widget.theme,
        data: widget.data,
        onPlacementEvent: (name, event) {
          final shown = event.show == PlacementShow.document;
          if (shown != _shown) setState(() => _shown = shown);
        },
      ),
    );
  }
}

/// Keeps the last known map between launches of the app.
final class MyPlacementStore implements PlacementMapStore {
  final Map<String, String> _texts = {};

  @override
  Future<String?> read(String key) async => _texts[key];

  @override
  Future<void> write(String key, String text) async => _texts[key] = text;
}

/// A source of your own: a bundled map and a store.
Future<PlacementLoad> readHomeBanner(Uri base) async {
  final source = PlacementSource(
    projectBase: base,
    name: 'home.banner',
    bundledMap: await rootBundle.loadString('assets/hotlayout/placements.json'),
    store: MyPlacementStore(), // implements PlacementMapStore
  );
  final load = await source.refresh();
  // load.resolution.status: document, empty, unknown or unreadable
  // load.entry: the entry point, or null for the initial screen
  // load.documentSource: a DocumentSource of the placed document, or null
  return load;
}
