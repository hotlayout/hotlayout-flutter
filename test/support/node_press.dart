/// Pressing a node of a case table the way a person does: where to tap it, how to reach it from the keyboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

typedef Json = Map<String, Object?>;

Json asJson(Object? value) => (value! as Map<Object?, Object?>).cast<String, Object?>();

List<Json> childrenOf(Json node) => ((node['children'] as List<Object?>?) ?? const []).cast<Json>();

/// The node with this id in a tree (or a list of trees), or `null`.
Json? findNodeJson(Object? tree, String id) {
  if (tree is List) {
    for (final item in tree) {
      final found = findNodeJson(item, id);
      if (found != null) return found;
    }
    return null;
  }
  final node = asJson(tree);
  if (node['id'] == id) return node;
  return findNodeJson(childrenOf(node), id);
}

String _literal(Object? value) => asJson(value)['value']! as String;

/// Where a tap on the node lands: its label, its accessible name, or the box of the card.
///
/// Needs `tester.ensureSemantics()` for an icon button (found by its name).
Finder finderOfNodeJson(Json node) {
  final type = node['type']! as String;
  final props = asJson(node['props'] ?? const <String, Object?>{});
  switch (type) {
    case 'Text':
      return find.text(_literal(props['content'])).first;
    case 'Button':
      return find.text(_literal(props['label'])).first;
    case 'IconButton':
      return find.bySemanticsLabel(_literal(props['label'])).first;
    case 'ListTile':
      return find.text(_literal(props['title'])).first;
    case 'Switch' || 'Checkbox':
      return find.text(_literal(props['label'])).first;
    default:
      return find.byKey(ValueKey('sdui-press-${node['id']}@')).first;
  }
}

/// Moves the keyboard focus onto [target] with Tab. Returns whether it got there: a disabled button is not a stop
/// of the focus order in Flutter, and then a key goes nowhere.
Future<bool> focusWithTab(WidgetTester tester, Finder target) async {
  final element = target.evaluate().first;
  bool contains(Element outer, Element inner) {
    var found = identical(outer, inner);
    inner.visitAncestorElements((ancestor) {
      if (identical(ancestor, outer)) found = true;
      return !found;
    });
    return found;
  }

  for (var step = 0; step < 24; step += 1) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final context = FocusManager.instance.primaryFocus?.context;
    if (context is! Element) continue;
    if (contains(context, element) || contains(element, context)) return true;
  }
  return false;
}
