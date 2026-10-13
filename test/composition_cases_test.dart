/// FREE COMPOSITION AND THE PRESSABLE CONTAINER (schema 9.19.0).
///
/// The case table is shared by every reader of the contract
/// (`assets/contract/fixtures/composition/composition-cases.json`) and every row of its groups runs here:
///
///  1. `nestingCases` (20) -- a parent holding a child of any type is read and drawn, whatever the
///     registry of the builder says;
///  2. `depthCases` (9) -- a chain of containers of the stated depth is drawn to its leaf;
///  3. `documentCases` (16) -- every document is read without a crash, whatever the builder's verdict;
///  4. `pressableCases` (19) -- which node is a pressable container, which takes a press, which is a
///     button on the finished screen: found out by pressing and by looking at the semantics, not by
///     asking a function;
///  5. `pressCases` (21) -- a REAL tap on the box of a node: who runs the action, and that the ancestors
///     of the receiver get nothing; the record of the pressed list row;
///  6. `nameCases` (35) -- the accessible name of the card: the label first, then the text of the content.
///
/// The model is the builder's `scripts/composition-cases.test.tsx`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/composition_rules.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/labels.dart';
import 'package:hotlayout_flutter/src/render/icon_box.dart';
import 'package:hotlayout_flutter/src/render/image_frame.dart';
import 'package:hotlayout_flutter/src/render/widgets/pressable.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/composition/composition-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

_Json _obj(Object? value) => (value! as Map<Object?, Object?>).cast<String, Object?>();

List<_Json> _children(_Json node) => ((node['children'] as List<Object?>?) ?? const []).cast<_Json>();

Map<String, Object?> _text(String id, String value) => {
  'id': id,
  'type': 'Text',
  'props': {
    'content': {'kind': 'literal', 'value': value},
  },
};

/// A node of `type` with the minimum of props it needs to be drawn at all.
_Json _holder(String type, String id, List<_Json> children) {
  final props = switch (type) {
    'Grid' => {'columns': 2},
    'Accordion' || 'Tab' => {
      'title': {'kind': 'literal', 'value': 'Title'},
    },
    'Repeater' => {'source': 'items', 'item': 'item'},
    _ => <String, Object?>{},
  };
  return {'id': id, 'type': type, 'props': props, 'children': children};
}

_Json _leaf(String type, String id) => switch (type) {
  'Text' => _text(id, 'leaf'),
  'Icon' => {
    'id': id,
    'type': 'Icon',
    'props': {'name': 'gift'},
  },
  _ => _holder(type, id, const []),
};

/// The parent holding the child; a tab only stands in `Tabs`.
List<_Json> _nested(String parent, String child) {
  final inner = _holder(parent, 'parent', [child == 'Tab' ? _holder('Tabs', 'child', const []) : _leaf(child, 'child')]);
  return [parent == 'Tab' ? _holder('Tabs', 'tabs', [inner]) : inner];
}

/// Walks the parsed tree to the first node with this id.
UiNode? _find(UiNode node, String id) {
  if (node.id == id) return node;
  for (final child in node.children) {
    final found = _find(child, id);
    if (found != null) return found;
  }
  return null;
}

ScreenNode _screenOf(List<_Json> children) {
  final root = {'id': 'root', 'type': 'Screen', 'props': {}, 'children': children};
  return UiNode.parse(root) as ScreenNode;
}

/// What the host heard: the nodes whose action or analytics event arrived (once each, in order), and the
/// records of the actions.
typedef _Run = ({List<String> ran, List<Map<String, Object?>?> records});

/// Draws [tree] (the child of the screen root) and returns what the host will hear.
Future<_Run> _pump(
  WidgetTester tester,
  _Json tree, {
  Map<String, Object?> data = const {},
}) async {
  final ran = <String>[];
  final records = <Map<String, Object?>?>[];
  await pumpDocument(
    tester,
    docWith([tree]),
    data: data,
    onTrack: (event, nodeId, record) {
      if (!ran.contains(nodeId)) ran.add(nodeId);
    },
    onRecordAction: (action, nodeId, record) {
      if (!ran.contains(nodeId)) ran.add(nodeId);
      records.add(record);
    },
  );
  return (ran: ran, records: records);
}

const _names = ['Alpha', 'Beta', 'Gamma'];

/// The finder of the box a press lands on, for a node of the table. A plain container has nothing of
/// its own to find, so the press lands on its first content: the receiver is the same, because nothing
/// between the container and its content takes a press.
Finder _finderOf(_Json node, {int instance = 0, bool listed = false}) {
  final type = node['type']! as String;
  final id = node['id']! as String;
  final props = _obj(node['props'] ?? const <String, Object?>{});
  String literal(Object? value) => (value! as Map)['value']! as String;
  Finder pick(Finder finder) => listed ? finder.at(instance) : finder.first;
  switch (type) {
    case 'Text':
      final content = _obj(props['content']);
      if (content['kind'] == 'binding') return find.text(listed ? _names[instance] : content['fallback']! as String);
      return find.text(literal(content));
    case 'Button':
      return pick(find.text(literal(props['label'])));
    case 'IconButton':
      return find.bySemanticsLabel(literal(props['label'])).first;
    case 'ListTile':
      return pick(find.text(literal(props['title'])));
    case 'Switch' || 'Checkbox':
      return pick(find.text(literal(props['label'])));
    case 'TextField':
      return find.byKey(ValueKey('sdui-input-$id@')).first;
    case 'Accordion':
      return find.text(literal(props['title'])).first;
    case 'Icon':
      return find.byType(IconBox).first;
    case 'Image':
      return find.byType(ImageFrame).first;
    case 'Tabs':
      return find.text(literal(_obj(_children(node).first['props'])['title'])).first;
    default:
      if (kPressableTypes.contains(type) && props['action'] != null && isPressAction(ButtonAction.parse(props['action']))) {
        return find.byKey(ValueKey('sdui-press-$id@${listed ? '$instance' : ''}')).first;
      }
      final children = _children(node);
      if (children.isEmpty) return find.byKey(ValueKey('sdui-press-$id@')).first;
      return _finderOf(children.first, instance: instance, listed: listed);
  }
}

void main() {
  group('table: structure', () {
    test('six groups with the promised number of rows', () {
      expect(_rows('nestingCases'), hasLength(20));
      expect(_rows('depthCases'), hasLength(9));
      expect(_rows('documentCases'), hasLength(16));
      expect(_rows('pressableCases'), hasLength(19));
      expect(_rows('pressCases'), hasLength(21));
      expect(_rows('nameCases'), hasLength(35));
      expect(_table['maxDepth'], 8);
    });
  });

  group('nestingCases: a child of any type is read and drawn', () {
    for (final row in _rows('nestingCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final parent = row['parent']! as String;
        final child = row['child']! as String;
        final tree = _nested(parent, child);
        final screen = _screenOf(tree);
        final inner = _find(screen, 'parent');
        expect(inner, isNotNull, reason: 'the parent is parsed');
        // The reader does not check child types: a parent that holds children keeps this one.
        if (!const {'Text', 'Icon'}.contains(parent)) {
          expect(inner!.children.map((node) => node.id), contains('child'), reason: '${row['name']}: ${row['allowed']}');
        }
        await pumpDocument(tester, docWith(tree));
        expect(tester.takeException(), isNull, reason: 'the reader draws what arrived');
      });
    }
  });

  group('depthCases: the tree is drawn to its leaf', () {
    for (final row in _rows('depthCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final chain = (row['chain']! as List<Object?>).cast<String>();
        final leafType = row['leaf']! as String;
        var node = _leaf(leafType, 'leaf');
        for (var index = chain.length - 1; index >= 0; index -= 1) {
          node = _holder(chain[index], 'n$index', [node]);
        }
        final screen = _screenOf([node]);
        expect(_find(screen, 'leaf'), isNotNull, reason: 'depth ${row['depth']} (the limit of the reader is $kReaderParseLimit)');
        await pumpDocument(tester, docWith([node]), data: {'items': [{'name': 'x'}]});
        expect(tester.takeException(), isNull);
        if (leafType == 'Text') expect(find.text('leaf'), findsOneWidget);
        if (leafType == 'Icon') expect(find.byType(IconBox), findsOneWidget);
      });
    }

    test('the reader parse limit is the artifact value', () {
      final depth = _obj(_obj(_obj(_schema['x-style'])['layout'])['composition'])['depth']! as _Json;
      expect(depth['readerParseLimit'], kReaderParseLimit);
      expect(depth['max'], _table['maxDepth']);
      expect(depth['readerBelowParseLimit'], 'draws-the-tree');
      expect(depth['readerAboveParseLimit'], 'rejects-the-screen');
      expect(depth['counted'], 'levels-below-the-screen-root');
      expect(depth['root'], 0);
    });

    _Json chain(int levels) {
      var node = _text('leaf', 'deep');
      for (var level = levels - 1; level >= 1; level -= 1) {
        node = _holder('Column', 'c$level', [node]);
      }
      return node;
    }

    // `levels` is the level of the leaf: the root's children are level 1.
    test('a tree up to the limit is read whole; a deeper one is rejected as a screen', () {
      for (final levels in [1, 8, kReaderParseLimit]) {
        final screen = docWith([chain(levels)]).initialScreen;
        expect(screen.tooDeep, isFalse, reason: 'level $levels');
        expect(_find(screen.root, 'leaf'), isNotNull, reason: 'at $levels levels the tree is read to its leaf');
      }
      for (final levels in [kReaderParseLimit + 1, kReaderParseLimit + 2, 1000]) {
        expect(docWith([chain(levels)]).initialScreen.tooDeep, isTrue, reason: 'level $levels');
      }
      // Only objects are nodes: a hole in the list is not a level.
      expect(exceedsParseLimit({'children': List.filled(5, null)}), isFalse);
    });

    testWidgets('a rejected screen draws a notice, not half a screen; the next screen of the document is drawn', (tester) async {
      final document = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'deep',
        'name': 'deep',
        'initialScreenId': 'deep',
        'screens': [
          screenEntry('deep', [chain(kReaderParseLimit + 1)]),
          screenEntry('fine', [_text('fine-text', 'A fine screen')]),
        ],
      });
      await pumpDocument(tester, document);
      expect(tester.takeException(), isNull);
      expect(find.text('deep'), findsNothing, reason: 'nothing of the too deep tree is drawn');
      expect(find.text(const RendererLabels().screenUnavailable), findsOneWidget);
      // A tree at the limit is drawn to its leaf, and another screen of a document is not touched by the rejection.
      await pumpDocument(tester, docWith([chain(kReaderParseLimit)]));
      expect(find.text('deep'), findsOneWidget);
      final fineFirst = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'deep',
        'name': 'deep',
        'initialScreenId': 'fine',
        'screens': [
          screenEntry('deep', [chain(kReaderParseLimit + 1)]),
          screenEntry('fine', [_text('fine-text', 'A fine screen')]),
        ],
      });
      await pumpDocument(tester, fineFirst);
      expect(find.text('A fine screen'), findsOneWidget);
    });
  });

  group('documentCases: every document is read without a crash', () {
    for (final row in _rows('documentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final children = _children(row);
        await pumpDocument(tester, docWith(children));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('pressableCases: who is a pressable container, who takes a press, who is a button', () {
    for (final row in _rows('pressableCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final semantics = tester.ensureSemantics();
        final node = _obj(row['node']);
        final type = node['type']! as String;
        final id = node['id']! as String;
        final withContent = {
          ...node,
          if (const {'Column', 'Row', 'Container', 'Stack', 'Grid', 'Tabs', 'Accordion'}.contains(type))
            'children': [
              if (type == 'Tabs')
                _holder('Tab', 'tab', [_text('tab-text', 'In the tab')])
              else
                _text('content', 'Content'),
            ],
        };

        // 1. `pressable`: the parser keeps the press on the four container types, only when it does something.
        final parsed = _find(_screenOf([withContent]), id);
        expect(parsed is ChildNode && parsed.press != null, row['pressable'], reason: '${row['name']}: pressable');

        // 2. `ownsPress`: a press on the node does not reach the card around it.
        // An option row only stands in a group: a bare one is dead.
        final isOption = type == 'ListTile' && (_obj(node['props'])['trailing'] as Map?)?['kind'] == 'radio';
        final placed = isOption ? choiceGroupNode([withContent], value: {'kind': 'literal', 'value': 'zzz'}) : withContent;
        final outer = _holder('Container', 'outer', [placed]);
        (outer['props']! as _Json)['action'] = {'type': 'submit'};
        final outerRun = await _pump(tester, outer, data: const {'user.isPremium': true, 'user.firstName': 'Maya'});
        await tester.tap(_finderOf(withContent), warnIfMissed: false);
        await tester.pump();
        expect(!outerRun.ran.contains('outer'), row['ownsPress'], reason: '${row['name']}: ownsPress (ran: ${outerRun.ran})');

        // 3. `acts`: a button on the finished screen. The node stands alone, so no card around it
        // lends its own role to the text inside.
        await _pump(tester, placed, data: const {'user.isPremium': true, 'user.firstName': 'Maya'});
        final flags = tester.getSemantics(_buttonFinder(node, withContent)).flagsCollection;
        expect(flags.isButton, row['acts'], reason: '${row['name']}: acts');
        semantics.dispose();
      });
    }
  });

  group('pressCases: a tap on the box of a node', () {
    for (final row in _rows('pressCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final semantics = tester.ensureSemantics();
        final tree = _obj(row['tree']);
        final instances = row['instances'] as int?;
        final instance = (row['instance'] as int?) ?? 0;
        final disabled = (row['disabled'] as List<Object?>?)?.cast<String>() ?? const <String>[];
        final data = <String, Object?>{
          'user.isPremium': disabled.isEmpty,
          'user.firstName': 'Maya',
          if (instances != null) 'items': [for (final name in _names.take(instances)) {'name': name}],
        };
        final document = instances == null ? tree : _holder('Repeater', 'list', [tree]);
        final run = await _pump(tester, document, data: data);
        final press = _findNode(tree, row['press']! as String);
        var target = _finderOf(press, instance: instance, listed: instances != null);
        if (target.evaluate().isEmpty) {
          // The body of a collapsed accordion is not built: open the accordion by its header first.
          await tester.tap(find.text('Question'));
          await tester.pumpAndSettle();
          target = _finderOf(press, instance: instance, listed: instances != null);
        }
        await tester.tap(target, warnIfMissed: false);
        await tester.pump();
        final runs = row['runs'] as String?;
        // A `none` action without an event is executed and heard by nobody: the host gets nothing.
        final observable = runs != null && _observable(_findNode(tree, runs));
        expect(run.ran, observable ? [runs] : isEmpty, reason: '${row['name']}: who runs (receiver ${row['receiver']})');
        if (instances != null && runs != null) {
          final record = run.records.single;
          expect(record?['item.name'], _names[instance], reason: 'the action carries the record of ITS row');
        }
        semantics.dispose();
      });
    }
  });

  group('nameCases: the label first, then the text of the content', () {
    for (final row in _rows('nameCases')) {
      final tree = _obj(row['tree']);
      testWidgets(row['name']! as String, (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, tree);
        // The body of a collapsed accordion is not built; open it, as a person would.
        final headers = [for (final node in _all(tree)) if (node['type'] == 'Accordion') _obj(node['props'])['title']];
        for (final header in headers) {
          await tester.tap(find.text((header! as Map)['value']! as String).first);
          await tester.pumpAndSettle();
        }
        final label = _withoutPlaceholder(tester.getSemantics(find.byType(PressableCard).first).label);
        expect(!isSilentAccessibleName(label), row['hasName'], reason: '${row['name']}: hasName (label "$label")');
        final startsWith = row['startsWith'] as String?;
        if (startsWith != null) expect(label.startsWith(startsWith), isTrue, reason: 'starts with "$startsWith": "$label"');
        for (final heard in (row['heard']! as List<Object?>).cast<String>()) {
          expect(label, contains(heard));
        }
        // The pictures inside the card, on the finished screen, are named by their descriptions.
        for (final described in ((row['described'] as List<Object?>?) ?? const []).cast<String>()) {
          expect(label, contains(described), reason: 'the description "$described" is heard and names the card');
        }
        semantics.dispose();
      });
    }
  });

  group('mirror of the artifact', () {
    test('x-style.layout.composition: the keys the reader executes', () {
      final composition = _obj(_obj(_obj(_schema['x-style'])['layout'])['composition']);
      final pressable = _obj(composition['pressable']);
      expect(_obj(pressable['props']), {'action': 'action', 'label': 'label'});
      expect(_obj(pressable['semantics'])['ownControlTextWidgets'], ['Accordion', 'Tab']);
      expect(_obj(pressable['press'])['ownControlWidgets'], ['Tabs', 'Accordion']);
      expect(_obj(pressable['keyboard'])['activate'], ['Enter', 'Space']);
      expect(kPressableTypes, {'Column', 'Row', 'Container', 'Stack'});
      expect(pressable['disabledState'], 'none');
    });

    test('the feature names are in the catalog', () {
      final features = _obj(_obj(_schema['x-compatibility'])['features']);
      for (final name in ['sameTypeNesting', 'treeDepthEight', 'pressableContainer']) {
        expect(features[name], '9.19.0');
      }
    });
  });
}

/// The text of the reader's own placeholder of a picture that did not load (`RendererLabels`) is the
/// reader's chrome, not a name that the document gave: the test has no network.
String _withoutPlaceholder(String label) => label
    .split('\n')
    .where((line) => line != 'Image unavailable' && !line.startsWith('https://example.com/'))
    .join('\n');

Iterable<_Json> _all(_Json node) sync* {
  yield node;
  for (final child in _children(node)) {
    yield* _all(child);
  }
}

/// Whether the host hears the action or the event of this node: any type but `none`, or `none` with an event.
bool _observable(_Json node) {
  final action = _obj(_obj(node['props'])['action']);
  return action['type'] != 'none' || action['track'] != null;
}

_Json _findNode(_Json node, String id) {
  if (node['id'] == id) return node;
  for (final child in _children(node)) {
    final found = _findNodeOrNull(child, id);
    if (found != null) return found;
  }
  throw StateError('no node $id');
}

_Json? _findNodeOrNull(_Json node, String id) {
  if (node['id'] == id) return node;
  for (final child in _children(node)) {
    final found = _findNodeOrNull(child, id);
    if (found != null) return found;
  }
  return null;
}

/// Where to read the semantics of a node: its own box when it has one, else its text.
Finder _buttonFinder(_Json node, _Json withContent) {
  final type = node['type']! as String;
  return switch (type) {
    'Column' || 'Row' || 'Container' || 'Stack' => find.byKey(ValueKey('sdui-press-${node['id']}@')).evaluate().isNotEmpty
        ? find.byKey(ValueKey('sdui-press-${node['id']}@')).first
        : find.text('Content').first,
    _ => _finderOf(withContent),
  };
}
