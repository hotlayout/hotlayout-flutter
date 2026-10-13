// Regenerates the embedded icon set from the contract artifacts:
//
//   dart run tool/generate_icon_set.dart
//
// Run it after every copy of
//   the contract's icons.json and screen-schema.json into assets/contract/
//
// Since contract 9.3.0 an icon drawing is contract DATA (`contract/icons.json`),
// not a platform resource. A document carries only the icon name, so the reader
// must hold the WHOLE set, and it is not delivered over the network. The set is
// therefore embedded as code, like the built-in theme: the package declares no
// assets (they would ship in every consumer's bundle and load asynchronously,
// so an icon would flicker on the first frame).
//
// If you forget, test/icon_set_test.dart fails: the copy must equal the
// artifact byte for byte.

import 'dart:convert';
import 'dart:io';

const String _icons = 'assets/contract/icons.json';
const String _schema = 'assets/contract/screen-schema.json';
const String _target = 'lib/src/model/icon_set.dart';

/// The grid the painter supports (`lib/src/render/icon_glyph.dart`). If the
/// contract changes the root (another canvas, other line caps) the generator
/// stops: an embedded set with a foreign grid, accepted silently, would be
/// drawn differently from the editor canvas.
const Map<String, Object> _supportedGrid = {
  'viewBox': '0 0 24 24',
  'size': 24,
  'fill': 'none',
  'stroke': 'currentColor',
  'strokeWidth': 2,
  'strokeLinecap': 'round',
  'strokeLinejoin': 'round',
};

void main() {
  final icons = jsonDecode(File(_icons).readAsStringSync()) as Map<String, Object?>;
  final schema = jsonDecode(File(_schema).readAsStringSync()) as Map<String, Object?>;

  final version = icons['iconSetVersion'];
  final grid = icons['grid'];
  final bodies = icons['icons'];
  final mirrored = schema['x-mirroredIcons'];
  if (version is! String || grid is! Map || bodies is! Map || mirrored is! List) {
    stderr.writeln('artifacts have the wrong format: iconSetVersion, grid, icons and x-mirroredIcons are required');
    exitCode = 1;
    return;
  }
  if (jsonEncode(grid) != jsonEncode(_supportedGrid)) {
    stderr.writeln('the set\'s grid has changed: ${jsonEncode(grid)}\nthe painter supports only ${jsonEncode(_supportedGrid)}');
    exitCode = 1;
    return;
  }

  final out = StringBuffer(_header)
    ..writeln("const String kIconSetVersion = ${_string(version)};")
    ..writeln()
    ..writeln('/// Side of the drawing canvas in grid units (`grid.size`).')
    ..writeln('const double kIconGridSize = ${(grid['size'] as num).toDouble()};')
    ..writeln()
    ..writeln('/// Stroke width in GRID units (`grid.strokeWidth`), not pixels.')
    ..writeln('const double kIconGridStrokeWidth = ${(grid['strokeWidth'] as num).toDouble()};')
    ..writeln()
    ..writeln('/// The artifact\'s `grid` block as is, for comparing against the artifact.')
    ..writeln('const Map<String, Object> kIconGrid = {');
  for (final entry in grid.entries) {
    final value = entry.value;
    out.writeln('  ${_string(entry.key as String)}: ${value is String ? _string(value) : value},');
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln('/// Icons mirrored in right-to-left writing (`x-mirroredIcons` of the schema).')
    ..writeln('const Set<String> kMirroredIcons = {');
  for (final name in mirrored) {
    out.writeln('  ${_string(name as String)},');
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln('/// Icon name to SVG body (`icons` of the artifact), in artifact order.')
    ..writeln('const Map<String, String> kIconBodies = {');
  for (final entry in bodies.entries) {
    out.writeln('  ${_string(entry.key as String)}:\n      ${_string(entry.value as String)},');
  }
  out.writeln('};');

  File(_target).writeAsStringSync(out.toString());
  stdout.writeln('$_target regenerated: ${bodies.length} icons, set $version');
}

/// A Dart string in DOUBLE quotes: the bodies carry single quotes in attributes.
String _string(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$')}"';

const String _header = '''
// The icon set of the contract, built into the code: `assets/contract/icons.json`
// (drawings, grid, version) and `x-mirroredIcons` from
// `assets/contract/screen-schema.json`.
//
// GENERATED: dart run tool/generate_icon_set.dart. Do not edit by hand.
//
// The renderer has no icon drawings of its own: every reader draws from the
// same artifact, so the picture in the editor is the picture on the phone.
// The copy cannot drift from the artifact silently: `test/icon_set_test.dart`
// compares them byte for byte.
//
// Apart from ten bespoke drawings, the icons are Lucide (ISC); some of them
// derive from Feather (MIT). License texts are in `THIRD-PARTY-NOTICES.md` at
// the package root.
//
// ignore_for_file: prefer_single_quotes, lines_longer_than_80_chars

/// The version of the icon drawings built into this renderer
/// (`iconSetVersion` of `contract/icons.json`). Independent of the document
/// contract version: a redrawn icon changes only this.
''';
