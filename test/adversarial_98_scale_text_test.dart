/// HOSTILE-INPUT TESTS FOR THE 9.7.0 SCALE AND THE 9.6.0 RICH TEXT -- `hotlayout_flutter`.
///
/// The document arrives from the network as a JSON STRING, so the hostile values here are
/// what `jsonDecode` really produces: `1e999` is `Infinity`, a twenty-digit
/// integer is a `double`. Every node is drawn as a real screen; the frame must not throw.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

UiDocument _doc(String childrenJson) => UiDocument.fromJson(
  jsonDecode('''
{"schemaVersion":"${UiDocument.supportedSchemaVersion}","documentId":"adv","name":"adv","initialScreenId":"a",
 "screens":[{"screenId":"a","name":"a","root":{"id":"root","type":"Screen","props":{},"children":$childrenJson}}]}
''')
      as Map<String, Object?>,
);

const _numbers = ['1e999', '-1e999', '-0.0', '-1', '1e308', '5e-324', '99999999999999999999', '0.5', '"12"', 'null', 'true', '[]', '{}'];

void main() {
  for (final type in ['ProgressBar', 'CircularProgress']) {
    testWidgets('GUARD 9.7.0 $type: value, max, thickness and sizes as hostile numbers -- the frame does not throw', (tester) async {
      for (final hostile in _numbers) {
        for (final field in ['value', 'max']) {
          final other = field == 'value' ? 'max' : 'value';
          await pumpDocument(
            tester,
            _doc(
              '[{"id":"p","type":"$type","props":{"$field":{"kind":"literal","value":$hostile},"$other":{"kind":"literal","value":7},"labelFormat":"percent","thickness":4},"style":{"width":56,"height":56}}]',
            ),
          );
          expect(tester.takeException(), isNull, reason: '$type.$field = $hostile');
        }
        await pumpDocument(
          tester,
          _doc('[{"id":"p","type":"$type","props":{"value":{"kind":"literal","value":5},"max":{"kind":"literal","value":7},"thickness":$hostile}}]'),
        );
        expect(tester.takeException(), isNull, reason: '$type.thickness = $hostile');
        for (final key in ['width', 'height', 'minWidth', 'maxWidth', 'minHeight', 'maxHeight', 'padding', 'opacity']) {
          await pumpDocument(
            tester,
            _doc(
              '[{"id":"p","type":"$type","props":{"value":{"kind":"literal","value":5},"max":{"kind":"literal","value":7},"thickness":128,'
              '"gradient":{"angle":90,"stops":[{"color":"warning","position":0},{"color":"danger","position":1}]}},"style":{"$key":$hostile}}]',
            ),
          );
          expect(tester.takeException(), isNull, reason: '$type style.$key = $hostile');
        }
      }
    });

    testWidgets('GUARD 9.7.0 $type: zero geometry and a hostile gradient -- the frame does not throw', (tester) async {
      final stops5000 = List.filled(5000, '{"color":"primary","position":0.5}').join(',');
      for (final gradient in [
        '{"angle":90,"stops":[]}',
        '{"angle":90,"stops":[{"color":"primary","position":0}]}',
        '{"angle":90,"stops":[{"color":"primary","position":-1},{"color":"danger","position":2}]}',
        '{"angle":90,"stops":[{"color":"primary","position":1e999},{"color":"danger","position":1}]}',
        '{"angle":90,"stops":[{"color":"primary","position":1},{"color":"danger","position":0}]}',
        '{"angle":90,"stops":[{"color":"primary","position":0.5},{"color":"danger","position":0.5}]}',
        '{"angle":90,"stops":[{"color":"primary","position":0},{"color":"primary","position":0}]}',
        '{"angle":90,"stops":[{"color":{"value":"#zzzzzz"},"position":0},{"color":5,"position":1}]}',
        '{"angle":1e999,"stops":[{"color":"primary","position":0},{"color":"danger","position":1}]}',
        '{"angle":90,"stops":[$stops5000]}',
        '{"angle":90,"stops":{"0":{"color":"primary","position":0}}}',
        '"__proto__"',
        '5',
        '[]',
      ]) {
        for (final box in ['{"width":0,"height":0}', '{"width":1,"height":1,"padding":64}', '{"minWidth":400,"maxWidth":1}', '{}']) {
          for (final value in ['0', '7', '3']) {
            await pumpDocument(
              tester,
              _doc(
                '[{"id":"p","type":"$type","props":{"value":{"kind":"literal","value":$value},"max":{"kind":"literal","value":7},"thickness":128,"gradient":$gradient},"style":$box}]',
              ),
            );
            expect(tester.takeException(), isNull, reason: '$type gradient=${gradient.length > 90 ? gradient.substring(0, 90) : gradient} box=$box value=$value');
          }
        }
      }
    });
  }

  testWidgets('GUARD 9.6.0: hostile part style and place names -- the frame does not throw', (tester) async {
    const content =
        '{"kind":"template","template":"{amount} {unit} {constructor} {toString} {zzz}","values":{"amount":{"kind":"binding","path":"user.points","fallback":"0"},"unit":{"kind":"text","text":"points"}}}';
    for (final span in [
      '{"typography":{"token":"bodyS","fontSize":1e999}}',
      '{"typography":{"token":"bodyS","fontSize":-1e999,"lineHeight":0}}',
      '{"typography":{"token":"bodyS","lineHeight":-1}}',
      '{"typography":{"token":"bodyS","lineHeight":1e999}}',
      '{"typography":{"token":"bodyS","fontWeight":"900"}}',
      '{"typography":{"token":"bodyS","fontWeight":1e999}}',
      '{"typography":{"token":"bodyS","letterSpacing":1e999}}',
      '{"typography":{"token":"__proto__","fontSize":20}}',
      '{"typography":5}',
      '{"color":{"value":"#ffffff;x"}}',
      '{"color":{"token":"primary","opacity":1e999}}',
      '{"color":{"token":"primary","opacity":-1}}',
      '{"color":[]}',
      '5',
      'null',
    ]) {
      await pumpDocument(
        tester,
        _doc('[{"id":"t","type":"Text","props":{"content":$content,"spans":{"amount":$span,"unit":$span,"constructor":$span,"zzz":$span}}}]'),
        data: const {'user.points': 10},
      );
      expect(tester.takeException(), isNull, reason: 'span = $span');
    }
  });

  testWidgets('GUARD 9.6.0: the parser is not quadratic -- 10,000 places and 100 KB of braces', (tester) async {
    final values = [for (var index = 0; index < 50; index += 1) '"p$index":{"kind":"text","text":"x"}'].join(',');
    final spans = [for (var index = 0; index < 50; index += 1) '"p$index":{"color":"${index.isEven ? 'danger' : 'muted'}"}'].join(',');
    final many = [for (var index = 0; index < 10000; index += 1) '{p${index % 50}}'].join(' ');
    for (final template in [many, '{' * 100000, '{a' * 50000, '${'{{' * 25000}${'}}' * 25000}', '{p0}' * 25000]) {
      final watch = Stopwatch()..start();
      await pumpDocument(
        tester,
        _doc('[{"id":"t","type":"Text","props":{"content":{"kind":"template","template":${jsonEncode(template)},"values":{$values}},"spans":{$spans}}}]'),
      );
      watch.stop();
      expect(tester.takeException(), isNull);
      expect(watch.elapsedMilliseconds, lessThan(4000), reason: 'template of ${template.length} characters took ${watch.elapsedMilliseconds} ms to draw');
    }
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
