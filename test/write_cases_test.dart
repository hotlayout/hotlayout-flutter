/// THE WRITE ACTIONS `setValue` AND `toggleValue` (schema 9.19.0, `x-actions.write`).
///
/// The shared table (`assets/contract/fixtures/actions/action-cases.json`) runs row by row:
///
///  1. `writeCases` (67) -- what a press does with the data under the path, as a pure function, and what the
///     host is told; the rows with a `gate` name a path the reader refuses to write;
///  2. `writeControlCases` (22) -- which node is an option, which a toggle, which a plain button;
///  3. `writeSchemaCases` (14), `writeDocumentCases` (47), `writeTreeCases` (11) -- the structure and the
///     validator are the builder's; for the reader this means "reads and draws without a crash", and where the
///     builder says a parameter is unusable, the reader does nothing with it;
///  4. `writePressCases` (15) -- a REAL press (tap, Enter, Space, a held Enter) on a real screen: the order of the
///     analytics event and the write, the host hearing `onWrite` and never `onAction`, a disabled button, a card.
///
/// The model is the builder's `scripts/action-cases.test.tsx` (the `write…` groups).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/write_action.dart';
import 'package:hotlayout_flutter/src/render/write_run.dart';

import 'support/fixtures.dart';
import 'support/node_press.dart';

final Json _table = jsonDecode(File('assets/contract/fixtures/actions/action-cases.json').readAsStringSync()) as Json;
final Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Json;

List<Json> _rows(String key) => (_table[key]! as List<Object?>).cast<Json>();

/// `{ "repeat": { prefix, char, length } }` in place of a string -- a string of the stated length.
Object? _materialize(Object? value) {
  if (value is Map) {
    if (value.length == 1 && value.containsKey('repeat')) {
      final repeat = asJson(value['repeat']);
      final prefix = repeat['prefix']! as String;
      return prefix + (repeat['char']! as String) * ((repeat['length']! as int) - prefix.length);
    }
    return <String, Object?>{for (final entry in value.entries) entry.key as String: _materialize(entry.value)};
  }
  if (value is List) return <Object?>[for (final item in value) _materialize(item)];
  return value;
}

ButtonAction _actionOf(Json row) => ButtonAction.parse(_materialize(row['action']));

/// What the host would hear for [step]: nothing, or `[path, value]`.
List<Object?>? _hostHears(WriteStep? step) {
  final heard = <List<Object?>>[];
  if (step != null) runWriteStep(step, write: (path, value) => heard.add([path, value]));
  return heard.isEmpty ? null : heard.single;
}

String _kindOf(WriteStep step) => switch (step) {
  WriteNow() => 'write',
  WriteSame() => 'same-value',
  WriteInvalid() => 'invalid',
};

void main() {
  test('the table has the promised rows, with names that are unique inside a group', () {
    final counts = {
      'writeCases': 67,
      'writeControlCases': 22,
      'writeSchemaCases': 14,
      'writeDocumentCases': 47,
      'writeTreeCases': 11,
      'writePressCases': 15,
    };
    counts.forEach((key, count) {
      expect(_rows(key), hasLength(count), reason: key);
      final names = _rows(key).map((row) => row['name']).toList();
      expect(names.toSet(), hasLength(names.length), reason: key);
    });
  });

  group('writeCases: what a press does with the data under the path', () {
    for (final row in _rows('writeCases')) {
      test(row['name']! as String, () {
        final data = asJson(row['data']);
        final step = writeStepOf(_actionOf(row), (path) => data[path]);
        final expected = row['step'];
        if (expected == null) {
          expect(step, isNull, reason: 'not a write action');
        } else {
          final want = asJson(_materialize(expected));
          expect(step, isNotNull);
          expect(_kindOf(step!), want['kind']);
          switch (step) {
            case WriteNow(:final path, :final value) || WriteSame(:final path, :final value):
              expect(path, want['path']);
              expect(value, want['value']);
              // The type of the value is part of the answer: `7` is not `7.0`, `"7"` is not `7`.
              expect(value.runtimeType == want['value'].runtimeType || (value is num && want['value'] is num), isTrue);
            case WriteInvalid(:final problem):
              expect(problem.wire, want['problem']);
          }
        }
        // The host: refused paths and repeated values reach nobody.
        expect(_hostHears(step), _materialize(row['host']), reason: 'host${row['gate'] == null ? '' : ' (gate: ${row['gate']})'}');
      });
    }

    test('a write action never reads the path or the value from data', () {
      for (final row in _rows('writeCases').where((row) => asJson(row['action']).containsKey('paramBindings'))) {
        final action = _actionOf(row);
        final everything = {for (final entry in asJson(row['data']).entries) entry.key: entry.value};
        final step = writeStepOf(action, (path) => everything[path]);
        // Without the bindings the result is the same: they are not read at all.
        final bare = ButtonAction(action.type, action.params);
        expect(_kindOf(writeStepOf(bare, (path) => everything[path])!), _kindOf(step!), reason: row['name']! as String);
      }
    });
  });

  group('writeControlCases: option, toggle or a plain button', () {
    for (final row in _rows('writeControlCases')) {
      test(row['name']! as String, () {
        final data = asJson(row['data']);
        final control = writeControlOf(_actionOf(row), (path) => data[path]);
        final expected = row['control'];
        if (expected == null) {
          expect(control, isNull);
        } else {
          final want = asJson(expected);
          expect(control, isNotNull);
          expect(control!.role.name == 'option' ? 'option' : 'toggle', want['role']);
          expect(control.path, want['path']);
          expect(control.on, want['on']);
        }
      });
    }
  });

  group('writeSchemaCases, writeDocumentCases: the reader reads every action without a crash', () {
    for (final row in [..._rows('writeSchemaCases'), ..._rows('writeDocumentCases')]) {
      test(row['name']! as String, () {
        final action = _actionOf(row);
        expect(() => writeStepOf(action, (_) => null), returnsNormally);
        expect(() => writeControlOf(action, (_) => null), returnsNormally);
        expect(action.handOver((_) => null).type, action.type);
      });
    }

    test('a parameter that is not a text is "no parameter" (the schema rows with a number, a flag, null, a list)', () {
      for (final row in _rows('writeSchemaCases').where((row) => row['valid'] == false)) {
        final params = asJson(asJson(row['action'])['params'] ?? const <String, Object?>{});
        final action = _actionOf(row);
        for (final name in [kWritePathParam, kWriteValueParam, kWriteValueTypeParam]) {
          final raw = params[name];
          if (raw != null && raw is! String && raw is! Map) {
            expect(action.params.containsKey(name), isFalse, reason: '${row['name']}: $name');
          }
        }
      }
    });

    test('where the builder names a parameter unusable, the reader writes nothing with it', () {
      var checked = 0;
      for (final row in _rows('writeDocumentCases')) {
        final issues = (row['issues']! as List<Object?>).cast<Json>().where((issue) => issue['code'] == 'invalid_action_param');
        final step = writeStepOf(_actionOf(row), (_) => null);
        if (issues.isEmpty) {
          // Publishable (or only mistyped for the builder): the reader has no quarrel with it.
          final stepsOnly = (row['issues']! as List<Object?>).cast<Json>().every((issue) => issue['code'] != 'invalid_action_param');
          if (stepsOnly) expect(step, isNot(isA<WriteInvalid>()), reason: row['name']! as String);
          continue;
        }
        checked += 1;
        final at = ((issues.first['at']! as List<Object?>).last) as String;
        final action = _actionOf(row);
        switch (at) {
          case 'path':
            expect(step, isA<WriteInvalid>(), reason: row['name']! as String);
          case 'valueType':
            expect((step! as WriteInvalid).problem, WriteProblem.unknownValueType, reason: row['name']! as String);
          default:
            // A value the builder does not publish: the reader refuses what is no flag or no number at all, and
            // reads the looser number spellings (a comma, other digits, spaces, `7.0`) the way a number field does.
            final type = action.params[kWriteValueTypeParam];
            if (step is WriteInvalid) {
              expect(const [WriteProblem.notAFlag, WriteProblem.notANumber], contains(step.problem), reason: row['name']! as String);
            } else {
              expect(type, 'number', reason: '${row['name']}: only a number has a looser spelling the reader accepts');
            }
        }
      }
      expect(checked, greaterThan(10));
    });
  });

  group('writeTreeCases: the nodes are read and drawn without a crash', () {
    for (final row in _rows('writeTreeCases')) {
      testWidgets(row['name']! as String, (tester) async {
        await pumpDocument(tester, docWith((_materialize(row['nodes'])! as List<Object?>).cast<Json>()));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('writePressCases: a real press on a real screen', () {
    for (final row in _rows('writePressCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final semantics = tester.ensureSemantics();
        final nodes = (row['nodes']! as List<Object?>).cast<Json>();
        final log = <List<Object?>>[];
        final handed = <String>[];
        await pumpDocument(
          tester,
          docWith(nodes),
          onTrack: (event, nodeId, record) => log.add(['track', event.event]),
          onWrite: (path, value) => log.add(['write', path, value]),
          onAction: (action, nodeId) => handed.add(action.type),
          onRecordAction: (action, nodeId, record) => handed.add(action.type),
        );
        for (final press in (row['presses']! as List<Object?>).cast<Json>()) {
          final target = finderOfNodeJson(findNodeJson(nodes, press['node']! as String)!);
          switch (press['how']) {
            case 'tap':
              await tester.tap(target, warnIfMissed: false);
            case 'enter':
              await focusWithTab(tester, target);
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            case 'space':
              await focusWithTab(tester, target);
              await tester.sendKeyEvent(LogicalKeyboardKey.space);
            case 'enter-held':
              await focusWithTab(tester, target);
              await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
              for (var repeat = 0; repeat < 4; repeat += 1) {
                await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
              }
              await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
            default:
              fail('unknown press ${press['how']}');
          }
          await tester.pump();
        }
        expect(log, _materialize(row['log']), reason: 'the host hears the event first, then the write');
        // The session after the presses is what the last write of each path left.
        final session = <String, Object?>{for (final entry in log.where((entry) => entry.first == 'write')) entry[1]! as String: entry[2]};
        expect(session, row['session']);
        expect(handed, isEmpty, reason: 'a write action never reaches onAction');
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  });

  group('mirror of the artifact', () {
    final write = asJson(asJson(_schema['x-actions'])['write']);

    test('x-actions.write: names, limits and words', () {
      expect(asJson(write['types']), {'set': kSetValueActionType, 'toggle': kToggleValueActionType});
      expect(asJson(write['path'])['maxLength'], kWritePathMaxLength);
      expect(asJson(write['path'])['param'], kWritePathParam);
      final value = asJson(write['value']);
      expect(value['param'], kWriteValueParam);
      expect(value['typeParam'], kWriteValueTypeParam);
      expect(value['types'], kWriteValueTypes);
      expect(value['defaultType'], kWriteDefaultValueType);
      expect(asJson(value['boolean'])['words'], kWriteFlagWords);
      expect(asJson(value['number'])['publishedPattern'], kWriteNumberPublishedPatternSource);
      expect(write['problems'], WriteProblem.values.map((problem) => problem.wire));
      expect(write['ignoredFields'], ['paramBindings', 'carryRecord']);
      expect(write['order'], ['track', 'write']);
      expect(asJson(write['host'])['onAction'], 'not-called');
    });

    test('x-actions.catalog: the two reader actions and their forms', () {
      final catalog = (asJson(_schema['x-actions'])['catalog']! as List<Object?>).cast<Json>();
      expect(catalog.map((entry) => entry['type']), kActionCatalog.map((entry) => entry.type));
      for (final type in [kSetValueActionType, kToggleValueActionType]) {
        expect(catalogActionOf(type)!.executor, ActionExecutor.reader);
        final entry = catalog.firstWhere((candidate) => candidate['type'] == type);
        expect(entry['executor'], 'reader');
      }
    });
  });
}
