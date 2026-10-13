import 'dart:math' as math;

import 'package:flutter/painting.dart' show Axis;

import 'node.dart';
import 'offset_rules.dart';
import 'style_values.dart';
import 'tokens.dart';

/// Layout rules that the document's shape does not state; mirror of the builder's
/// `layout-rules.ts` (`x-style.layout` in the schema artifact).
///
/// Each rule here exists because the policy already had a word for it (`row-viewport`, `start-top`,
/// `clip`) but the word referred to a notion the artifact did not define ("stretching content", "tight
/// slot", "sized box"). Every notion is now a LIST in the contract, and the function here answers
/// according to that list.
///
/// The functions cannot drift from the artifact: `test/layout_rules_test.dart` builds a node for EVERY
/// row of the artifact's list, asks the function, and then checks that it says no for neighbouring
/// nodes.

/// Stretching content of a scrollable row (`scrollableRowChildWidth: 'row-viewport'`,
/// `x-style.layout.scrollableRow.stretchToViewport`).
///
/// Every child of such a row is at most as wide as the row's viewport (or its own `style.width`, if
/// larger). Most children take their NATURAL width and scroll; the ones listed here take the whole
/// viewport width: they have no natural width, and without the list one reader would draw them with zero
/// width and another with infinite width.
///
/// EXACTLY FIVE CONDITIONS: `Button{fullWidth}`, horizontal `Divider`, horizontal `Spacer`,
/// `ProgressBar`, `Grid`. Everything else (including `CircularProgress`, `Image`, `ListTile`, `Text`)
/// has natural width.
bool stretchesToRowViewport(ChildNode node) => switch (node) {
  ButtonNode(:final fullWidth) => fullWidth,
  DividerNode(:final orientation) => orientation == OrientationToken.horizontal,
  SpacerNode(:final orientation) => orientation == OrientationToken.horizontal,
  ProgressBarNode() => true,
  GridNode() => true,
  _ => false,
};

/// Tight slot (`sizedChildInTightSlot: 'start-top'`, `x-style.layout.tightSlots`): a parent that
/// itself dictates the child's size, i.e. a grid cell and an instance of a repeater laid out in
/// columns. A child with its own width or height is neither stretched nor centered there; it sits at the
/// logical start, at the top.
bool isTightSlotParent(ChildNode? parent) => switch (parent) {
  GridNode() => true,
  RepeaterNode(:final columns) => columns != null,
  _ => false,
};

/// Column parent (`columnChildWidth: 'stretch-unless-natural'`, `x-style.layout.column.parents`):
/// a node whose children are stretched to the content width.
///
/// `Screen`, `Column`, `Container{direction: column}`, `Tab`, `Accordion`, `ChoiceGroup`. `Repeater` is
/// NOT included: laid out as a column it always stretches the instance, with no exception for
/// [hasNaturalColumnWidth]. An unknown node is drawn with the same column but does not belong to the
/// list.
bool isColumnParent(UiNode node) => switch (node) {
  ScreenNode() => true,
  ColumnNode() => true,
  ContainerNode(:final direction) => direction == ContainerDirectionToken.column,
  TabNode() => true,
  AccordionNode() => true,
  ChoiceGroupNode() => true,
  _ => false,
};

/// Natural width of a column child (`x-style.layout.column.naturalWidth`).
///
/// The other children of a column are stretched to the parent's content width minus their own `margin`;
/// these take their content width and are placed by the parent's `align` (for a parent without that
/// prop, at the logical start, `naturalWidthAlign`). A list, not "something similar": `Text` and `Image`
/// are stretched, and so are `Column` and `Container`. A node with its own `style.width` gets natural
/// width regardless of type (`ownWidth: 'natural-width'`); the renderer checks that itself because it
/// depends on the data.
bool hasNaturalColumnWidth(ChildNode node) => switch (node) {
  ButtonNode(:final fullWidth) => !fullWidth,
  // Since 9.5.0: the icon button is a circle of its own size; in a row it is `rigid`.
  IconButtonNode() => true,
  BadgeNode() => true,
  IconNode() => true,
  CircularProgressNode() => true,
  DividerNode(:final orientation) => orientation == OrientationToken.vertical,
  SpacerNode(:final orientation) => orientation == OrientationToken.vertical,
  _ => false,
};

/// Scalar rows of `x-style.layout.column`, mirrored for the test against the artifact (the `parents`
/// and `naturalWidth` lists are mirrored by the functions above).
const Map<String, Object?> kColumnLayout = {
  'childWidth': 'parent-content-minus-own-margin',
  // A column without a definite width (in a row without a weight, in a scrollable row, a stack layer
  // without `fill`) is as wide as its widest NATURAL child including that child's `margin`; stretched
  // children align to it. [StretchColumn] does this by measuring the children in two passes.
  'childWidthWithoutDefiniteParent': 'widest-natural',
  'ownWidth': 'natural-width',
  'naturalMaxWidth': 'parent-content',
  'naturalWidthAlign': {'prop': 'align', 'withoutProp': 'start'},
  'constrainedStretch': 'clamp-then-same-align',
};

/// Natural width in a tight slot (`naturalWidthInTightSlot: 'natural-start-top'`,
/// `x-style.layout.tightSlotNaturalWidth`): in a `Grid` cell and an instance of `Repeater{columns}`, a
/// child from [hasNaturalColumnWidth] (the same list as the column's, hence the value) without an
/// effective own width takes its natural width and sits at the start, at the top.
const String kTightSlotNaturalWidth = 'column.naturalWidth';

/// A row share includes the node's margins (`x-style.weightShareIncludes`): the remainder of the row
/// is divided by weights, `margin` lies inside the share, and the box lies inside the margin. In code
/// this is the order `Expanded` then `Padding`; the two cannot be swapped.
const List<String> kWeightShareIncludes = ['margin'];

/// Built-in badge padding (`x-style.layout.badgePadding`): `xs` vertically, `sm` horizontally. Mirror
/// of the builder's `BADGE_PADDING`; `padding` from `style` replaces them entirely.
const SpacingToken kBadgePaddingBlock = SpacingToken.xs;
const SpacingToken kBadgePaddingInline = SpacingToken.sm;

/// Built-in button geometry: `sm` vertical and `md` horizontal padding, label in the `titleS` style.
/// Mirror of the canvas rule `.preview-button` and of `BUTTON_BLOCK_SPACING` /
/// `BUTTON_INLINE_SPACING` in the builder's preview model; `padding` and `typography` from `style` each
/// replace their part.
///
/// The numbers are in the artifact (`x-style.layout.buttonPadding`, `buttonTypography`,
/// `buttonSize: 'label-plus-padding-plus-border'`): a button's size is label plus padding plus border,
/// with no minimum size and no invisible touch padding. Material's button geometry (padding 24, label
/// 14/500, minimum 64x40, an invisible 48 around the finger) would make every button a different size
/// from the one on the canvas.
const SpacingToken kButtonPaddingBlock = SpacingToken.sm;
const SpacingToken kButtonPaddingInline = SpacingToken.md;
const TypographyToken kButtonTypography = TypographyToken.titleS;

/// Button size (since 9.5.0, `Button.size`, `IconButton.size`): `sm` / `md` / `lg`.
///
/// A missing field, a non-string value or an unknown word (a newer minor) gives [kDefaultButtonSize]
/// from `x-style.layout.defaultButtonSize`, NOT a schema default: in `$defs.ButtonProps` the field has
/// deliberately no `default` (a parse that appended a default would change every document it reads).
enum ButtonSizeToken {
  sm,
  md,
  lg;

  static ButtonSizeToken parse(Object? raw) {
    for (final size in values) {
      if (size.name == raw) return size;
    }
    return kDefaultButtonSize;
  }
}

/// `x-style.layout.defaultButtonSize`.
const ButtonSizeToken kDefaultButtonSize = ButtonSizeToken.md;

/// Geometry of one button size, in theme tokens rather than pixels.
typedef ButtonSizeGeometry = ({SpacingToken block, SpacingToken inline, TypographyToken typography});

/// Button size table (`x-style.layout.buttonSizes`); mirror of the builder's `BUTTON_SIZE_GEOMETRY`.
/// The `md` row is exactly the button before 9.5.0 ([kButtonPaddingBlock], [kButtonPaddingInline],
/// [kButtonTypography]). With the built-in theme the height without a border is 28 / 40 / 48.
///
/// The icon button uses the same table (`iconButton.sizes: 'buttonSizes'`): its side equals the height of
/// a button of the same size, so a "back" button sits level with "Continue" with no manual alignment.
const Map<ButtonSizeToken, ButtonSizeGeometry> kButtonSizes = {
  ButtonSizeToken.sm: (block: SpacingToken.xs, inline: SpacingToken.md, typography: TypographyToken.bodyM),
  ButtonSizeToken.md: (block: kButtonPaddingBlock, inline: kButtonPaddingInline, typography: kButtonTypography),
  ButtonSizeToken.lg: (block: SpacingToken.md, inline: SpacingToken.lg, typography: TypographyToken.titleM),
};

/// Geometry of a size; mirror of `buttonGeometryOf`.
ButtonSizeGeometry buttonGeometryOf(ButtonSizeToken size) => kButtonSizes[size]!;

/// Icon button geometry (`x-style.layout.iconButton`), mirrored for the test against the artifact.
/// The content box is a square whose side is the line height of the size, the glyph is a square of the
/// font size, the padding is the vertical padding of a button of that size on ALL sides, the radius is
/// `pill`.
const Map<String, String> kIconButtonLayout = {
  'sizes': 'buttonSizes',
  'contentBox': 'typography-line-height-square',
  'glyph': 'typography-font-size',
  'padding': 'buttonSizes.padding.block',
  'radius': 'pill',
};

/// Icon position next to text (since 9.5.0) is LOGICAL: `start` is before the text in the writing
/// direction, `end` after it. In RTL `start` is on the right; the row direction (`Row` under
/// `Directionality`) swaps the sides, not reader code.
///
/// A missing field or an unknown word gives [kDefaultIconPosition]
/// (`iconBesideText.defaultPosition`).
enum IconPositionToken {
  start,
  end;

  static IconPositionToken parse(Object? raw) => raw == 'end' ? end : kDefaultIconPosition;
}

/// `x-style.layout.iconBesideText.defaultPosition`.
const IconPositionToken kDefaultIconPosition = IconPositionToken.start;

/// The "icon beside text" rule (`x-style.layout.iconBesideText`) is ONE rule for three places: the
/// button label, the badge label and the trailing text slot of a list tile. This is the gap between the
/// icon box and the text.
const SpacingToken kIconBesideTextGap = SpacingToken.xs;

/// Scalar rows of the rule, mirrored for the test against the artifact. Behaviour is held by the case
/// table `fixtures/icon-text/icon-text-cases.json`.
const Map<String, Object?> kIconBesideText = {
  'gap': 'xs',
  // The icon box is centered on the center of the text LINE, not on the baseline.
  'crossAlign': 'center',
  // The color of the text the icon sits next to; the icon has none of its own.
  'color': 'text',
  'order': 'logical',
  'textGlyphBox': {'inline': 'text-font-size', 'block': 'text-line-height'},
  'defaultPosition': 'start',
};

/// Built-in color of a list tile's trailing text and the icon beside it
/// (`x-style.layout.listTileTrailingColor`). Both are `onSurface`, not the muted color, so "120 JOD" at
/// the end of a row looks the same as on the canvas.
const ColorToken kListTileTrailingColor = ColorToken.onSurface;

/// The three policy rows of 9.5.0; the test checks them against the artifact.
const Map<String, String> kIconTextPolicy = {
  'unknownIconBesideText': 'empty-box-keeps-gap',
  'emptyTextBesideIcon': 'keep-icon-and-gap',
  'iconButtonWithoutLabel': 'draw-and-name-by-icon',
};

/// Whether there is an icon in this place: as soon as the field is NAMED with a non-`null` value,
/// even a name outside the set or a non-string (then an empty box, `unknownIconBesideText`). Mirror of
/// `hasIconBesideText`.
IconToken? iconBesideTextOf(Object? raw) => raw == null ? null : IconToken.parse(raw);

/// Order of the parts in the writing direction; mirror of `iconBesideTextOrder`.
List<String> iconBesideTextOrder({required bool hasIcon, required IconPositionToken position}) => !hasIcon
    ? const ['text']
    : position == IconPositionToken.end
    ? const ['text', 'icon']
    : const ['icon', 'text'];

/// Accessible name of an icon button (`iconButtonWithoutLabel: 'draw-and-name-by-icon'`); mirror of
/// `iconButtonNameOf`. [label] is the label AFTER translation and data substitution. If it is empty
/// (or only whitespace), the name becomes the icon name in words: `chevron-left` gives "chevron left".
/// If the icon is not a string ([iconName] is `null`), there is no name at all; the button is still
/// drawn.
String iconButtonNameOf(String label, String? iconName) {
  if (!isSilentAccessibleName(label)) return label;
  return iconName == null ? '' : iconName.replaceAll('-', ' ').trim();
}

/// Class of "silent" characters in a name (`x-accessibleName`): whitespace, Unicode format and control
/// characters (`Cf`, `Cc`), combining marks (`Mn`, `Me`) and the five blank fillers that Unicode counts
/// as letters or symbols (U+3164, U+115F, U+1160, U+FFA0, U+2800). A string with nothing left after
/// removing them gives no name because a screen reader would not speak it; a letter with a combining
/// accent is heard, because its base stays. Dart's `trim()` does not know most of them, so the class is
/// named by the contract rather than left to the platform.
const String kSilentCharactersPattern = r'[\s\p{Cf}\p{Cc}\p{Mn}\p{Me}\u3164\u115F\u1160\uFFA0\u2800]';

/// Flag for [kSilentCharactersPattern]: without `unicode`, Dart does not know `\p{Cf}`.
const bool kSilentCharactersUnicode = true;

final RegExp _silentCharacters = RegExp(kSilentCharactersPattern, unicode: kSilentCharactersUnicode);

/// Whether an accessible name is empty according to [kSilentCharactersPattern].
bool isSilentAccessibleName(String label) => label.replaceAll(_silentCharacters, '').isEmpty;

/// Alignment of a button label (`x-style.layout.buttonLabelAlign`): centered, including the second
/// line when the label wraps. Mirror of the key.
const String kButtonLabelAlign = 'center';

/// A row child without a weight (`unweightedRowChild: 'natural-shrink-proportionally'`,
/// `unweightedStretchInRow: 'share-of-one'`, `x-style.layout.row`): in a row that divides its width, a
/// child without a weight takes its natural width (on one line, no wider than the row's content) and
/// shrinks PROPORTIONALLY to that width when they do not fit together. A node with an effective
/// `style.width` (`ownWidth`) and widgets from [hasNaturalColumnWidth] (`rigid`) do not shrink.
/// Stretching content without a weight ([stretchesToRowViewport]) takes the remainder with the share
/// [kRowStretchShare], but only where shares APPLY; the shares divide what is left after the children
/// without a weight. `RowLayout` does the layout; the child kinds are `RowChildWidth` and `RowSlot`.
const Map<String, Object?> kRowLayout = {
  'unweightedWidth': 'single-line-content-max-row-content',
  'shrink': 'proportional-to-natural-width',
  'rigid': 'column.naturalWidth',
  'ownWidth': 'named-overflows-row',
  'stretch': 'scrollableRow.stretchToViewport',
  'stretchShare': kRowStretchShare,
  'shares': 'remainder-after-unweighted',
};

/// Share of stretching content without a weight (`x-style.layout.row.stretchShare`).
const double kRowStretchShare = 1;

/// Schema policy: a row child without a weight, and stretching content without a weight.
const String kUnweightedRowChild = 'natural-shrink-proportionally';
const String kUnweightedStretchInRow = 'share-of-one';

/// Sized box (`sizedBoxOverflow: 'clip'`, `x-style.layout.sizedBoxKeys`): only `width` and `height`;
/// `min...` and `max...` do not set a box, they constrain it.
const List<String> kSizedBoxKeys = ['width', 'height'];

/// What `style.width` / `height`, `min...` and `max...` include: the WHOLE box
/// (`x-style.sizeIncludes`). `margin` lies outside.
const List<String> kSizeIncludes = ['border', 'padding'];

/// Fields to which `unknownBoxToken` and `unknownSideToken` apply (`x-style.boxTokenFields`).
const List<String> kBoxTokenFields = ['padding', 'margin', 'radius'];

/// Which tab is open (`hiddenInitialTab` / `initialTabOutOfRange`, the builder's `openTabIndex`).
///
/// [initialTab] counts ALL tabs in document order, including ones hidden by a condition; `-1` means the
/// value is not a non-negative integer (a string, a fraction, a negative). If the named tab is hidden,
/// or the number is out of range, the FIRST VISIBLE tab opens. `null` means there are no visible tabs.
///
/// [visible] says whether the i-th tab of the document is visible now.
int? openTabIndex(int initialTab, List<bool> visible) {
  if (initialTab >= 0 && initialTab < visible.length && visible[initialTab]) return initialTab;
  final first = visible.indexOf(true);
  return first == -1 ? null : first;
}

// Overlay with offset (9.10.0)

/// `fill` applies only to a DIRECT child of a stack (`fillOutsideStack: 'ignore'`).
bool effectiveFill(ChildNode node, UiNode? parent) => node.fill && parent is StackNode;

/// The reader's view of an overlay (`x-style.layout.layer`): the layer placement, or `null` when the
/// node is an ordinary layer. Mirror of the builder's `readerLayerOf`.
///
/// Conditions: the parent is a `Stack` and the node is its DIRECT child (`layerOutsideStack`); not
/// `fill` (`layerOnFill: fill-wins`); the value is an object (`unreadableLayer`); the stack has at least
/// one layer that is neither an overlay nor stretched (`noSizingLayer: ignore-layer`; otherwise the field
/// is read by NO layer, not "by all but the first"). [siblings] are all visible children of the stack.
LayerPlacement? readerLayerOf(ChildNode node, UiNode? parent, {Iterable<ChildNode>? siblings}) {
  if (parent is! StackNode) return null;
  if (effectiveFill(node, parent) || node.layer == null) return null;
  final layers = siblings ?? parent.children;
  final sized = layers.any((layer) => !effectiveFill(layer, parent) && layer.layer == null);
  return sized ? node.layer : null;
}

/// Whether a layer SETS the stack's size: it is not stretched (a stretched layer takes the size) and
/// not an overlay (an overlay is placed relative to the finished box).
bool sizesStack(ChildNode node, UiNode? parent, {Iterable<ChildNode>? siblings}) =>
    !effectiveFill(node, parent) && readerLayerOf(node, parent, siblings: siblings) == null;

/// The flow axis along which a child of this parent can be pulled (`pullAxisOf`), or `null` if the
/// parent does not accept pulling (`pullOutsideFlow: 'ignore'`). `Screen` and `Column` are a column;
/// `Container` follows `direction`; `Row` is a row, but not with wrapping or scrolling: there the
/// "previous" sibling may be in another line or before the start of the scroll.
Axis? pullAxisOf(UiNode? parent) => switch (parent) {
  ScreenNode() || ColumnNode() => Axis.vertical,
  ContainerNode(:final direction) => direction == ContainerDirectionToken.row ? Axis.horizontal : Axis.vertical,
  RowNode(:final wrap, :final scrollable) => !wrap && !scrollable ? Axis.horizontal : null,
  _ => null,
};

/// Whether a row of this parent divides its width by weights (`acceptsWeightedChildren`): `Row`
/// without `wrap` and `scrollable`, and `Container{direction: row}`.
bool _acceptsWeightedChildren(UiNode? parent) => switch (parent) {
  RowNode(:final wrap, :final scrollable) => !wrap && !scrollable,
  ContainerNode(:final direction) => direction == ContainerDirectionToken.row,
  _ => false,
};

/// How far the node is pulled (`effectivePull`): a reference to a spacing step, or `null` when pulling
/// does not apply: outside the flow, on an app bar, on a node with an effective weight
/// (`pullWithWeight: weight-wins`), and with an unreadable value (`node.pull` is already `null`). The
/// parser gave `node.weight` only as an integer >= 1.
ScaleRef? effectivePull(ChildNode node, UiNode? parent) {
  if (node.pull == null || pullAxisOf(parent) == null) return null;
  // The app bar is a screen zone, not a flow child (`pull.onAppBar: 'ignore'`): the field is not read
  // on it and the next sibling does not move.
  if (node is AppBarNode) return null;
  if (node.weight != null && _acceptsWeightedChildren(parent)) return null;
  return node.pull;
}

// Alignment of children on both axes (9.15.0)

/// Main axis of a 9.15.0 host: `block` is top to bottom, `inline` is along the writing line
/// (`x-style.layout.alignment.hosts`).
enum AlignmentMainAxis { block, inline }

/// Where a column's height larger than its content comes from
/// (`alignment.main.column.heightSources`).
enum ColumnHeightSource {
  /// A layer stretched over the whole stack; it is stronger than `style.height`.
  fill('fill'),
  styleHeight('style.height'),
  styleMinHeight('style.minHeight');

  const ColumnHeightSource(this.wire);
  final String wire;
}

/// Words of the cross axis without the field (`alignment.cross.*.withoutProp`).
const AlignToken kCrossAlignBlockWithoutProp = AlignToken.start;
const AlignToken kCrossAlignInlineWithoutProp = AlignToken.center;
const JustifyToken kJustifyWithoutProp = JustifyToken.start;

/// Host: the node's main axis, or `null` when the node has no 9.15.0 fields. `Row` is not in the list:
/// its fields are older and have schema defaults.
AlignmentMainAxis? alignmentMainAxisOf(UiNode node) => switch (node) {
  ScreenNode() || ColumnNode() => AlignmentMainAxis.block,
  ContainerNode(:final direction) =>
    direction == ContainerDirectionToken.row ? AlignmentMainAxis.inline : AlignmentMainAxis.block,
  _ => null,
};

/// Host's cross-axis word AFTER "as without the field". A node without the fields gets the column's
/// word (`start`), as in the reference implementation for a non-host.
AlignToken crossAlignOf(UiNode node) => switch (node) {
  ScreenNode(:final align) => align,
  ColumnNode(:final align) => align,
  ContainerNode(:final align) => align,
  _ => kCrossAlignBlockWithoutProp,
};

/// Host's main-axis word AFTER "as without the field".
JustifyToken mainJustifyOf(UiNode node) => switch (node) {
  ScreenNode(:final justify) => justify,
  ColumnNode(:final justify) => justify,
  ContainerNode(:final justify) => justify,
  _ => kJustifyWithoutProp,
};

/// What gives a column a height larger than its content: `fill` (a stack layer), an effective
/// `style.height`, an effective `style.minHeight`, and nothing else (`null` means height by content). A
/// grid cell, a row, a tab and a repeater give no height.
///
/// [height] and [minHeight] say whether the EFFECTIVE style (with state, after checking a data-driven
/// value) names these sizes; the caller must already have resolved the style.
ColumnHeightSource? columnHeightSourceOf(
  ChildNode node,
  UiNode? parent, {
  required bool height,
  required bool minHeight,
}) {
  if (effectiveFill(node, parent)) return ColumnHeightSource.fill;
  if (height) return ColumnHeightSource.styleHeight;
  if (minHeight) return ColumnHeightSource.styleMinHeight;
  return null;
}

/// Whether the host's main axis CAN have free space; `null` means the node is not a host. A row and a
/// screen body always can (the layout knows how much); a column only with a height source.
bool? mainAxisSpaceOf(
  UiNode node,
  UiNode? parent, {
  required bool height,
  required bool minHeight,
}) {
  final axis = alignmentMainAxisOf(node);
  if (axis == null) return null;
  if (node is ScreenNode) return true;
  if (axis == AlignmentMainAxis.inline) return true;
  return columnHeightSourceOf(node as ChildNode, parent, height: height, minHeight: minHeight) != null;
}

/// By how much each of [count] children is shifted along the main axis from the place given by
/// `start`. [free] <= 0 or infinite means "none". The gap is not included. Numbers are not rounded.
List<double> mainAxisShifts(double free, int count, JustifyToken justify) {
  final space = free.isFinite ? (free > 0 ? free : 0.0) : 0.0;
  return List<double>.generate(count < 0 ? 0 : count, (index) {
    switch (justify) {
      case JustifyToken.center:
        return space / 2;
      case JustifyToken.end:
        return space;
      case JustifyToken.between:
        return count > 1 ? space * index / (count - 1) : 0.0;
      case JustifyToken.start:
        return 0.0;
    }
  });
}

/// Offset of a child of size [size] from the START of the cross axis in a space of size [available].
double crossAxisOffset(double available, double size, AlignToken align) {
  final space = available - size > 0 ? available - size : 0.0;
  return switch (align) {
    AlignToken.center => space / 2,
    AlignToken.end => space,
    AlignToken.start => 0.0,
  };
}

/// Free space of a screen body: the height of the body area minus the length of what scrolls in it
/// (including the body's padding). A body that scrolls has no free space.
double screenBodyFreeSpace({required double bodyHeight, required double contentHeight}) {
  final free = bodyHeight - contentHeight;
  return free > 0 ? free : 0.0;
}

/// A host's child for [alignedChildRects]: its size including its own `margin`.
class AlignedChild {
  const AlignedChild(this.width, this.height, {this.stretch = false});
  final double width;
  final double height;

  /// A stretched column child: its width is the host's content width.
  final bool stretch;
}

/// A child's rectangle; `x` is measured from the LEFT edge of the content box in both directions.
class AlignedRect {
  const AlignedRect(this.x, this.y, this.width, this.height);
  final double x;
  final double y;
  final double width;
  final double height;
}

/// Where a host's children stand in its content box (numbers are not rounded). [block] is the named
/// height (`style.height`, `fill`); [minBlock] is `minHeight` (read only on the `block` main axis).
({double block, double free, List<AlignedRect> rects}) alignedChildRects({
  required AlignmentMainAxis axis,
  required double inline,
  double? block,
  double? minBlock,
  required double gap,
  required AlignToken align,
  required JustifyToken justify,
  required bool rtl,
  required List<AlignedChild> children,
}) {
  final gaps = gap * (children.length > 1 ? children.length - 1 : 0);
  double fromLeft(double start, double width) => rtl ? inline - start - width : start;
  if (axis == AlignmentMainAxis.block) {
    final content = children.fold<double>(0, (sum, child) => sum + child.height) + gaps;
    final boxBlock = block ?? ((minBlock ?? 0) > content ? minBlock! : content);
    final free = boxBlock - content > 0 ? boxBlock - content : 0.0;
    final shifts = mainAxisShifts(free, children.length, justify);
    var cursor = 0.0;
    final rects = <AlignedRect>[];
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final width = child.stretch ? inline : (child.width < inline ? child.width : inline);
      final y = cursor + shifts[i];
      cursor += child.height + gap;
      rects.add(AlignedRect(fromLeft(crossAxisOffset(inline, width, align), width), y, width, child.height));
    }
    return (block: boxBlock, free: free, rects: rects);
  }
  final content = children.fold<double>(0, (sum, child) => sum + child.width) + gaps;
  final tallest = children.fold<double>(0, (most, child) => child.height > most ? child.height : most);
  final boxBlock = block ?? tallest;
  final free = inline - content > 0 ? inline - content : 0.0;
  final shifts = mainAxisShifts(free, children.length, justify);
  var cursor = 0.0;
  final rects = <AlignedRect>[];
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    final start = cursor + shifts[i];
    cursor += child.width + gap;
    rects.add(AlignedRect(fromLeft(start, child.width), crossAxisOffset(boxBlock, child.height, align), child.width, child.height));
  }
  return (block: boxBlock, free: free, rects: rects);
}

// Own glyph size (9.16.0)

/// Range of the `glyphSize` field (`x-style.layout.ownGlyphSize.range`).
const int kGlyphSizeMin = 8;
const int kGlyphSizeMax = 128;

/// The effective value of `glyphSize`: an integer within the range, or `null` (no field, so the `size`
/// word applies). A fraction, an out-of-range number, a string and `null` are not read.
int? ownGlyphSizeOf(Object? raw) {
  if (raw is! num || !raw.isFinite) return null;
  if (raw != raw.truncate()) return null;
  final value = raw.toInt();
  return value >= kGlyphSizeMin && value <= kGlyphSizeMax ? value : null;
}

/// Box and glyph of a widget with its own glyph size (`iconGeometryOf` /
/// `iconButtonGeometryOf`).
class GlyphGeometry {
  const GlyphGeometry({
    required this.glyph,
    required this.contentInline,
    required this.contentBlock,
    required this.boxInline,
    required this.boxBlock,
    required this.own,
  });

  /// Side of the glyph square.
  final double glyph;

  /// Content box (without padding and border).
  final double contentInline;
  final double contentBlock;

  /// Node box (with padding and border).
  final double boxInline;
  final double boxBlock;

  /// The glyph is named by a number.
  final bool own;
}

GlyphGeometry _glyphGeometry({
  required Object? glyphSize,
  required double fontSize,
  required double paddingInline,
  required double paddingBlock,
  required double borderWidth,
  double? width,
  double? height,
  required double wordInline,
  required double wordBlock,
}) {
  final own = ownGlyphSizeOf(glyphSize);
  final insetInline = paddingInline + 2 * borderWidth;
  final insetBlock = paddingBlock + 2 * borderWidth;
  final naturalInline = own?.toDouble() ?? wordInline;
  final naturalBlock = own?.toDouble() ?? wordBlock;
  final contentInline = width == null ? naturalInline : math.max(0.0, width - insetInline);
  final contentBlock = height == null ? naturalBlock : math.max(0.0, height - insetBlock);
  final boxInline = width ?? contentInline + insetInline;
  final boxBlock = height ?? contentBlock + insetBlock;
  // With a word: the glyph is the font size, and a named box does not constrain it.
  if (own == null) {
    return GlyphGeometry(
      glyph: fontSize,
      contentInline: contentInline,
      contentBlock: contentBlock,
      boxInline: boxInline,
      boxBlock: boxBlock,
      own: false,
    );
  }
  final glyph = math.min(
    own.toDouble(),
    math.min(width == null ? own.toDouble() : contentInline, height == null ? own.toDouble() : contentBlock),
  );
  return GlyphGeometry(
    glyph: glyph,
    contentInline: contentInline,
    contentBlock: contentBlock,
    boxInline: boxInline,
    boxBlock: boxBlock,
    own: true,
  );
}

/// Reference implementation: box and glyph of the "Icon" widget. Without a number, the box is "font
/// size by line" (`iconGlyphBox`) and the glyph is the font size; with a number, a square of that
/// number.
GlyphGeometry iconGeometryOf({
  Object? glyphSize,
  required double fontSize,
  required double lineHeight,
  double paddingInline = 0,
  double paddingBlock = 0,
  double borderWidth = 0,
  double? width,
  double? height,
}) => _glyphGeometry(
  glyphSize: glyphSize,
  fontSize: fontSize,
  paddingInline: paddingInline,
  paddingBlock: paddingBlock,
  borderWidth: borderWidth,
  width: width,
  height: height,
  wordInline: fontSize,
  wordBlock: fontSize * lineHeight,
);

/// Reference implementation: box and glyph of an icon button. Without a number, a square of the line
/// height (`iconButton.contentBox`); with a number, a square of that number plus the same padding. The
/// box GROWS with the glyph; a named side clamps the glyph.
GlyphGeometry iconButtonGeometryOf({
  Object? glyphSize,
  required double fontSize,
  required double lineHeight,
  double paddingInline = 0,
  double paddingBlock = 0,
  double borderWidth = 0,
  double? width,
  double? height,
}) {
  final line = fontSize * lineHeight;
  return _glyphGeometry(
    glyphSize: glyphSize,
    fontSize: fontSize,
    paddingInline: paddingInline,
    paddingBlock: paddingBlock,
    borderWidth: borderWidth,
    width: width,
    height: height,
    wordInline: line,
    wordBlock: line,
  );
}
