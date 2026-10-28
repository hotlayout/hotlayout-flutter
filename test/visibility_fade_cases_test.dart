/// A node fading in and out when its `visibleIf` changes (schema 9.33.0, `visibilityTransition`, `x-visibilityFade`):
/// the shared table `fixtures/visibility-fade/visibility-fade-cases.json`.
///
/// `curveCases`, `timelineCases`, `pairCases`, `animateCases` and `fieldCases` run through the pure rules
/// (`visibility_fade.dart`) with a clock the test gives. `documentCases` run through node parsing: which nodes the
/// reader fades. `screenCases` run on the REAL finished screen of the frame, with the clock of the pumped frames; the
/// rows after them are the ways a node ends up in a `Stack`, a `Grid`, a list, or in no fade at all.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart' show carouselStateKey;
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/visibility_fade.dart';
import 'package:hotlayout_flutter/src/render/visibility_fade_scope.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table =
      (jsonDecode(File('assets/contract/fixtures/visibility-fade/visibility-fade-cases.json').readAsStringSync())
              as Map)
          .cast<String, Object?>();
  final schema = (jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();

  test('the table is read in full', () {
    expect(rowsOf('curveCases'), hasLength(12));
    expect(rowsOf('timelineCases'), hasLength(9));
    expect(rowsOf('pairCases'), hasLength(2));
    expect(rowsOf('animateCases'), hasLength(4));
    expect(rowsOf('fieldCases'), hasLength(5));
    expect(rowsOf('documentCases'), hasLength(8));
    expect(rowsOf('screenCases'), hasLength(1));
  });

  group('the data of the artifact', () {
    test('`x-visibilityFade` is mirrored whole', () {
      expect(jsonDecode(jsonEncode(kVisibilityFadeRules)), schema['x-visibilityFade']);
    });

    test('the wait of an appearing node is the fade out of a leaving one: a pair is never in the layout together', () {
      expect(kVisibilityFadeInDelayMs, kVisibilityFadeOutMs);
    });

    test('the capability is in the catalog from 9.33.0', () {
      expect(kFeatureCatalog['visibilityFade'], '9.33.0');
      expect(supportsFeature('visibilityFade'), isTrue);
      expect(supportsFeature('visibilityFade', readerVersion: '9.32.0'), isFalse);
    });
  });

  // ──────────────────────────── the pure rules ────────────────────────────

  VisibilityFadeState stateAfter(bool shown, List<_Row> changes, num until) {
    var state = visibilityFadeRest(shown);
    for (final change in changes) {
      final at = (change['at']! as num).toDouble();
      if (at <= until) state = visibilityFadeChange(state, change['shown']! as bool, at, animate: true);
    }
    return state;
  }

  group('the rules', () {
    for (final row in rowsOf('curveCases')) {
      test('curve: ${row['name']}', () {
        final curve = row['curve'] == 'out' ? kVisibilityFadeOutCurve : kVisibilityFadeInCurve;
        expect(cubicBezierAt(curve, (row['x']! as num).toDouble()), closeTo((row['y']! as num).toDouble(), 0.001));
      });
    }

    for (final row in rowsOf('timelineCases')) {
      test('timeline: ${row['name']}', () {
        final changes = (row['changes']! as List<Object?>).cast<_Row>();
        for (final probe in (row['probes']! as List<Object?>).cast<_Row>()) {
          final at = (probe['at']! as num).toDouble();
          final frame = visibilityFadeAt(stateAfter(row['shown']! as bool, changes, at), at);
          expect(frame.phase.name, probe['phase'], reason: 'phase at $at');
          expect(frame.inLayout, probe['inLayout'], reason: 'in the layout at $at');
          expect(frame.interactive, probe['interactive'], reason: 'a control at $at');
          expect(frame.opacity, closeTo((probe['opacity']! as num).toDouble(), 0.001), reason: 'opacity at $at');
        }
      });
    }

    for (final row in rowsOf('pairCases')) {
      test('pair: ${row['name']}', () {
        final at = (row['at']! as num).toDouble();
        final back = row['back'] as num?;
        List<_Row> changesOf(bool to) => [
          {'at': at, 'shown': to},
          if (back != null) {'at': back, 'shown': !to},
        ];
        ({bool leaving, bool appearing})? previous;
        final layoutChanges = <double>[];
        for (final probe in (row['probes']! as List<Object?>).cast<num>()) {
          final leaving = visibilityFadeAt(stateAfter(true, changesOf(false), probe), probe.toDouble()).inLayout;
          final appearing = visibilityFadeAt(stateAfter(false, changesOf(true), probe), probe.toDouble()).inLayout;
          expect(leaving && appearing, isFalse, reason: 'both in the layout at $probe');
          if (previous != null && (previous.leaving != leaving || previous.appearing != appearing)) {
            expect(
              previous.leaving != leaving && previous.appearing != appearing,
              isTrue,
              reason: 'both change together at $probe',
            );
            layoutChanges.add(probe.toDouble());
          }
          previous = (leaving: leaving, appearing: appearing);
        }
        final expected = row['layoutChangesAt'] as num?;
        expect(layoutChanges, expected == null ? isEmpty : [expected.toDouble()]);
      });
    }

    for (final row in rowsOf('animateCases')) {
      test('at once: ${row['name']}', () {
        var start = visibilityFadeRest(row['shown']! as bool);
        var at = 0.0;
        final midway = row['midway'] as _Row?;
        if (midway != null) {
          at = (midway['at']! as num).toDouble();
          start = visibilityFadeChange(start, midway['shown']! as bool, 0, animate: true);
        }
        final frame = visibilityFadeAt(visibilityFadeChange(start, row['to']! as bool, at, animate: false), at);
        expect(frame.phase.name, row['phase']);
        expect(frame.inLayout, row['inLayout']);
        expect(frame.opacity, (row['opacity']! as num).toDouble());
      });
    }

    for (final row in rowsOf('fieldCases')) {
      test('field: ${row['name']}', () {
        expect(readsVisibilityFade(row['value']) ? 'fade' : null, row['reads']);
      });
    }
  });

  // ─────────────────────────── which nodes fade ───────────────────────────

  const condition = {'path': 'account.cardIndex', 'op': 'eq', 'value': 0};

  /// The nodes of a screen root, parsed by the reader; whether [id] fades.
  bool fades(List<_Row> children, String id) {
    ChildNode? find(List<ChildNode> nodes) {
      for (final node in nodes) {
        if (node.id == id) return node;
        final inner = find(node.children);
        if (inner != null) return inner;
      }
      return null;
    }

    final node = find(UiDocumentBuilder.bare(children).initialScreen.root.children);
    expect(node, isNotNull, reason: id);
    return fadesOnChange(node!);
  }

  _Row textNode(String id, {Object? field = 'fade', bool conditioned = true, Object? pin}) => {
    'id': id,
    'type': 'Text',
    'props': {
      'content': {'kind': 'literal', 'value': id},
    },
    if (conditioned) 'visibleIf': condition,
    'visibilityTransition': ?field,
    'pin': ?pin,
  };

  _Row bar(String id) => {
    'id': id,
    'type': 'AppBar',
    'props': {
      'title': {'kind': 'literal', 'value': id},
    },
    'visibleIf': condition,
    'visibilityTransition': 'fade',
    'children': const <_Row>[],
  };

  group('documentCases: which nodes the reader fades', () {
    for (final row in rowsOf('documentCases')) {
      if (row['root'] == true) continue;
      test(row['name']! as String, () {
        final spec = (row['node']! as _Row);
        final type = spec['type']! as String;
        final first = spec['first'] == true;
        final node = <String, Object?>{
          'id': 'n',
          'type': type,
          'props': type == 'AppBar'
              ? {
                  'title': {'kind': 'literal', 'value': 'n'},
                }
              : {
                  'content': {'kind': 'literal', 'value': 'n'},
                  'direction': 'column',
                  'gap': 'none',
                },
          if (spec['visibleIf'] == true) 'visibleIf': condition,
          'visibilityTransition': spec['visibilityTransition'],
          'pin': ?spec['pin'],
          if (type == 'Container') 'children': const <_Row>[],
        };
        final body = textNode('body', field: null, conditioned: false);
        final reads = row['schema'] == true && row['publishes'] == true;
        expect(fades(first ? [node, body] : [body, node], 'n'), reads);
      });
    }

    test('a pinned node of the other word fades no more than the bottom one: any pin is a zone', () {
      expect(fades([textNode('n', pin: 'top')], 'n'), isFalse);
      expect(fades([textNode('n', pin: 'bottom')], 'n'), isFalse);
      expect(fades([textNode('n', pin: 'left')], 'n'), isFalse);
    });

    test('an app bar that is not the first child of the root is no zone: it fades', () {
      expect(fades([textNode('body', field: null, conditioned: false), bar('n')], 'n'), isTrue);
    });

    test('the first child of the root that is an app bar is a zone', () {
      expect(fades([bar('n'), textNode('body', field: null, conditioned: false)], 'n'), isFalse);
    });

    test('a navigation bar and its item are zones', () {
      final nav = {
        'id': 'nav',
        'type': 'NavBar',
        'props': const <String, Object?>{},
        'visibleIf': condition,
        'visibilityTransition': 'fade',
        'children': [
          {
            'id': 'item',
            'type': 'NavItem',
            'props': {
              'label': {'kind': 'literal', 'value': 'Home'},
              'icon': 'house',
              'action': {'type': 'none'},
            },
            'visibleIf': condition,
            'visibilityTransition': 'fade',
          },
        ],
      };
      expect(fades([textNode('body', field: null, conditioned: false), nav], 'nav'), isFalse);
      expect(fades([textNode('body', field: null, conditioned: false), nav], 'item'), isFalse);
    });

    test('a tab of `Tabs` is not faded: the open one follows its condition at once', () {
      final tabs = {
        'id': 'tabs',
        'type': 'Tabs',
        'props': const <String, Object?>{},
        'children': [
          {
            'id': 'tab',
            'type': 'Tab',
            'props': {
              'title': {'kind': 'literal', 'value': 'One'},
            },
            'visibleIf': condition,
            'visibilityTransition': 'fade',
            'children': const <_Row>[],
          },
        ],
      };
      expect(fades([tabs], 'tab'), isFalse);
    });
  });

  // ───────────────────────── the real finished screen ─────────────────────────

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  FadeBook bookOf(WidgetTester tester) => tester.widget<FadeBox>(find.byType(FadeBox).first).book;
  Finder boxOf(String id) =>
      find.byWidgetPredicate((w) => w is FadeBox && w.entryKey == carouselStateKey(id, const []));

  /// The phase of a node as the screen shows it: no box and not in the layout is `hidden` or `waiting`, which the
  /// book tells apart.
  String phaseOn(WidgetTester tester, String id) {
    final phase = bookOf(tester).frameOf(carouselStateKey(id, const [])).phase;
    final present = boxOf(id).evaluate().isNotEmpty;
    expect(present, visibilityFadeInLayout(phase), reason: '$id: in the tree only while in the layout');
    return phase.name;
  }

  group('screenCases: the finished screen of the frame', () {
    for (final row in rowsOf('screenCases')) {
      testWidgets(row['name']! as String, (tester) async {
        phone(tester);
        await pumpDocument(tester, loadFixture('visibility-fade-screens'), data: const {'account.cardIndex': 0});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(ValueKey('sdui-press-${row['press']}@')).first);
        var now = 0;
        for (final probe in (row['probes']! as List<Object?>).cast<_Row>()) {
          final at = (probe['at']! as num).toInt();
          await tester.pump(Duration(milliseconds: at - now));
          now = at;
          for (final phase in VisibilityFadePhase.values) {
            for (final id in ((probe[phase.name] as List<Object?>?) ?? const []).cast<String>()) {
              expect('$id at $at: ${phaseOn(tester, id)}', '$id at $at: ${phase.name}');
            }
          }
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a leaving node catches no press, takes no focus and is not heard; an entering one is a control', (
      tester,
    ) async {
      phone(tester);
      await pumpDocument(tester, loadFixture('visibility-fade-screens'), data: const {'account.cardIndex': 0});
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sdui-press-dot-1@')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      IgnorePointer pointerOf(String id) =>
          tester.widget<IgnorePointer>(find.descendant(of: boxOf(id), matching: find.byType(IgnorePointer)).first);
      expect(pointerOf('details-debit').ignoring, isTrue);
      ExcludeSemantics hiddenFrom(String id) => tester.widget<ExcludeSemantics>(
        find.descendant(of: boxOf(id), matching: find.byType(ExcludeSemantics)).first,
      );
      ExcludeFocus focusOf(String id) =>
          tester.widget<ExcludeFocus>(find.descendant(of: boxOf(id), matching: find.byType(ExcludeFocus)).first);
      expect(hiddenFrom('details-debit').excluding, isTrue, reason: 'a leaving node is out of the accessibility tree');
      expect(focusOf('details-debit').excluding, isTrue);
      expect(find.text('Coffee · −₴85'), findsOneWidget, reason: 'but it still stands in the layout');
      await tester.pump(const Duration(milliseconds: 121));
      expect(pointerOf('details-credit').ignoring, isFalse);
      expect(hiddenFrom('details-credit').excluding, isFalse);
      expect(focusOf('details-credit').excluding, isFalse);
      expect(
        tester
            .widget<Opacity>(find.descendant(of: boxOf('details-credit'), matching: find.byType(Opacity)).first)
            .opacity,
        lessThan(1),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Opacity>(find.descendant(of: boxOf('details-credit'), matching: find.byType(Opacity)).first)
            .opacity,
        1,
      );
    });

    testWidgets('the first show stands at rest: no transition runs and the ticker is idle', (tester) async {
      phone(tester);
      await pumpDocument(tester, loadFixture('visibility-fade-screens'), data: const {'account.cardIndex': 0});
      expect(tester.hasRunningAnimations, isFalse);
      expect(phaseOn(tester, 'details-debit'), 'shown');
      expect(phaseOn(tester, 'details-credit'), 'hidden');
    });

    testWidgets('"disable animations": at once', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        loadFixture('visibility-fade-screens'),
        data: const {'account.cardIndex': 0},
        disableAnimations: true,
      );
      await tester.tap(find.byKey(const ValueKey('sdui-press-dot-1@')).first);
      await tester.pump();
      expect([phaseOn(tester, 'details-debit'), phaseOn(tester, 'details-credit')], ['hidden', 'shown']);
    });

    testWidgets('a change of the language puts the node at rest of its new condition', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        loadFixture('visibility-fade-screens'),
        data: const {'account.cardIndex': 0},
        locale: 'en',
      );
      await pumpDocument(
        tester,
        loadFixture('visibility-fade-screens'),
        data: const {'account.cardIndex': 1},
        locale: 'uk',
      );
      expect([phaseOn(tester, 'details-debit'), phaseOn(tester, 'details-credit')], ['hidden', 'shown']);
    });

    testWidgets('a change of the data without a gesture fades the same: the data is the condition', (tester) async {
      phone(tester);
      await pumpDocument(tester, loadFixture('visibility-fade-screens'), data: const {'account.cardIndex': 0});
      await pumpDocument(tester, loadFixture('visibility-fade-screens'), data: const {'account.cardIndex': 1});
      expect([phaseOn(tester, 'details-debit'), phaseOn(tester, 'details-credit')], ['leaving', 'waiting']);
      await tester.pump(const Duration(milliseconds: 121));
      expect([phaseOn(tester, 'details-debit'), phaseOn(tester, 'details-credit')], ['hidden', 'entering']);
      await tester.pumpAndSettle();
      expect([phaseOn(tester, 'details-debit'), phaseOn(tester, 'details-credit')], ['hidden', 'shown']);
    });
  });

  group('the children of other containers fade like those of a column', () {
    _Row child(String id, int shownAt) => {
      'id': id,
      'type': 'Text',
      'props': {
        'content': {'kind': 'literal', 'value': id},
      },
      'visibleIf': {'path': 'account.cardIndex', 'op': 'eq', 'value': shownAt},
      'visibilityTransition': 'fade',
    };

    final containers = <String, _Row Function(List<_Row>)>{
      'Stack': (children) => {'id': 'host', 'type': 'Stack', 'props': const <String, Object?>{}, 'children': children},
      'Grid': (children) => {
        'id': 'host',
        'type': 'Grid',
        'props': {'columns': 2, 'gap': 'sm'},
        'children': children,
      },
      'Row': (children) => {
        'id': 'host',
        'type': 'Row',
        'props': {'gap': 'sm'},
        'children': children,
      },
    };

    for (final entry in containers.entries) {
      testWidgets('${entry.key}: a leaving child stays, then leaves; an appearing one waits, then enters', (
        tester,
      ) async {
        phone(tester);
        final doc = UiDocumentBuilder.bare([
          entry.value([child('first', 0), child('second', 1)]),
        ]);
        await pumpDocument(tester, doc, data: const {'account.cardIndex': 0});
        expect(find.text('first'), findsOneWidget);
        expect(find.text('second'), findsNothing);

        await pumpDocument(tester, doc, data: const {'account.cardIndex': 1});
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('first'), findsOneWidget, reason: 'it fades in place');
        expect(find.text('second'), findsNothing, reason: 'it waits out of the layout');

        await tester.pump(const Duration(milliseconds: 61));
        expect(find.text('first'), findsNothing, reason: 'it has left the layout');
        expect(find.text('second'), findsOneWidget, reason: 'it has entered');

        await tester.pumpAndSettle();
        expect(find.text('second'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
