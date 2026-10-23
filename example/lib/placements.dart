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
    onPlacement: (name, report) => log('$name: ${report.name}'),
  );
}

/// Keeps the last known map between launches of the app.
final class MyPlacementStore implements PlacementMapStore {
  String? _text;

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async => _text = text;
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
