/// Nodes that group content: tabs, accordion and the choice group.
part of '../node.dart';

/// Tabs (8.8.0): several panels under a shared strip; exactly one is visible.
///
/// Only [TabNode]s may be children: so says the builder's registry. The renderer does NOT rely on it: the
/// document comes from the network, and a foreign node among the tabs is simply not taken into the strip
/// (see `_tabs`) rather than crashing.
final class TabsNode extends ChildNode {
  const TabsNode({
    required super.id,
    super.visibleIf,
    super.hiddenByClass,
    super.style,
    super.styleWhen,
    super.fill,
    super.weight,
    super.layer,
    super.motion,
    super.pull,
    super.pin,
    super.pinTop,
    super.pressFeedbackOff,
    required this.children,
    required this.initialTab,
  });

  @override
  final List<ChildNode> children;

  /// The number of the tab open when the screen is shown. An INITIAL state, not a mirror of the current
  /// one: afterwards a finger drives the tabs and the document never learns about it, as with
  /// `Accordion.initiallyExpanded`.
  final int initialTab;
}

TabsNode _parseTabs(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return TabsNode(
    id: id,
    visibleIf: visibleIf,
    hiddenByClass: hiddenByClass,
    style: style,
    styleWhen: styleWhen,
    fill: node.fill,
    weight: node.weight,
    layer: node.layer,
    motion: node.motion,
    pull: node.pull,
    pin: node.pin,
    pinTop: node.pinTop,
    pressFeedbackOff: node.pressFeedbackOff,
    children: node.childNodes(),
    // A negative number and a non-integer are a number outside the list (`-1`); a number larger than the
    // last tab is too. In all three cases the first VISIBLE tab opens (`initialTabOutOfRange:
    // 'first-visible'`); see `_tabs`.
    initialTab: _tabIndex(props['initialTab']),
  );
}

/// One tab panel together with its title.
///
/// The title lies HERE and not in an array of titles on the parent, and this is the main structural
/// decision of 8.8.0: two parallel lists would fall out of sync on the very first reordering of tabs,
/// silently.
final class TabNode extends ChildNode {
  const TabNode({
    required super.id,
    super.visibleIf,
    super.hiddenByClass,
    super.style,
    super.styleWhen,
    super.fill,
    super.weight,
    super.layer,
    super.motion,
    super.pull,
    super.pin,
    super.pinTop,
    super.pressFeedbackOff,
    required this.children,
    required this.title,
  });

  @override
  final List<ChildNode> children;

  final BindableString title;
}

TabNode _parseTab(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return TabNode(
    id: id,
    visibleIf: visibleIf,
    hiddenByClass: hiddenByClass,
    style: style,
    styleWhen: styleWhen,
    fill: node.fill,
    weight: node.weight,
    layer: node.layer,
    motion: node.motion,
    pull: node.pull,
    pin: node.pin,
    pinTop: node.pinTop,
    pressFeedbackOff: node.pressFeedbackOff,
    children: node.childNodes(),
    title: BindableString.parse(props['title'], key: node.key('title')),
  );
}

final class AccordionNode extends ChildNode {
  const AccordionNode({
    required super.id,
    super.visibleIf,
    super.hiddenByClass,
    super.style,
    super.styleWhen,
    super.fill,
    super.weight,
    super.layer,
    super.motion,
    super.pull,
    super.pin,
    super.pinTop,
    super.pressFeedbackOff,
    required this.children,
    required this.title,
    required this.initiallyExpanded,
  });

  @override
  final List<ChildNode> children;
  final BindableString title;

  /// Precisely an initial state, not a controlled prop: after the first tap the document no longer affects
  /// the expansion.
  final bool initiallyExpanded;
}

AccordionNode _parseAccordion(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return AccordionNode(
    id: id,
    visibleIf: visibleIf,
    hiddenByClass: hiddenByClass,
    style: style,
    styleWhen: styleWhen,
    fill: node.fill,
    weight: node.weight,
    layer: node.layer,
    motion: node.motion,
    pull: node.pull,
    pin: node.pin,
    pinTop: node.pinTop,
    pressFeedbackOff: node.pressFeedbackOff,
    children: node.childNodes(),
    title: BindableString.parse(props['title'], key: node.key('title')),
    initiallyExpanded: _bool(props['initiallyExpanded'], false),
  );
}

/// A group of mutually exclusive choice (6.0.0): the first contract node that describes STATE rather
/// than look.
///
/// [value] is the name of the selected option, not an index and not a flag on a row. The choice belongs to
/// the group: the rows only name themselves (`TrailingRadio.optionValue`), and a document with two
/// selected is structurally impossible.
///
/// [value] is bindable because the initial choice comes from data: the user may have picked a record last
/// time, and the screen has to open with that choice.
final class ChoiceGroupNode extends ChildNode {
  const ChoiceGroupNode({
    required super.id,
    super.visibleIf,
    super.hiddenByClass,
    super.style,
    super.styleWhen,
    super.fill,
    super.weight,
    super.layer,
    super.motion,
    super.pull,
    super.pin,
    super.pinTop,
    super.pressFeedbackOff,
    required this.children,
    required this.value,
    required this.gap,
    this.required = false,
    this.valuePath,
    this.valueFallback,
  });

  @override
  final List<ChildNode> children;
  final BindableString value;

  /// Required (9.14.0): only the literal `true`. The group has no label, so there is no asterisk, only
  /// state for a screen reader.
  final bool required;

  /// The path the group writes the choice to (`inputPathOf`): only a real binding. A literal and an empty
  /// path give `null`: the choice stays the group's own state.
  final String? valuePath;

  /// The binding's fallback text: without data the group shows the option with this name as selected, so
  /// "filled" has to see it too.
  final String? valueFallback;
  final FieldSpacing gap;

  /// The names of all options in the group's subtree, needed only for the "selected something that is not
  /// there" diagnostic. The walk is deep on purpose: the schema allows any node in `children`, so a row may
  /// lie inside a `Container`.
  Set<String> get optionValues {
    final values = <String>{};
    void walk(ChildNode node) {
      if (node is ListTileNode) {
        final trailing = node.trailing;
        if (trailing is TrailingRadio) values.add(trailing.optionValue);
      }
      // A nested group owns its own options; we do not collect foreign ones.
      if (node is ChoiceGroupNode) return;
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final child in children) {
      walk(child);
    }
    return values;
  }
}

ChoiceGroupNode _parseChoiceGroup(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return ChoiceGroupNode(
    id: id,
    visibleIf: visibleIf,
    hiddenByClass: hiddenByClass,
    style: style,
    styleWhen: styleWhen,
    fill: node.fill,
    weight: node.weight,
    layer: node.layer,
    motion: node.motion,
    pull: node.pull,
    pin: node.pin,
    pinTop: node.pinTop,
    pressFeedbackOff: node.pressFeedbackOff,
    children: node.childNodes(),
    // There is deliberately no key: `value` is the NAME of the selected option, compared with the row's
    // `optionValue`, not text for a person. A translation here would break the choice. In the builder's
    // registry this field is `localizable: false` too.
    value: BindableString.parse(props['value'], formats: false),
    gap: FieldSpacing.parse(props['gap'], fieldDefault: SpacingToken.none),
    // 9.14.0: "required" (only the literal `true`) and where the group writes the choice.
    required: isRequiredProp(props['required']),
    valuePath: inputPathOf(props['value']),
    valueFallback: fallbackOfBinding(props['value']),
  );
}
