/// Limit: a number from the document, the theme or the data never becomes an exception.
///
/// `double.toInt()`, `round()`, `floor()` and `ceil()` throw on infinity and NaN, and `jsonDecode`
/// turns `1e400` into infinity. An uncaught error in `build` replaces the screen with an error
/// widget (a red box in debug, a grey one in release), so every conversion must check its range
/// first. Each case below walks a real fixture and replaces numbers with a hostile value: all of
/// them at once, then key by key.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import '../support/demo_data.dart';
import '../support/fixtures.dart';
import 'support.dart';

/// Parses and draws every screen of [json] with [data]; returns the first failure or `null`.
///
/// Errors are collected through `FlutterError.onError` so that the FIRST one is named, not a
/// "multiple exceptions" summary.
Future<String?> drawOutcome(
  WidgetTester tester,
  Map<String, Object?> json, {
  Map<String, Object?> data = sampleScreenData,
  RenderTheme? theme,
}) async {
  final UiDocument doc;
  try {
    doc = UiDocument.fromJson(json);
  } on Object catch (e) {
    return 'parse threw ${e.runtimeType}: ${'$e'.split('\n').first}';
  }
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    for (final screen in doc.screens) {
      await pumpDocument(tester, doc, data: data, theme: theme, entry: screen.screenId, now: DateTime.utc(2026, 10, 10, 9));
      await tester.pump(const Duration(milliseconds: 800));
      if (errors.isNotEmpty) {
        final e = errors.first;
        final frame = e.stack.toString().split('\n').firstWhere((l) => l.contains('package:hotlayout_flutter'), orElse: () => '');
        return 'screen ${screen.screenId}: ${e.exception.runtimeType}: ${'${e.exception}'.split('\n').first} at ${frame.trim()}';
      }
    }
    await tester.pumpWidget(const SizedBox());
  } finally {
    FlutterError.onError = previous;
  }
  return null;
}

void main() {
  group('document numbers: every number of a fixture replaced at once', () {
    for (final id in fixtureIds) {
      for (final value in jsonHostileNumbers.entries) {
        testWidgets('$id, ${value.key}', (tester) async {
          final hostile = (replaceNumbers(decodeObject(readFixture(id)), value.value) as Map).cast<String, Object?>();
          expect(await drawOutcome(tester, hostile, theme: fixtureTheme(id)), isNull);
        });
      }
    }
  });

  group('document numbers: key by key', () {
    // One fixture per numeric key: the first one that carries it.
    final firstFixtureOf = <String, String>{};
    for (final id in fixtureIds) {
      for (final key in numericKeys(decodeObject(readFixture(id)))) {
        firstFixtureOf.putIfAbsent(key, () => id);
      }
    }
    for (final entry in firstFixtureOf.entries) {
      for (final value in jsonHostileNumbers.entries) {
        testWidgets('"${entry.key}" = ${value.key} (in ${entry.value})', (tester) async {
          final source = decodeObject(readFixture(entry.value));
          final hostile = (replaceNumbers(source, value.value, keys: {entry.key}) as Map).cast<String, Object?>();
          expect(await drawOutcome(tester, hostile, theme: fixtureTheme(entry.value)), isNull);
        });
      }
    }
  });

  group('data numbers: every number of the host data replaced', () {
    for (final id in fixtureIds) {
      for (final value in dataHostileNumbers.entries) {
        testWidgets('$id, ${value.key}', (tester) async {
          final data = (replaceNumbers(sampleScreenData, value.value) as Map).cast<String, Object?>();
          expect(await drawOutcome(tester, decodeObject(readFixture(id)), data: data, theme: fixtureTheme(id)), isNull);
        });
      }
    }
  });

  group('theme numbers: key by key, every theme of the set draws a fixture', () {
    final themes = {
      'built-in theme': decodeObject(readThemeContract())['contract'],
      for (final e in fixtureThemeFiles.entries) '${e.key} theme': decodeObject(File('assets/contract/fixtures/${e.value}.json').readAsStringSync()),
    };
    for (final theme in themes.entries) {
      for (final key in <String?>{null, ...numericKeys(theme.value)}) {
        for (final value in jsonHostileNumbers.entries) {
          testWidgets('${theme.key}: ${key == null ? 'every number' : '"$key"'} = ${value.key}', (tester) async {
            final hostile = replaceNumbers(theme.value, value.value, keys: key == null ? null : {key});
            final ThemeLoad load;
            try {
              load = ThemeLoad.fromJson(hostile);
            } on Object catch (e) {
              fail('parse threw $e');
            }
            for (final id in load.contract.themes.keys) {
              final failure = await drawOutcome(tester, decodeObject(readFixture('rewards-showcase-screens')), theme: load.contract.themeById(id));
              expect(failure, isNull, reason: 'theme $id');
            }
          });
        }
      }
    }
  });
}
