/// The live record of a page (schema 9.27.0, `x-liveRecord`): the shared groups `entitySourceCases`, `liveRecordCases`
/// and `liveFlowCases` of `fixtures/scope/record-scope-cases.json` run through the rule and through a real
/// `ScreenFlow` fed new data, and then what the table cannot say: the page keeps its scroll and its typed text, the
/// stack and the events stay, the host is handed the refreshed record, and a changed number counts to its new value.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart' show ScreenFlowController;
import 'package:hotlayout_flutter/src/model/live_record.dart';
import 'package:hotlayout_flutter/src/model/record_scope.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _table = jsonDecode(File('assets/contract/fixtures/scope/record-scope-cases.json').readAsStringSync()) as _Json;
final _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

_Json? _mapOrNull(Object? value) => value == null ? null : (value as Map<Object?, Object?>).cast<String, Object?>();

/// The roots a document with these lists has: one `Repeater` per list, in the order of the table.
List<_Json> _rootsOf(List<_Json> lists) => [
  {
    'type': 'Screen',
    'children': [
      for (final list in lists)
        {'type': 'Repeater', 'props': {'source': list['source'], 'item': list['item']}, 'children': [<String, Object?>{'type': 'Text'}]},
    ],
  },
];

RecordChain _chainOf(Object? raw) => [
  for (final link in (raw! as List<Object?>).cast<_Json>())
    RecordLink(source: link['source']! as String, item: link['item']! as String, fields: link['fields']),
];

Object? Function(String source) _lookupIn(Object? collections) {
  final map = _mapOrNull(collections) ?? const {};
  return (source) => map[source];
}

void main() {
  group('the table', () {
    test('is read in full', () {
      expect(_rows('entitySourceCases'), hasLength(3));
      expect(_rows('liveRecordCases'), hasLength(23));
      expect(_rows('liveFlowCases'), hasLength(6));
      expect(_table['liveRecordNote'], isA<String>());
    });

    test('x-liveRecord: the scalar rows of the block are the ones in code', () {
      final block = _schema['x-liveRecord']! as _Json;
      for (final entry in kLiveRecordRules.entries) {
        expect(block[entry.key], entry.value, reason: entry.key);
      }
      expect((block['key']! as _Json)['path'], '<item>.$kLiveRecordKeyField');
      expect((block['key']! as _Json)['field'], kLiveRecordKeyField);
      expect((block['search']! as _Json)['order'], ['source', 'entity']);
      expect(block['cases'], 'contract/fixtures/scope/record-scope-cases.json (liveRecordCases, liveFlowCases)');
    });
  });

  group('entitySourceCases: which collections carry an entity, by the document', () {
    for (final row in _rows('entitySourceCases')) {
      test(row['name']! as String, () {
        final screens = (row['screens']! as List<Object?>).toList();
        final expected = (row['expected']! as _Json).map((key, value) => MapEntry(key, (value! as List<Object?>).cast<String>()));
        expect(entitySourcesOf(screens), expected);
      });
    }
  });

  group('liveRecordCases: the chain of a frame follows the data', () {
    for (final row in _rows('liveRecordCases')) {
      test(row['name']! as String, () {
        final sources = entitySourcesOf(_rootsOf((row['lists']! as List<Object?>).cast<_Json>()));
        var chain = _chainOf(row['chain']);
        for (final update in (row['updates']! as List<Object?>).cast<_Json>()) {
          final next = refreshRecordChain(chain, _lookupIn(update['collections']), sources);
          final record = recordOfChain(next);
          expect(record, _mapOrNull(update['record']));
          // `same`: nothing changed, and the reader keeps the very frame it has.
          expect(identical(next, chain), update['same'] == true, reason: 'same');
          chain = next;

          final read = _mapOrNull(update['read']);
          if (read != null) {
            final found = readLayered({'record': record, 'session': _mapOrNull(read['session'])}, read['path']! as String);
            expect(found?.value, read['value']);
            expect(found?.layer, read['layer']);
          }
        }
      });
    }
  });

  group('the key of a record', () {
    test('a non-empty string or a finite number, by the short name or by the full path', () {
      expect(liveKeyOf('task', {'id': 'walk'}), 'walk');
      expect(liveKeyOf('task', {'task.id': 'walk'}), 'walk');
      expect(liveKeyOf('task', {'id': 7}), 7);
      expect(liveKeyOf('task', {'id': 7.5}), 7.5);
      for (final bad in [null, '', true, double.nan, double.infinity, <String, Object?>{}, <Object?>[]]) {
        expect(liveKeyOf('task', {'id': bad}), isNull, reason: '$bad');
      }
      expect(liveKeyOf('task', {'title': 'x'}), isNull);
      expect(liveKeyOf('task', 'not a map'), isNull);
    });

    test('a hostile field never reaches the record, and a hostile id is only a value', () {
      final sources = entitySourcesOf(_rootsOf([{'source': 'tasks', 'item': 'task'}]));
      final chain = [const RecordLink(source: 'tasks', item: 'task', fields: {'id': '__proto__', 'title': 'a'})];
      final next = refreshRecordChain(chain, _lookupIn({'tasks': [{'id': '__proto__', 'title': 'b', '__proto__': {'x': 1}, 'constructor': 'c'}]}), sources);
      expect(recordOfChain(next), {'task.id': '__proto__', 'task.title': 'b'});
    });

    test('a thousand records are looked through once, in order, without copying them', () {
      final records = [for (var i = 0; i < 5000; i += 1) <String, Object?>{'id': 'r$i', 'n': i}];
      final sources = entitySourcesOf(_rootsOf([{'source': 'tasks', 'item': 'task'}]));
      var chain = [const RecordLink(source: 'tasks', item: 'task', fields: {'id': 'r4999', 'n': 0})];
      chain = refreshRecordChain(chain, _lookupIn({'tasks': records}), sources);
      expect(recordOfChain(chain), {'task.id': 'r4999', 'task.n': 4999});
      expect(identical(chain.single.fields, records.last), isTrue, reason: 'the found record itself, not a copy');
    });
  });

  group('liveFlowCases: with a real ScreenFlow, real taps, new data', () {
    // The document of a case: on the screen where a step is made there is that step's button, bare or inside a chain
    // of lists, one record in each; a "probe" button on every screen sends the record the screen holds to the host.
    ({UiDocument document, Map<String, Object?> data}) documentFor(_Json row) {
      final screens = (row['screens']! as _Json).cast<String, String>();
      final data = <String, Object?>{};
      final children = <String, List<_Json>>{
        for (final screenId in screens.keys)
          screenId: [
            buttonNode('probe $screenId', action: {'type': 'probe'}, id: 'probe-$screenId'),
          ],
      };
      var stack = <String>[row['start']! as String];
      final steps = (row['steps']! as List<Object?>).cast<_Json>();
      for (var index = 0; index < steps.length; index += 1) {
        final step = steps[index];
        final screenId = stack.last;
        if (step['do'] != 'data') {
          _Json button = buttonNode('step $index', action: switch (step['do']) {
            'navigate' => {
              'type': 'navigate',
              'params': {'screenId': step['to']},
              if (step['carryRecord'] == true) 'carryRecord': true,
            },
            _ => {'type': 'navigate.back'},
          }, id: 'step-$index');
          final instances = (step['instances']! as List<Object?>).cast<_Json>();
          for (var depth = instances.length - 1; depth >= 0; depth -= 1) {
            final source = instances[depth]['source']! as String;
            data[source] ??= [instances[depth]['fields']];
            button = {
              'id': 'list-$index-$depth',
              'type': 'Repeater',
              'props': {'source': source, 'item': instances[depth]['item'], 'direction': 'column', 'gap': 'none'},
              'children': [button],
            };
          }
          children[screenId]!.add(button);
        }
        stack = ((step['expect']! as _Json)['stack']! as List<Object?>).cast<String>();
      }
      // The lists the document names without a button in them (the other collection of an entity).
      final first = row['start']! as String;
      for (final list in (row['lists']! as List<Object?>).cast<_Json>()) {
        children[first]!.add({
          'id': 'names-${list['source']}',
          'type': 'Repeater',
          'props': {'source': list['source'], 'item': list['item'], 'direction': 'column', 'gap': 'none'},
          'children': [{'id': 'spacer-${list['source']}', 'type': 'Spacer', 'props': <String, Object?>{}}],
        });
      }
      final document = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'live-case',
        'name': 'case',
        'initialScreenId': row['start'],
        'screens': [
          for (final entry in screens.entries)
            screenEntry(entry.key, children[entry.key]!, presentation: entry.value == 'modal' ? 'modal' : null),
        ],
      });
      return (document: document, data: data);
    }

    for (final row in _rows('liveFlowCases')) {
      testWidgets(row['name']! as String, (tester) async {
        tester.view.physicalSize = const Size(390, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final (:document, :data) = documentFor(row);
        final controller = ScreenFlowController();
        addTearDown(controller.dispose);
        final calls = <({String type, String nodeId, Map<String, Object?>? record})>[];
        final shown = <String>[];

        Future<void> pump(Map<String, Object?> hostData) => pumpDocument(
          tester,
          document,
          data: hostData,
          controller: controller,
          onRecordAction: (action, nodeId, record) => calls.add((type: action.type, nodeId: nodeId, record: record)),
          onScreenShown: (event) => shown.add('${event.cause.name}:${event.screenId}'),
        );

        var hostData = data;
        await pump(hostData);
        await tester.pumpAndSettle();

        final steps = (row['steps']! as List<Object?>).cast<_Json>();
        for (var index = 0; index < steps.length; index += 1) {
          final step = steps[index];
          final expected = step['expect']! as _Json;
          final shownBefore = shown.length;
          if (step['do'] == 'data') {
            hostData = (step['collections']! as _Json).cast<String, Object?>();
            await pump(hostData);
            await tester.pumpAndSettle();
            expect(shown.length, shownBefore, reason: 'step $index: new data is not a show');
          } else {
            await tester.tap(find.text('step $index'));
            await tester.pumpAndSettle();
            expect(shown.length, shownBefore + 1, reason: 'step $index: one show');
          }
          final stack = (expected['stack']! as List<Object?>).cast<String>();
          expect(controller.currentScreenId, stack.last, reason: 'step $index: top screen');
          expect(controller.canGoBack, stack.length > 1, reason: 'step $index: stack depth');
          // The record of EVERY frame of the stack, bottom first - also the ones that are not painted.
          final records = (expected['records']! as List<Object?>).map(_mapOrNull).toList();
          expect(controller.frameRecords, records, reason: 'step $index: the records of the frames');

          // The host is handed the same record the top frame holds.
          await tester.tap(find.text('probe ${stack.last}'));
          await tester.pumpAndSettle();
          expect(calls.last.type, 'probe', reason: 'step $index: probe');
          expect(calls.last.record, records.last, reason: 'step $index: the record the host gets');
        }
      });
    }
  });

  group('the page stays where it is', () {
    UiDocument page() => docWithScreens([
      screenEntry('list', [
        {
          'id': 'rows',
          'type': 'Repeater',
          'props': {'source': 'missions', 'item': 'mission', 'direction': 'column', 'gap': 'none'},
          'children': [
            {
              'id': 'row',
              'type': 'ListTile',
              'props': {
                'leading': {'kind': 'none'},
                'trailing': {'kind': 'none'},
                'title': {'kind': 'binding', 'path': 'mission.title', 'fallback': ''},
                'action': {'type': 'navigate', 'params': {'screenId': 'mission'}},
              },
            },
          ],
        },
      ]),
      screenEntry('mission', [
        {
          'id': 'count',
          'type': 'Text',
          'props': {'content': {'kind': 'binding', 'path': 'mission.progress', 'fallback': '-'}, 'animateChanges': true},
        },
        {
          'id': 'field',
          'type': 'TextField',
          'props': {'label': {'kind': 'literal', 'value': 'Note'}, 'value': {'kind': 'binding', 'path': 'draft.note', 'fallback': ''}},
        },
        {
          'id': 'pay',
          'type': 'Button',
          'props': {'label': {'kind': 'literal', 'value': 'Pay'}, 'variant': 'primary', 'action': {'type': 'pay'}},
        },
      ]),
    ], initialScreenId: 'list');

    Map<String, Object?> missions(int progress, {String title = 'Five rides'}) => {
      'missions': [
        {'id': 'ride', 'title': title, 'progress': progress},
      ],
    };

    testWidgets('typed text, the stack and the events stay; the number counts to its new value; the host gets the new record', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final doc = page();
      final seen = <Map<String, Object?>?>[];
      final shown = <String>[];
      Future<void> pump(Map<String, Object?> data) => pumpDocument(
        tester,
        doc,
        data: data,
        onRecordAction: (action, nodeId, record) => seen.add(record),
        onScreenShown: (event) => shown.add(event.cause.name),
      );

      await pump(missions(100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Five rides'));
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'my note');
      await tester.pump();
      shown.clear();

      await pump(missions(300));
      await tester.pump(const Duration(milliseconds: 100));
      final number = find.byWidgetPredicate((widget) => widget is Text && RegExp(r'^\d+$').hasMatch(widget.data ?? ''));
      final middle = int.parse(tester.widget<Text>(number.first).data!);
      expect(middle, inInclusiveRange(101, 299), reason: 'a changed number counts, as any changed value does');
      await tester.pumpAndSettle();
      expect(find.text('300'), findsOneWidget);
      expect(find.text('my note'), findsOneWidget, reason: 'the typed text stays');
      expect(shown, isEmpty, reason: 'new data is not a show');

      await tester.tap(find.text('Pay'));
      await tester.pump();
      expect(seen.last, {'mission.id': 'ride', 'mission.title': 'Five rides', 'mission.progress': 300});
    });

    testWidgets('a record that left the data keeps the last one the page had; it is not emptied', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final doc = page();
      await pumpDocument(tester, doc, data: missions(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Five rides'));
      await tester.pumpAndSettle();
      await pumpDocument(tester, doc, data: const {'missions': <Object?>[]});
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      // And the next time it appears, it is found again.
      await pumpDocument(tester, doc, data: missions(4));
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('a new object with the same records changes nothing: the frame is the same one', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final doc = page();
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      await pumpDocument(tester, doc, data: missions(3), controller: controller);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Five rides'));
      await tester.pumpAndSettle();
      final before = controller.frameRecords.last;
      await pumpDocument(tester, doc, data: missions(3), controller: controller);
      await tester.pump();
      expect(identical(controller.frameRecords.last, before), isTrue);
    });

    testWidgets('a page opened without a row has no record to follow, and the data does not give it one', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final doc = docWithScreens([
        screenEntry('list', [buttonNode('Open', action: {'type': 'navigate', 'params': {'screenId': 'plain'}}, id: 'open')]),
        screenEntry('plain', [textNode('x', id: 'plain-text')]),
      ], initialScreenId: 'list');
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      await pumpDocument(tester, doc, data: missions(3), controller: controller);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await pumpDocument(tester, doc, data: missions(4), controller: controller);
      await tester.pumpAndSettle();
      expect(controller.frameRecords, [null, null]);
    });
  });
}
