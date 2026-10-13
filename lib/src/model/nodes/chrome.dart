/// Screen chrome nodes: the app bar and the navigation bar with its items.
part of '../node.dart';

/// The app bar (6.0.0).
///
/// A node the schema allows only in `Screen`, as its first and only such child. The builder's validator
/// sees this rule (`app_bar_misplaced`), not JSON Schema: in the `ChildNode` union `AppBar` stands level
/// with the rest, so a document from the network may well bring an app bar inside a `Column`. The
/// renderer draws such a document rather than rejecting it; see `render_document.dart`.
final class AppBarNode extends ChildNode {
  const AppBarNode({
    required super.id,
    super.visibleIf,
    super.hiddenByClass,
    super.style,
    super.styleWhen,
    super.fill,
    super.weight,
    super.layer,
    super.pull,
    super.pin,
    required this.title,
    required this.subtitle,
    required this.showBack,
    this.titleAlign = AppBarTitleAlign.center,
    this.children = const [],
  });

  /// Where the title block stands (9.16.0): `start` is right after the leading zone, lines start-aligned;
  /// `center` (and anything that is not `start`) is as before 9.16.0.
  final AppBarTitleAlign titleAlign;

  final BindableString title;
  final BindableString? subtitle;

  /// The app bar actions (9.9.0): children in document order. Only `IconButton`s are drawn, the rest are
  /// not (`appBarChildren: 'icon-buttons-in-order-others-not-drawn'`). The reader does not enforce the
  /// limit of two here.
  @override
  final List<ChildNode> children;

  /// The "show back arrow" flag. What "back" means the contract does not say: the app bar has no action
  /// for it at all.
  final bool showBack;
}

// 9.9.0: the children of the app bar are its actions; it is no longer a leaf.
AppBarNode _parseAppBar(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return AppBarNode(
    id: id,
    visibleIf: visibleIf,
    hiddenByClass: hiddenByClass,
    style: style,
    styleWhen: styleWhen,
    fill: node.fill,
    weight: node.weight,
    layer: node.layer,
    pull: node.pull,
    pin: node.pin,
    title: BindableString.parse(props['title'], key: node.key('title')),
    subtitle: props['subtitle'] == null
        ? null
        : BindableString.parse(props['subtitle'], key: node.key('subtitle')),
    showBack: _bool(props['showBack'], true),
    titleAlign: titleAlignOf(props['titleAlign']),
    // 9.9.0: the children of the app bar are its actions. Which types they are is decided at paint time
    // (`appBarChildren`), while parsing takes all of them: a child the app bar does not draw is still
    // visible to a walk of the tree.
    children: node.childNodes(),
  );
}

/// The navigation bar (9.12.0): the last child of the screen root is drawn in the bottom zone
/// (`screenChildrenByZone`). If it is not the last, it is an ordinary body child (`navBarNotLast`). The
/// children are [NavItemNode]s; the bar does not draw other types.
final class NavBarNode extends ChildNode {
  const NavBarNode({
    required super.id,
    super.visibleIf,
    super.hiddenByClass,
    super.style,
    super.styleWhen,
    super.fill,
    super.weight,
    super.layer,
    super.pull,
    super.pin,
    this.widePlacement = NavWidePlacement.top,
    this.children = const [],
  });

  /// Where the bar goes in a wide place (9.18.0, `NavBar.widePlacement`): `top` is at the top, `bottom`
  /// at the bottom as on a phone. Without the field, and with an unknown word, `top`.
  final NavWidePlacement widePlacement;

  @override
  final List<ChildNode> children;
}

// 9.12.0: the navigation bar. The children are items. The only prop is `widePlacement` (9.18.0): a
// word of the wrong shape or an unknown one reads as "no field" (`top`).
NavBarNode _parseNavBar(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return NavBarNode(
    id: id,
    visibleIf: visibleIf,
    hiddenByClass: hiddenByClass,
    style: style,
    styleWhen: styleWhen,
    fill: node.fill,
    weight: node.weight,
    layer: node.layer,
    pull: node.pull,
    pin: node.pin,
    widePlacement: navWidePlacementOf(props['widePlacement']),
    children: node.childNodes(),
  );
}

/// A navigation bar item (9.12.0): an icon above a label, and an action. What makes it active is not
/// its own state but the shown screen (`isActiveNavAction`).
final class NavItemNode extends ChildNode {
  const NavItemNode({
    required super.id,
    super.visibleIf,
    super.hiddenByClass,
    super.style,
    super.styleWhen,
    super.fill,
    super.weight,
    super.layer,
    super.pull,
    super.pin,
    required this.icon,
    required this.iconName,
    required this.label,
    required this.action,
  });

  /// The glyph; [IconToken.unknown] is an empty box of the same size.
  final IconToken icon;

  /// The icon name as in the document (for a name derived from the icon name); `null` means it is not a
  /// string.
  final String? iconName;

  /// The label: the visible text and the item's accessible name at once.
  final BindableString label;
  final ButtonAction action;
}

// 9.12.0: a bar item. Without `icon` the field default `house` applies (like `info` in `IconButton`);
// if the field IS there and is not readable, an empty box of the same size.
NavItemNode _parseNavItem(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return NavItemNode(
    id: node.leafId(),
    visibleIf: visibleIf,
    hiddenByClass: hiddenByClass,
    style: style,
    styleWhen: styleWhen,
    fill: node.fill,
    weight: node.weight,
    layer: node.layer,
    pull: node.pull,
    pin: node.pin,
    icon: props.containsKey('icon') ? IconToken.parse(props['icon']) : IconToken.parse('house'),
    iconName: props.containsKey('icon') ? (props['icon'] is String ? props['icon']! as String : null) : 'house',
    label: BindableString.parse(props['label'], key: node.key('label')),
    action: ButtonAction.parse(props['action']),
  );
}
