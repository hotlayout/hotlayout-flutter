/// THE NUMBERS OF A THEME (`x-themeNumbers`): the shared table
/// `assets/contract/fixtures/theme-numbers/theme-number-cases.json`.
///
/// Each row puts `value` at `place` in a copy of the built-in theme of `brightness` and expects the number the
/// reader draws with: the value of the same token and field in the built-in theme when the place has one, otherwise
/// the nearest bound; and a line in the report of the theme. A token is no longer dropped as a whole.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import 'hardening/support.dart' show decodeObject;
import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = jsonDecode(File('assets/contract/fixtures/theme-numbers/theme-number-cases.json').readAsStringSync()) as _Row;

List<_Row> _rows() => (_table['numberCases']! as List<Object?>).cast<_Row>();

/// A copy of the built-in theme of [brightness] as JSON.
_Row _builtIn(String brightness) {
  final contract = decodeObject(readThemeContract())['contract']! as _Row;
  final theme = (contract['themes']! as _Row)[brightness]! as _Row;
  return jsonDecode(jsonEncode(theme)) as _Row;
}

/// `"Infinity"` and `"-Infinity"` stand for what a JSON parser reads from `1e309`.
Object? _valueOf(Object? raw) => switch (raw) {
  'Infinity' => double.infinity,
  '-Infinity' => double.negativeInfinity,
  _ => raw,
};

/// Writes the row's value into [theme]; a token the built-in theme lacks is made from a built-in one first.
void _put(_Row theme, _Row place, Object? value) {
  final dictionary = place['dictionary']! as String;
  final token = place['token']! as String;
  final group = theme[dictionary]! as _Row;
  final field = place['field'] as String?;
  switch (dictionary) {
    case 'spacing' || 'radius':
      group[token] = value;
    case 'typography':
      final style = (group[token] ??= {'fontSize': 14, 'lineHeight': 1.4, 'fontWeight': 400, 'role': 'body'}) as _Row;
      style[field!] = value;
    case 'elevation':
      final layers = group[token]! as List<Object?>;
      (layers[place['layer']! as int]! as _Row)[field!] = value;
    case 'gradient':
      final stops = (group[token]! as _Row)['stops']! as List<Object?>;
      (stops[place['stop']! as int]! as _Row)[field!] = value;
    default:
      fail('unknown dictionary $dictionary');
  }
}

/// The report line the place gets: `<dictionary>.<token>[…].<field>`.
String _placeOf(_Row place) {
  final dictionary = place['dictionary']! as String;
  final token = place['token']! as String;
  final field = place['field'] as String?;
  return switch (dictionary) {
    'spacing' || 'radius' => '$dictionary.$token',
    'typography' => 'typography.$token.$field',
    'elevation' => 'elevation.$token[${place['layer']}].$field',
    _ => 'gradient.$token.stops[${place['stop']}].$field',
  };
}

/// The number the reader draws with at [place].
double _drawn(RenderTheme theme, _Row place) {
  final token = place['token']! as String;
  final field = place['field'] as String?;
  switch (place['dictionary']! as String) {
    case 'spacing':
      return theme.spacing[token]!;
    case 'radius':
      return theme.radii[token]!;
    case 'typography':
      final style = theme.typography[token]!;
      return switch (field!) {
        'fontSize' => style.fontSize!,
        'lineHeight' => style.height!,
        'fontWeight' => style.fontWeight!.value.toDouble(),
        'letterSpacing' => style.letterSpacing!,
        _ => fail('unknown typography field $field'),
      };
    case 'elevation':
      // The reader keeps shadows in painting order: the first of the contract is the last here.
      final layers = theme.elevations[token]!;
      final BoxShadow layer = layers[layers.length - 1 - (place['layer']! as int)];
      return switch (field!) {
        'blur' => layer.blurRadius,
        'offsetY' => layer.offset.dy,
        'offsetX' => layer.offset.dx,
        'spread' => layer.spreadRadius,
        'opacity' => layer.color.a,
        _ => fail('unknown shadow field $field'),
      };
    default:
      return theme.gradients[token]!.stops![place['stop']! as int];
  }
}

void main() {
  test('the table has the promised rows', () => expect(_rows(), hasLength(31)));

  for (final row in _rows()) {
    test(row['name']! as String, () {
      final place = row['place']! as _Row;
      final theme = _builtIn(row['brightness']! as String);
      _put(theme, place, _valueOf(row['value']));
      final read = RenderTheme.fromJson(theme);

      expect(_drawn(read, place), closeTo((row['expected']! as num).toDouble(), 0.0001));

      final replacedBy = row['replacedBy'] as String?;
      if (replacedBy == null) {
        expect(read.numberReports, isEmpty, reason: 'a number inside the bounds is not reported');
      } else {
        expect(read.numberReports, ['${_placeOf(place)}: $replacedBy']);
      }
    });

    // The same through the contract: a theme set read by the loader keeps the token and says so.
    test('through the loader: ${row['name']}', () {
      final place = row['place']! as _Row;
      final theme = _builtIn(row['brightness']! as String);
      _put(theme, place, _valueOf(row['value']));
      final load = ThemeLoad.fromJson({
        'themeContractVersion': kSupportedThemeContractVersion,
        'defaultThemeId': theme['id'],
        'themes': {theme['id']! as String: theme},
      });
      expect(load.status, ThemeLoadStatus.ok);
      final read = load.contract.themeById(theme['id']! as String);
      expect(_drawn(read, place), closeTo((row['expected']! as num).toDouble(), 0.0001));
    });
  }
}
