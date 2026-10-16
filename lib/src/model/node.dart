import 'package:flutter/foundation.dart';

import '../data/screen_data.dart';
import 'action.dart';
import 'bindable.dart';
import 'bottom_zone_rules.dart';
import 'compatibility.dart';
import 'composition_rules.dart';
import 'layout_rules.dart';
import 'list_tile_parts.dart';
import 'icon_from_data.dart';
import 'input_parts.dart';
import 'input_rules.dart';
import 'list_marker.dart';
import 'localization.dart';
import 'media_chrome_rules.dart';
import 'motion_rules.dart';
import 'progress_cap.dart';
import 'node_style.dart';
import 'offset_rules.dart';
import 'part_style.dart';
import 'scrolled_bar.dart';
import 'carousel_rules.dart';
import 'progress_rules.dart';
import 'screen_top_rules.dart';
import 'style_values.dart';
import 'text_spans.dart';
import 'tokens.dart';
import 'visibility.dart';
import 'width_class.dart';

part 'nodes/chrome.dart';
part 'nodes/content.dart';
part 'nodes/controls.dart';
part 'nodes/layout.dart';
part 'nodes/list_tile.dart';
part 'nodes/parse.dart';
part 'nodes/progress.dart';
part 'nodes/sections.dart';

// A node of the screen tree.
//
// A sealed hierarchy plus pattern matching in the renderer gives exhaustiveness: add a type to the
// contract and the compiler shows where it is not drawn yet.
//
// The hierarchy has two levels on purpose: in schema 4.0.0 `Screen` left the list of allowed children,
// so [ScreenNode] stays outside [ChildNode], and "a screen inside a screen" cannot even be expressed in
// the types.
/// A node of a parsed document. Opaque to hosts: hand a screen to
/// `renderScreen` or a document to `renderDocument`.
sealed class UiNode {
  const UiNode({required this.id, this.style, this.styleWhen = const []});

  final String id;

  /// The node's style (9.0.0): box, background, border, shadow, color and font. `null` means there is no
  /// style, and that means exactly "none": no background, no padding.
  ///
  /// It lies on the root of the hierarchy because in the schema this is a field of the node ITSELF, the
  /// same on every type including `Screen`. It is the RAW base style, without states and without
  /// inheritance; draw with what `resolveNodeStyle` gives.
  final NodeStyle? style;

  /// The node's STATES (8.9.0): "condition to style", the first whose condition holds applies.
  ///
  /// They cannot be applied while parsing: which state is in effect depends on the DATA, and data changes
  /// without the document being re-read.
  final List<StyleCase> styleWhen;

  /// Leaf nodes have no children: in schema 4.0.0 they have no `children` field at all, so the default
  /// is empty and only containers override it.
  List<ChildNode> get children => const [];

  /// Parses the root of the document. NEVER throws: any problem collapses into an [UnknownNode] or the
  /// token default (see the "unknown type" section below).
  ///
  /// [keys] is the builder of localization keys (7.2.0). It is off by default, so the tree is parsed
  /// exactly as before 7.2.0.
  ///
  /// [widthClass] (9.18.0) is the width class the tree is resolved FOR (`nodeInWidthClass`): effective
  /// `props`, `style` with the `styleOn` layers, `showOn` as a flag. Without it, `compact`, i.e. the base
  /// of the document.
  static UiNode parse(
    Object? raw, {
    LocalizationKeys keys = LocalizationKeys.off,
    WidthClass widthClass = WidthClass.compact,
  }) {
    final node = _RawNode.of(raw, keys, widthClass);
    if (node.type == 'Screen') {
      // Since 9.0.0 the screen's `props` are empty: background and padding moved to `style`, and the reader
      // has no default look: a screen without a style has neither background nor padding.
      return ScreenNode(
        id: node.id,
        children: node.childNodes(),
        style: node.style,
        styleWhen: node.styleWhen,
        gap: FieldSpacing.parse(node.props['gap'], fieldDefault: SpacingToken.sm),
        // 9.15.0: alignment of children. A missing field, `null` or an unknown word acts as without the field
        // (`alignment.cross.unknownValue`), with no warning.
        align: _alignWord(node.props['align'], AlignToken.start),
        justify: _justifyWord(node.props['justify']),
        // 9.18.0: the largest content width; a non-integer means no field, an out-of-range value is
        // clamped.
        contentMaxWidth: contentMaxWidthOf(node.props['contentMaxWidth']),
        // 9.19.0: where the body area starts. One word; anything else is no field. The field is not
        // overridden by the width class (`propsOn` does not name it).
        bodyTop: bodyTopOf(node.props['bodyTop']),
      );
    }
    return _parseChild(node);
  }

  static ChildNode _parseChild(_RawNode node) {
    final id = node.id;
    // `visibleIf` is a field of the node, not a prop, and every child type has it, so it is parsed once
    // before the type is chosen.
    final visibleIf = VisibilityCondition.parse(node.visibleIf);
    final hiddenByClass = node.hiddenByClass;
    final style = node.style;
    final styleWhen = node.styleWhen;

    return switch (node.type) {
      'AppBar' => _parseAppBar(node, visibleIf),
      'Column' => _parseColumn(node, visibleIf),
      'Row' => _parseRow(node, visibleIf),
      'Container' => _parseContainer(node, visibleIf),
      'Grid' => _parseGrid(node, visibleIf),
      'Stack' => _parseStack(node, visibleIf),
      'Tabs' => _parseTabs(node, visibleIf),
      'Tab' => _parseTab(node, visibleIf),
      'Accordion' => _parseAccordion(node, visibleIf),
      'ChoiceGroup' => _parseChoiceGroup(node, visibleIf),
      'Repeater' => _parseRepeater(node, visibleIf),
      'Spacer' => _parseSpacer(node, visibleIf),
      'Divider' => _parseDivider(node, visibleIf),
      'Text' => _parseText(node, visibleIf),
      'Image' => _parseImage(node, visibleIf),
      'Icon' => _parseIcon(node, visibleIf),
      'Button' => _parseButton(node, visibleIf),
      'ListTile' => _parseListTile(node, visibleIf),
      'ProgressBar' => _parseProgressBar(node, visibleIf),
      'CircularProgress' => _parseCircularProgress(node, visibleIf),
      'Badge' => _parseBadge(node, visibleIf),
      'IconButton' => _parseIconButton(node, visibleIf),
      'NavBar' => _parseNavBar(node, visibleIf),
      'NavItem' => _parseNavItem(node, visibleIf),
      'TextField' => _parseTextField(node, visibleIf),
      'Switch' => _parseSwitch(node, visibleIf),
      'Checkbox' => _parseCheckbox(node, visibleIf),
      // In 4.0.0 a `Screen` cannot be a child. This is not an "unknown type from the future" but an error
      // in the document, so it gets a separate log message, but degrades as softly as for a foreign type.
      'Screen' => () {
        if (kDebugMode) {
          debugPrint('[hotlayout] `Screen` cannot be a child (id=$id): rendered as an unknown widget');
        }
        return UnknownNode(
          id: id,
          type: 'Screen',
          children: node.childNodes(),
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
        );
      }(),
      // A type this version of the app does not know. For server-driven UI this is a normal situation: the
      // admin tool and backend are updated faster than a mobile release rolls out. The raw data is kept so
      // the renderer can degrade softly (see the unknown-node handling in the renderer).
      _ => () {
        if (kDebugMode) {
          debugPrint('[hotlayout] unknown widget type "${node.type}" (id=$id)');
        }
        return UnknownNode(
          id: id,
          type: node.type,
          children: node.childNodes(),
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
        );
      }(),
    };
  }

}

/// A row-width share from the document (8.17.0).
///
/// The contract allows an integer from 1 to 4. The renderer used not to check the upper bound
/// (Flutter draws `flex: 7` without complaint); since 9.0.0 the policy says otherwise: a positive
/// value out of range is clamped, like any numeric field (`literalOutOfRange`), because otherwise
/// `weight: 9` would divide the row differently from the builder's preview.
///
/// Zero and negative values are discarded, and not out of pedantry: `Expanded(flex: 0)` gives the
/// child ZERO pixels, so the node stays in the document and vanishes from the screen. This is exactly
/// the silent loss the contract set a minimum of 1 to prevent. A discarded weight reads as no weight:
/// the node's own width.
const int kMinNodeWeight = 1;
const int kMaxNodeWeight = 4;

int? _weight(Object? raw) {
  // `invalidWeight: 'no-weight'`: a non-number, zero and a negative mean no weight (the node takes its
  // own width). This is the only numeric field with bounds where "not a number" does not give the lower
  // bound: a row share taken from nothing would take room from its neighbours. A non-integer weight (1.5,
  // infinity) also means no weight and is not rounded (`invalidWeight` covers it explicitly).
  if (raw is! num || !raw.isFinite || raw <= 0 || raw != raw.truncate()) return null;
  // A positive value outside 1..4 is clamped (`literalOutOfRange: 'clamp'`).
  return raw.clamp(kMinNodeWeight, kMaxNodeWeight).toInt();
}

final class ScreenNode extends UiNode {
  const ScreenNode({
    required super.id,
    required this.children,
    this.gap = const FieldSpacing(ScaleRef.token('sm'), SpacingToken.sm),
    this.align = AlignToken.start,
    this.justify = JustifyToken.start,
    this.contentMaxWidth,
    this.bodyTop,
    super.style,
    super.styleWhen,
  });

  @override
  final List<ChildNode> children;

  /// Where the body area starts (9.19.0, `Screen.props.bodyTop`). `null` means there is no field (or a
  /// word this reader does not know): the body starts below the app bar, as before 9.19.0.
  final BodyTop? bodyTop;

  /// Largest content width (9.18.0, `Screen.contentMaxWidth`): the app bar, body, pinned block and the
  /// navigation bar's items form a column no wider than this number, centered. The background of the root
  /// and of the zones runs edge to edge. `null` means there is no field.
  final int? contentMaxWidth;

  /// Where the root's children that do not stretch stand (9.15.0, `x-style.layout.alignment`).
  final AlignToken align;

  /// How the BODY's children are laid out top to bottom when the content is shorter than the visible
  /// body.
  final JustifyToken justify;

  /// Gap between the root's children (9.0.0). It is the layout of CHILDREN, hence `props` rather than
  /// `style`; the field's default is `sm`, as in `Column`.
  final FieldSpacing gap;
}

/// A node that may stand in `children`: everything except [ScreenNode].
sealed class ChildNode extends UiNode {
  const ChildNode({
    required super.id,
    this.visibleIf,
    this.hiddenByClass = false,
    super.style,
    super.styleWhen,
    this.fill = false,
    this.weight,
    this.layer,
    this.motion,
    this.pull,
    this.pin = false,
  });

  /// The display condition from the document (5.0.0). `null` means the node is always shown.
  ///
  /// It lies on the base class rather than on each node: in the schema this is a field of the node itself,
  /// common to all child types, and the renderer may check it once without asking which widget this is.
  final VisibilityCondition? visibleIf;

  /// A LAYER OVER THE WHOLE STACK (8.14.0). `false` means the node takes its own size.
  ///
  /// It lies on the base class for the same reason as [visibleIf] and [style]: in the schema this is a
  /// field of the node ITSELF, common to all child types. It acts only inside a `Stack`: elsewhere there
  /// is nothing to fill, and the builder does not produce such a document.
  ///
  /// Why not `bool?`: the contract has one value (`true`), and its absence is the "ordinary layer".
  /// Keeping a third state would distinguish "not stretched" from "not mentioned", though they are drawn
  /// the same.
  final bool fill;

  /// A SHARE OF THE ROW WIDTH (8.17.0). `null` means the node takes its own width.
  ///
  /// It lies on the base class for the same reason as [visibleIf], [style] and [fill]: in the schema this
  /// is a field of the node ITSELF, common to all child types. It acts only where the row width is finite:
  /// in a `Row` without `wrap` and without `scrollable`, and in a `Container` with `direction: row`;
  /// elsewhere there is nothing to divide, and the builder does not produce such a document.
  ///
  /// Why `int?` and not an `int` defaulting to 1: "no weight" and "weight 1" are DIFFERENT things. A
  /// child without a weight takes its natural width and takes no part in the division at all, whereas
  /// weight 1 means "one share of the sum". In a row with children 2 and 1 the difference is visible: with
  /// a default of 1, a third child without a weight would take a quarter, but it must take exactly as much
  /// as its content needs.
  final int? weight;

  /// THE PLACE OF A LAYER IN A STACK (9.10.0): its own alignment, offset, rotation. `null` means there is
  /// no field or it is not an object (`unreadableLayer`: an ordinary layer). This is only what the
  /// document says; whether it is read HERE is decided by [readerLayerOf].
  final LayerPlacement? layer;

  /// AN ENDLESS MOTION of the node (9.20.0, `motion`): `null` means there is no field or it is not a form this
  /// reader can draw, and the node stands. It is a paint transform only; it never changes the layout.
  final NodeMotion? motion;

  /// PULLING IN THE FLOW (9.10.0): a spacing reference. `null` means there is no field or it is
  /// unreadable (`unreadablePull`). Whether it is read HERE is decided by [effectivePull].
  final ScaleRef? pull;

  /// PINNED TO THE BOTTOM (9.12.0, `pin: 'bottom'`): only the word `bottom` is read, anything else means
  /// no field (`unreadablePin`). This is what the document says; whether the node really stands in the
  /// bottom zone is decided by `screenChildrenByZone` from its place in the root (`pinElsewhere`).
  final bool pin;

  /// The node is HIDDEN BY THE WIDTH CLASS (9.18.0, `showOn`): the tree is resolved for one class, and that
  /// class is not in the node's list. `false` means there is no field.
  ///
  /// This is the second half of the question "is the node visible", independent of the data condition: a
  /// class does not show what a condition hid, and vice versa. It is answered by [isVisible], the ONE
  /// place that the screen zones, app bar actions, navigation items, numbering, form, tabs, stack layers,
  /// row weights and carousel cards all go through.
  final bool hiddenByClass;

  /// The press of a container (9.19.0): `null` for every node but a `Column`, `Row`, `Container` or `Stack`
  /// that holds an action which does something. Such a node is a card that is a button on the finished
  /// screen.
  PressTarget? get press => null;

  /// Whether the node is NOT ALWAYS shown: it has a data condition or is hidden by the class.
  bool get hasVisibilityRule => visibleIf != null || hiddenByClass;

  /// Whether to show the node on this data: the width class AND the data condition.
  bool isVisible(ScreenData data) => !hiddenByClass && (visibleIf?.evaluate(data) ?? true);
}

/// A node whose type the app does not know (or a node of a broken shape).
final class UnknownNode extends ChildNode {
  const UnknownNode({
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
    required this.type,
    required this.children,
  });

  @override
  final List<ChildNode> children;
  final String type;
}
