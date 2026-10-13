/// Which record the screen opened from a list row sees (schema 9.2.0).
///
/// Four implementations hold this rule: the contract reference, the builder preview, the
/// mirror in `@hotlayout/react`, and this one. Before 9.2.0 each answered in its own way
/// and they never disagreed, because the contract was silent. Now the examples are DATA
/// (`assets/contract/fixtures/scope/record-scope-cases.json`), and here they are run row by
/// row through three layers, none of which replaces the others:
///
///  1. LAYERS and RECORD SCOPE - pure functions and `ScreenData`;
///  2. FLOWS - `testWidgets` with a real `ScreenFlow`: the document for each case is
///     BUILT from the table, steps are real taps, and the screen record and the record the
///     host received are captured as the host sees them;
///  3. the policy MIRROR - eight rows and the `x-dataScope` block against the artifact.
///
/// Model: the builder's `scripts/record-scope-cases.test.tsx` (function `documentFor`). A
/// test that checked the markup against itself would catch nothing here: before 9.2.0 the
/// rows in `testWidgets` were two separate nodes with different literals, not instances of
/// ONE template - so "two different rows give two different tasks" passed while the host
/// did not see the record at all.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/record_scope.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _readJson(String path) => jsonDecode(File(path).readAsStringSync()) as _Json;

final _table = _readJson('assets/contract/fixtures/scope/record-scope-cases.json');
final _schema = _readJson('assets/contract/screen-schema.json');

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

_Json? _mapOrNull(Object? value) => value == null ? null : (value as Map<Object?, Object?>).cast<String, Object?>();

/// The record scope of a node per the table: the screen record and instances, outer first.
Map<String, Object?>? _recordOf(Map<String, Object?>? screenRecord, List<_Json> instances) {
  var record = screenRecord;
  for (final instance in instances) {
    record = overlayRecord(record, instanceRecord(instance['item']! as String, _mapOrNull(instance['fields'])));
  }
  return record;
}

List<_Json> _instances(_Json step) => (step['instances']! as List<Object?>).cast<_Json>();

// ───────────────────────── document for a flow case ─────────────────────────

_Json _node(String type, String id, _Json props, [List<_Json>? children]) => {
  'id': id,
  'type': type,
  'props': props,
  'children': ?children,
};

_Json _actionOf(_Json step) {
  final kind = step['do']! as String;
  return switch (kind) {
    'navigate' => {
      'type': 'navigate',
      'params': {'screenId': step['to']},
      // 9.8.0: the explicit action word is exactly `true`.
      'carryRecord': ?(step['carryRecord'] == true ? true : null),
    },
    'back' => {'type': 'navigate.back'},
    _ => {'type': step['type'] ?? 'submit'},
  };
}

String _stepLabel(int index) => 'step $index';

/// The document for a case: on the screen where the step is made there is that step's
/// button - bare or inside a chain of lists, one record in each. Plus a "probe" button
/// outside the lists on EVERY screen: its action goes to the host and shows the record the
/// screen was opened with.
({UiDocument document, Map<String, Object?> data}) _documentFor(_Json row) {
  final screens = (row['screens']! as _Json).cast<String, String>();
  final data = <String, Object?>{};
  final children = <String, List<_Json>>{
    for (final screenId in screens.keys)
      screenId: [
        _node('Button', 'probe-$screenId', {
          'label': {'kind': 'literal', 'value': 'probe $screenId'},
          'variant': 'primary',
          'fullWidth': true,
          'action': {'type': 'probe'},
        }),
      ],
  };

  var stack = <String>[row['start']! as String];
  final steps = (row['steps']! as List<Object?>).cast<_Json>();
  for (var index = 0; index < steps.length; index += 1) {
    final step = steps[index];
    final screenId = stack.last;
    var button = _node('Button', 'step-$index', {
      'label': {'kind': 'literal', 'value': _stepLabel(index)},
      'variant': 'primary',
      'fullWidth': true,
      'action': _actionOf(step),
    });
    final instances = _instances(step);
    for (var depth = instances.length - 1; depth >= 0; depth -= 1) {
      final source = 'c${index}x$depth';
      data[source] = [instances[depth]['fields']];
      button = _node('Repeater', 'list-$index-$depth', {
        'source': source,
        'item': instances[depth]['item'],
        'direction': 'column',
        'gap': 'none',
      }, [button]);
    }
    children[screenId]!.add(button);
    stack = ((step['expect']! as _Json)['stack']! as List<Object?>).cast<String>();
  }

  final document = UiDocument.fromJson({
    'schemaVersion': kSupportedSchemaVersion,
    'documentId': 'record-scope-case',
    'name': 'case',
    'initialScreenId': row['start'],
    'screens': [
      for (final entry in screens.entries)
        screenEntry(
          entry.key,
          children[entry.key]!,
          presentation: entry.value == 'modal' ? 'modal' : null,
          // 9.9.0: table rows may name the layer placement (a window in the middle).
          modalPlacement: (row['modalPlacement'] as Map<String, Object?>?)?[entry.key],
        ),
    ],
  });
  return (document: document, data: data);
}

void main() {
  group('record scope table: structure', () {
    test('the table is non-empty, names do not repeat, layer order is the one in code', () {
      expect(_rows('readCases').length, greaterThanOrEqualTo(17));
      expect(_rows('recordCases').length, greaterThanOrEqualTo(8));
      expect(_rows('flowCases').length, greaterThanOrEqualTo(12));
      for (final key in ['readCases', 'recordCases', 'flowCases']) {
        final names = _rows(key).map((row) => row['name']).toList();
        expect(names.toSet(), hasLength(names.length), reason: key);
      }
      expect(_table['layerOrder'], kDataLayerOrder);
    });

    /* Scenarios from the task statement: none can vanish from the table silently. */
    for (final name in [
      'a list row opens the details of ITS record',
      'back drops the record; another row opens another record',
      'a button outside the list opens the page without a record',
      'the details screen opened from outside (an entry point): no record',
      'an action of a list row tells the host which record',
      'a button on the details screen tells the host the record the screen was opened with',
      'a modal sheet opened from a row gets the row record',
      'a modal sheet opened by a screen button sees the record of the screen beneath, and tells the host',
      'a page opened by a screen button does NOT inherit: back to the catalog by navigate is a clean catalog',
      'a nested list: the row carries both records, and a row of the next list overlays them',
    ]) {
      test('mandatory scenario: $name', () {
        expect(_rows('flowCases').any((row) => row['name'] == name), isTrue);
      });
    }
  });

  group('data layers (readCases)', () {
    for (final row in _rows('readCases')) {
      test(row['name']! as String, () {
        final layers = (row['layers']! as _Json).map((key, value) => MapEntry(key, _mapOrNull(value)));

        // 1. The pure rule function.
        final found = readLayered(layers, row['path']! as String);
        expect(found?.layer, row['layer'], reason: 'layer');
        expect(found?.value, row['value'], reason: 'value');

        // 2. The same, but through `ScreenData`, which the screen reads with.
        final data = ScreenData.scoped(
          record: layers['record'],
          session: layers['session'] ?? const {},
          scope: layers['host'] ?? const {},
          document: layers['data'] ?? const {},
        );
        expect(data.lookup(row['path']! as String), row['value'], reason: 'ScreenData.lookup');
      });
    }
  });

  group('node record scope (recordCases)', () {
    for (final row in _rows('recordCases')) {
      test(row['name']! as String, () {
        final record = _recordOf(_mapOrNull(row['screenRecord']), _instances(row));
        expect(record, _mapOrNull(row['expected']));

        // The same from the `ScreenData` side: a node in instances sees exactly this scope.
        var data = ScreenData.scoped(record: _mapOrNull(row['screenRecord']));
        for (final instance in _instances(row)) {
          data = data.withItem(instance['item']! as String, instance['fields']);
        }
        expect(data.record, _mapOrNull(row['expected']));
      });
    }
  });

  group('flows (flowCases) - with a real ScreenFlow, real taps', () {
    for (final row in _rows('flowCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final (:document, :data) = _documentFor(row);
        final controller = ScreenFlowController();
        addTearDown(controller.dispose);
        final calls = <({String type, String nodeId, Map<String, Object?>? record})>[];

        await pumpDocument(
          tester,
          document,
          data: data,
          controller: controller,
          onRecordAction: (action, nodeId, record) =>
              calls.add((type: action.type, nodeId: nodeId, record: record)),
        );
        await tester.pumpAndSettle();

        final steps = (row['steps']! as List<Object?>).cast<_Json>();
        for (var index = 0; index < steps.length; index += 1) {
          final step = steps[index];
          final expected = step['expect']! as _Json;
          final before = calls.length;

          await tester.tap(find.text(_stepLabel(index)));
          await tester.pumpAndSettle();

          final stack = (expected['stack']! as List<Object?>).cast<String>();
          expect(controller.currentScreenId, stack.last, reason: 'step $index: top screen');
          expect(controller.canGoBack, stack.length > 1, reason: 'step $index: stack depth');

          // The host gets the record EXACTLY with the action the renderer passed out.
          if (step['do'] == 'host') {
            expect(calls.length, before + 1, reason: 'step $index: the action reached the host');
            expect(calls.last.record, _mapOrNull(expected['hostRecord']), reason: 'step $index: hostRecord');
          } else {
            expect(calls.length, before, reason: 'step $index: ' 'navigate is executed by the renderer, the host does not see it');
          }

          // The record of the screen opened by this step is visible from the probe button outside the list.
          await tester.tap(find.text('probe ${stack.last}'));
          await tester.pumpAndSettle();
          expect(calls.last.type, 'probe', reason: 'step $index: probe');
          expect(calls.last.record, _mapOrNull(expected['record']), reason: 'step $index: screen record');
        }
      });
    }
  });

  group('artifact mirror', () {
    final compatibility = _schema['x-compatibility']! as _Json;
    final policy = compatibility['policy']! as _Json;
    final scope = _schema['x-dataScope']! as _Json;

    test('the eight policy rows match the artifact', () {
      expect(kRecordScopePolicy, hasLength(8));
      for (final entry in kRecordScopePolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
    });

    test('x-dataScope: layers, record sources and "no value" forms', () {
      expect(scope['layers'], kDataLayerOrder);
      expect(scope['recordSources'], kRecordSources);
      expect(scope['absent'], kAbsentForms);
      expect(scope['cases'], 'contract/fixtures/scope/record-scope-cases.json');
      // The policy says the same in words: layer order is their join with `-`.
      expect(policy['dataLayerOrder'], kDataLayerOrder.join('-'));
    });

    test('the recordScope feature is in the catalog with version 9.2.0', () {
      expect(kFeatureCatalog['recordScope'], '9.2.0');
      expect(supportsFeature('recordScope'), isTrue);
      expect(supportsFeature('recordScope', readerVersion: '9.1.0'), isFalse);
      // Reader AT LEAST 9.2: the version is not held as a number here - it grows with
      // every minor (now 9.3.0), and this test's question is the feature itself.
      expect(supportsFeature('recordScope', readerVersion: kSupportedSchemaVersion), isTrue);
    });
  });

  group('policy rows - each separately', () {
    // A list from ONE template (`Repeater` instances, not two nodes with different
    // literals) and a details screen bound to the same paths.
    UiDocument listToDetails({bool modal = false}) => UiDocument.fromJson({
      'schemaVersion': kSupportedSchemaVersion,
      'documentId': 'rows',
      'name': 'rows',
      'initialScreenId': 'list',
      'screens': [
        screenEntry('list', [
          _node('Repeater', 'rows', {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'}, [
            {
              'id': 'row',
              'type': 'ListTile',
              'props': {
                'leading': {'kind': 'none'},
                'title': {'kind': 'binding', 'path': 'item.name', 'fallback': 'Reward'},
                'trailing': {'kind': 'none'},
                'action': {
                  'type': 'navigate',
                  // Template parameters are identical in every instance - which was
                  // why the host could not tell which row was tapped.
                  'params': {'screenId': 'details', 'tag': 'same'},
                },
              },
            },
          ]),
          buttonNode('Open without a row', id: 'plain', action: {
            'type': 'navigate',
            'params': {'screenId': 'details'},
          }),
        ]),
        screenEntry(
          'details',
          [
            textNode('—', id: 'name', extra: {
              'content': {'kind': 'binding', 'path': 'item.name', 'fallback': 'No record'},
            }),
            buttonNode('Redeem', id: 'redeem', action: {'type': 'submit'}),
            buttonNode('Back', id: 'back', action: {'type': 'navigate.back'}),
          ],
          presentation: modal ? 'modal' : null,
        ),
      ],
    });

    const data = {
      'items': [
        {'id': 'headphones', 'name': 'Wireless headphones'},
        {'id': 'backpack', 'name': 'Travel backpack'},
      ],
    };

    testWidgets('actionRecord + navigateFromListItem: a list row carries ITS OWN record', (tester) async {
      // Two instances of ONE template, identical `params`: they can be told apart
      // only by the record. This is where the old "two different rows" test passed in vain.
      final seen = <Map<String, Object?>?>[];
      await pumpDocument(
        tester,
        listToDetails(),
        data: data,
        onRecordAction: (action, nodeId, record) => seen.add(record),
      );

      await tester.tap(find.text('Travel backpack'));
      await tester.pumpAndSettle();
      expect(find.text('Travel backpack'), findsOneWidget);

      await tester.tap(find.text('Redeem'));
      await tester.pumpAndSettle();
      expect(seen.single, {'item.id': 'backpack', 'item.name': 'Travel backpack'});

      // "Back" removes the frame together with its record; another row - another record.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wireless headphones'));
      await tester.pumpAndSettle();
      expect(find.text('Wireless headphones'), findsOneWidget);
      expect(find.text('Travel backpack'), findsNothing);
      await tester.tap(find.text('Redeem'));
      await tester.pumpAndSettle();
      expect(seen.last, {'item.id': 'headphones', 'item.name': 'Wireless headphones'});
    });

    testWidgets('navigateOutsideListItem: a button outside a list opens a page without a record', (tester) async {
      await pumpDocument(tester, listToDetails(), data: {
        ...data,
        'item.name': 'Document item',
      });

      await tester.tap(find.text('Open without a row'));
      await tester.pumpAndSettle();

      // No record: `item.name` is read from the document data.
      expect(find.text('Document item'), findsOneWidget);
    });

    testWidgets('navigateOutsideListItem: a modal layer sees the record of the screen under it', (tester) async {
      final doc = UiDocument.fromJson({
        'schemaVersion': kSupportedSchemaVersion,
        'documentId': 'sheet',
        'name': 'sheet',
        'initialScreenId': 'list',
        'screens': [
          screenEntry('list', [
            _node('Repeater', 'rows', {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'}, [
              buttonNode('open', id: 'open-row', action: {
                'type': 'navigate',
                'params': {'screenId': 'details'},
              }),
            ]),
          ]),
          screenEntry('details', [
            textNode('—', id: 'name', extra: {
              'content': {'kind': 'binding', 'path': 'item.name', 'fallback': 'No record'},
            }),
            buttonNode('Confirm sheet', id: 'ask', action: {
              'type': 'navigate',
              'params': {'screenId': 'sheet'},
            }),
          ]),
          screenEntry('sheet', [
            textNode('—', id: 'sheet-name', extra: {
              'content': {'kind': 'binding', 'path': 'item.name', 'fallback': 'Sheet without record'},
            }),
          ], presentation: 'modal'),
        ],
      });
      await pumpDocument(tester, doc, data: {
        'items': [
          {'id': 'bottle', 'name': 'Bottle'},
        ],
      });

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm sheet'));
      await tester.pumpAndSettle();

      // Two screens at once: details under the sheet and the sheet itself - both about Bottle.
      expect(find.text('Bottle'), findsNWidgets(2));
      expect(find.text('Sheet without record'), findsNothing);
    });

    testWidgets('navigateParams: params are for the host, not screen data', (tester) async {
      final requests = <ScreenScopeRequest>[];
      await pumpDocument(
        tester,
        listToDetails(),
        data: data,
        scopeFor: (request) {
          requests.add(request);
          return const {};
        },
      );
      await tester.tap(find.text('Travel backpack'));
      await tester.pumpAndSettle();

      final request = requests.last;
      // Parameters reached the host as they were, together with `screenId`...
      expect(request.params, {'screenId': 'details', 'tag': 'same'});
      // ...but a row record cannot be named with them: the record is separate.
      expect(request.record, {'item.id': 'backpack', 'item.name': 'Travel backpack'});
      // `read` looks into screen data WITHOUT the host scope, but with the record.
      expect(request.read('item.name'), 'Travel backpack');
      // There is no `params.*` path: it is not data.
      expect(request.read('params.tag'), isNull);
      expect(find.text('Travel backpack'), findsOneWidget);
    });

    testWidgets('entryPoint/start without a record: scopeFor yields record == null', (tester) async {
      final requests = <ScreenScopeRequest>[];
      await pumpDocument(
        tester,
        listToDetails(),
        data: data,
        scopeFor: (request) {
          requests.add(request);
          return const {};
        },
      );
      expect(requests.first.record, isNull);
    });

    testWidgets('compatibility: a host with only onAction works as it used to', (tester) async {
      final seen = <String>[];
      await pumpDocument(
        tester,
        listToDetails(),
        data: data,
        onAction: (action, nodeId) => seen.add('${action.type}:$nodeId'),
      );
      await tester.tap(find.text('Travel backpack'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redeem'));
      await tester.pumpAndSettle();

      expect(seen, ['submit:redeem']);
    });

    testWidgets('when both callbacks are given, the action goes only to onRecordAction', (tester) async {
      final plain = <String>[];
      final withRecord = <String>[];
      await pumpDocument(
        tester,
        listToDetails(),
        data: data,
        onAction: (action, nodeId) => plain.add(nodeId),
        onRecordAction: (action, nodeId, record) => withRecord.add(nodeId),
      );
      await tester.tap(find.text('Travel backpack'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redeem'));
      await tester.pumpAndSettle();

      expect(plain, isEmpty);
      expect(withRecord, ['redeem']);
    });

    testWidgets('the record for the host is an immutable map with path-form keys only', (tester) async {
      final records = <Map<String, Object?>?>[];
      final doc = UiDocument.fromJson({
        'schemaVersion': kSupportedSchemaVersion,
        'documentId': 'safe',
        'name': 'safe',
        'initialScreenId': 'list',
        'screens': [
          screenEntry('list', [
            _node('Repeater', 'rows', {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'}, [
              buttonNode('buy', id: 'buy', action: {'type': 'submit'}),
            ]),
          ]),
        ],
      });
      await pumpDocument(
        tester,
        doc,
        data: {
          'items': [
            {
              'id': 'bottle',
              '__proto__': 'x',
              'constructor': 'y',
              'prototype': 'z',
              'bad key': 'q',
              'price': 0,
              'inStock': false,
              'badge': null,
              'task': {'title': 'Nested', 'progress': 3},
              'tags': ['a', 'b'],
            },
          ],
        },
        onRecordAction: (action, nodeId, record) => records.add(record),
      );
      await tester.tap(find.text('buy'));
      await tester.pump();

      final record = records.single!;
      expect(record, {
        'item.id': 'bottle',
        // `false`, `0` are values, not "absent".
        'item.price': 0,
        'item.inStock': false,
        // The nested map is unrolled into paths; a list is a value.
        'item.task.title': 'Nested',
        'item.task.progress': 3,
        'item.tags': ['a', 'b'],
      });
      expect(record.containsKey('item.badge'), isFalse, reason: 'null - "no value"');
      expect(() => record['item.id'] = 'changed', throwsUnsupportedError);
    });
  });

  group('pickedChoice: the radio on a screen opened from a row', () {
    // The details screen also shows a choice group bound to a path carried by the
    // record ITSELF: `documentValue` reads the record, the session record does not change,
    // and the radio must still switch - while the value under the binding is the same.
    UiDocument doc() => UiDocument.fromJson({
      'schemaVersion': kSupportedSchemaVersion,
      'documentId': 'picked',
      'name': 'picked',
      'initialScreenId': 'list',
      'screens': [
        screenEntry('list', [
          _node('Repeater', 'rows', {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'}, [
            buttonNode('open', id: 'open', action: {
              'type': 'navigate',
              'params': {'screenId': 'details'},
            }),
          ]),
        ]),
        screenEntry('details', [
          choiceGroupNode(
            [
              optionNode('Headphones', optionValue: 'headphones'),
              optionNode('Backpack', optionValue: 'backpack'),
            ],
            value: const {'kind': 'binding', 'path': 'item.selectedId', 'fallback': ''},
          ),
        ]),
      ],
    });

    testWidgets('the human choice is visible, and the record stays the record', (tester) async {
      await pumpDocument(tester, doc(), data: {
        'items': [
          {'selectedId': 'headphones'},
        ],
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      Set<String> selected() => tester
          .widgetList<ChoiceOptionMark>(find.byType(ChoiceOptionMark))
          .where((mark) => mark.selected)
          .map((mark) => mark.optionValue)
          .toSet();
      expect(selected(), {'headphones'});

      await tester.tap(find.text('Backpack'));
      await tester.pumpAndSettle();

      expect(selected(), {'backpack'});
    });
  });
}
