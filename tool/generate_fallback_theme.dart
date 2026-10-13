// Regenerates the embedded theme snapshot from the artifact:
//
//   dart run tool/generate_fallback_theme.dart
//
// Run it after every copy of the contract's theme.json into assets/contract/.
// The snapshot exists for exactly one case, when the artifact cannot be read;
// it is not a source of truth, which is why it is generated rather than
// written by hand.
//
// If you forget, test/theme_contract_test.dart fails: it asserts that the
// embedded snapshot equals the artifact's `contract` block.

import 'dart:convert';
import 'dart:io';

const String _artifact = 'assets/contract/theme.json';
const String _target = 'lib/src/theme/fallback_theme.dart';

void main() {
  final artifact = jsonDecode(File(_artifact).readAsStringSync()) as Map<String, Object?>;
  final contract = artifact['contract'];
  if (contract is! Map) {
    stderr.writeln('$_artifact: no "contract" block, the artifact has the wrong format');
    exitCode = 1;
    return;
  }

  File(_target).writeAsStringSync('$_header${_literal(contract, 0)};\n');
  stdout.writeln('$_target regenerated from $_artifact');
}

String _literal(Object? value, int indent) {
  final pad = '  ' * indent;
  final inner = '  ' * (indent + 1);
  return switch (value) {
    null => 'null',
    bool() => '$value',
    num() => '$value',
    String() => "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'",
    List() when value.isEmpty => '<Object?>[]',
    List() => '[\n${value.map((item) => '$inner${_literal(item, indent + 1)},\n').join()}$pad]',
    Map() when value.isEmpty => '<String, Object?>{}',
    Map() =>
      '{\n${value.entries.map((e) => '$inner${_literal(e.key, indent + 1)}: '
          '${_literal(e.value, indent + 1)},\n').join()}$pad}',
    _ => throw StateError('unexpected type in JSON: ${value.runtimeType}'),
  };
}

const String _header = '''
// A snapshot of the `contract` block of the artifact `assets/contract/theme.json`, embedded in
// code.
//
// GENERATED: dart run tool/generate_fallback_theme.dart. Do not edit by hand.
//
// This is NOT a second source of truth: the values live here for exactly one case, when the
// artifact could not be read (missing file, corrupt data, a foreign theme contract major). The
// app then draws this theme instead of an empty screen.
//
// The snapshot cannot drift from a fresh artifact silently: `test/theme_contract_test.dart`
// compares this map with `assets/contract/theme.json` one to one. If that test fails,
// regenerate the snapshot instead of weakening the assertion.
//
// The map goes through the SAME parser as the artifact; otherwise the fallback would be a
// separate code path that nobody ever exercises.

/// The last theme known to the renderer: a snapshot of the theme contract at build time.
const Map<String, Object?> kFallbackThemeContractJson = ''';
