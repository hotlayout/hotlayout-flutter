/// Layout nodes: column, row, container, grid, stack and the list from data.
part of '../node.dart';

final class ColumnNode extends ChildNode {
  const ColumnNode({
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
    this.press,
    required this.children,
    required this.gap,
    required this.align,
    this.justify = JustifyToken.start,
  });

  @override
  final List<ChildNode> children;

  @override
  final PressTarget? press;
  final FieldSpacing gap;
  final AlignToken align;

  /// Main axis (9.15.0): where the free space goes along the column. It applies only where there is any
  /// (`columnHeightSourceOf`).
  final JustifyToken justify;
}

ColumnNode _parseColumn(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return ColumnNode(
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
    press: readPressTarget(props, labelKey: node.key('label'), longPressLabelKey: node.key(kLongPressLabelKey)),
    children: node.childNodes(),
    gap: FieldSpacing.parse(props['gap'], fieldDefault: SpacingToken.sm),
    align: AlignToken.parse(props['align']),
    // 9.15.0: the column's main axis. Always read; it applies only with a height source.
    justify: _justifyWord(props['justify']),
  );
}

final class RowNode extends ChildNode {
  const RowNode({
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
    this.press,
    required this.children,
    required this.gap,
    required this.align,
    required this.justify,
    required this.wrap,
    required this.scrollable,
    this.carousel,
  });

  @override
  final List<ChildNode> children;

  @override
  final PressTarget? press;
  final FieldSpacing gap;
  final AlignToken align;
  final JustifyToken justify;
  final bool wrap;

  /// Carousel (9.11.0): scrolling snaps to cards, with dots under it. `null` means there is no field, the
  /// row does not scroll, or the field is not an object.
  final ReaderCarousel? carousel;

  /// A horizontal carousel (8.11.0).
  ///
  /// Together with [wrap] it is meaningless and DANGEROUS: scrolling gives the child infinite width, and a
  /// `Wrap` inside asks where to break, which is a crash on an undefined width rather than a spoiled look.
  /// The builder's validator rejects such a pair; here it is still possible (someone else may have built
  /// the document), so the render step decides it itself; see `_row`.
  final bool scrollable;
}

RowNode _parseRow(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return RowNode(
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
    press: readPressTarget(props, labelKey: node.key('label'), longPressLabelKey: node.key(kLongPressLabelKey)),
    children: node.childNodes(),
    gap: FieldSpacing.parse(props['gap'], fieldDefault: SpacingToken.sm),
    align: AlignToken.parse(props['align'], fallback: AlignToken.center),
    justify: JustifyToken.parse(props['justify']),
    wrap: _bool(props['wrap'], false),
    // 8.11.0. The field is absent from documents before 8.11.0, where it reads `false`, i.e. exactly what
    // the row always did.
    scrollable: _bool(props['scrollable'], false),
    // 9.11.0. The field is read only on a row that scrolls (`hosts`); elsewhere it is skipped
    // (`carouselOutsideHost: 'ignore'`).
    carousel: _bool(props['scrollable'], false) ? readCarousel(props['carousel']) : null,
  );
}

final class ContainerNode extends ChildNode {
  const ContainerNode({
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
    this.press,
    required this.children,
    required this.direction,
    required this.gap,
    this.align = AlignToken.start,
    this.justify = JustifyToken.start,
  });

  @override
  final List<ChildNode> children;

  @override
  final PressTarget? press;

  /// How a container lays out its children (8.1.0). The field is absent from documents before 8.1.0,
  /// where it reads `column`, i.e. what the container always did.
  final ContainerDirectionToken direction;

  final FieldSpacing gap;

  /// Cross axis (9.15.0): in a column, where the children that do not stretch stand; in a row, the
  /// vertical. The word ALREADY accounts for "as without the field" (column `start`, row `center`).
  final AlignToken align;

  /// Main axis (9.15.0): where the free space goes along the container's direction.
  final JustifyToken justify;
}

ContainerNode _parseContainer(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return ContainerNode(
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
    press: readPressTarget(props, labelKey: node.key('label'), longPressLabelKey: node.key(kLongPressLabelKey)),
    children: node.childNodes(),
    direction: ContainerDirectionToken.parse(props['direction']),
    gap: FieldSpacing.parse(props['gap'], fieldDefault: SpacingToken.none),
    // 9.15.0. Without the field (or with an unknown word) the cross axis is as it was: start in a column,
    // the vertical center in a row (`alignment.cross.*.withoutProp`).
    align: _alignWord(
      props['align'],
      ContainerDirectionToken.parse(props['direction']) == ContainerDirectionToken.row
          ? AlignToken.center
          : AlignToken.start,
    ),
    justify: _justifyWord(props['justify']),
  );
}

/// The grid (8.5.0): equal columns, the number of which the document names.
///
/// It differs from a [RowNode] with `wrap` by a statement, not by styling: wrapping says "as many as
/// fit" and depends on natural widths, whereas the grid names a NUMBER, so both readers lay it out the
/// same way.
final class GridNode extends ChildNode {
  const GridNode({
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
    required this.columns,
    required this.gap,
  });

  @override
  final List<ChildNode> children;

  /// How many cells per row. Always within the contract bounds; see `_gridColumns`.
  final int columns;

  /// One gap for both axes: between columns and between rows. That is what the contract says; it is not
  /// simplified here.
  final FieldSpacing gap;
}

GridNode _parseGrid(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return GridNode(
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
    // The column count is the ONE thing a grid cannot guess: without it the layout stops being the one the
    // screen's author saw. Broken data gives two columns, the schema default, and not "as many columns as
    // children": the latter would quietly turn the grid into a row.
    columns: _gridColumns(props['columns'], overridden: node.columnsFromOverride),
    gap: FieldSpacing.parse(props['gap'], fieldDefault: SpacingToken.sm),
  );
}

/// The stack (8.6.0): layers at one point, the first in the list is the lowest.
///
/// Two alignment fields rather than one, because a stack has no main axis: both are cross axes, so "a
/// badge in the top right corner" is two independent statements. Together they give the same nine
/// positions as `AlignmentDirectional`, without a nine-valued enum in the contract.
final class StackNode extends ChildNode {
  const StackNode({
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
    this.press,
    required this.children,
    required this.alignHorizontal,
    required this.alignVertical,
  });

  @override
  final List<ChildNode> children;

  @override
  final PressTarget? press;

  /// Where a layer narrower than the stack stands. `start`/`end` are logical, so in RTL they mirror with
  /// the text direction.
  final AlignToken alignHorizontal;

  /// Where a layer shorter than the stack stands: `start` is at the top, `end` at the bottom.
  final AlignToken alignVertical;

}

StackNode _parseStack(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return StackNode(
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
    press: readPressTarget(props, labelKey: node.key('label'), longPressLabelKey: node.key(kLongPressLabelKey)),
    children: node.childNodes(),
    alignHorizontal: AlignToken.parse(props['alignHorizontal'], fallback: AlignToken.center),
    alignVertical: AlignToken.parse(props['alignVertical'], fallback: AlignToken.center),
  );
}

/// A data-driven list (8.4.0): a single template, drawn once per record.
final class RepeaterNode extends ChildNode {
  const RepeaterNode({
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
    required this.source,
    required this.item,
    required this.direction,
    required this.gap,
    this.columns,
    this.limit,
    this.carousel,
    this.where,
    this.groupBy,
  });

  @override
  final List<ChildNode> children;

  /// The filter of the list (schema 9.23.0, `x-listFilter.where`), judged on each record in ITS scope; `null` means
  /// every record. A record that does not pass does not exist for the layout.
  final VisibilityCondition? where;

  /// Carousel (9.11.0): `null` means there is no field, it is out of place or not an object. A list
  /// with the field scrolls by itself.
  final ReaderCarousel? carousel;

  /// Grouping of the drawn records (9.26.0): the path of the RECORD whose value, equal for records that follow one
  /// another, makes a group. `null` means there is no field, or the list is not a column (a grid, a row and a
  /// carousel are not grouped: the document is drawn as without the field). With it the SECOND child of the list is
  /// the header of a group, drawn before each group in the scope of its first record.
  final String? groupBy;

  /// The header of a group (9.26.0): the second child, when the list is grouped.
  ChildNode? get groupHeader => groupBy == null || children.length <= kGroupHeaderIndex ? null : children[kGroupHeaderIndex];

  /// Path to the collection in the data.
  final String source;

  /// The name under which a record lies in the template's scope.
  final String item;

  final ContainerDirectionToken direction;
  final FieldSpacing gap;

  /// How many instances stand IN A ROW (8.13.0).
  ///
  /// `null` means one per row (or all side by side if `direction: 'row'`), i.e. as the repeater always
  /// drew. Together with `direction: 'row'` this is a contradiction that the builder does not produce;
  /// here the GRID wins; see `_repeater`.
  final int? columns;

  /// How many records to show. `null` means all, as many as the contract limit allows.
  final int? limit;
}

RepeaterNode _parseRepeater(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final id = node.id;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return RepeaterNode(
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
    source: props['source'] is String ? props['source'] as String : '',
    // The prefix comes from the document and is not derived from the collection name: the data dictionary
    // lives in the builder and does not reach the contract.
    item: props['item'] is String ? props['item'] as String : '',
    direction: ContainerDirectionToken.parse(props['direction']),
    gap: FieldSpacing.parse(props['gap'], fieldDefault: SpacingToken.sm),
    // A number outside the contract bounds is clamped, not rejected, exactly as in `Grid`: the document
    // DESCRIBES a grid, and drawing it with the maximum is closer to the intent than drawing a column.
    columns: props['columns'] == null ? null : _gridColumns(props['columns'], overridden: node.columnsFromOverride),
    limit: _intIn(props, 'limit', 1, kMaxRepeaterItems),
    where: props['where'] is Map ? _listWhere(props['where']) : null,
    // 9.26.0. A column only: with `columns` (any class) or in a row the field is not read.
    groupBy: props['columns'] == null && ContainerDirectionToken.parse(props['direction']) != ContainerDirectionToken.row
        ? readGroupBy(props[kGroupByKey])
        : null,
    // 9.11.0. The host is a list into a row WITHOUT `columns`: a grid does not read the direction at all,
    // and it is never a carousel.
    carousel: props['columns'] == null && ContainerDirectionToken.parse(props['direction']) == ContainerDirectionToken.row
        ? readCarousel(props['carousel'])
        : null,
  );
}

/// `Repeater.where`: any form of a condition except the emptiness of a filtered list ("a filter does not carry a
/// filter"). One that cannot be read lets every record through, as a condition nobody could understand does anywhere.
VisibilityCondition? _listWhere(Object? raw) {
  final condition = VisibilityCondition.parse(raw);
  return condition is FilteredEmptinessCondition ? const AlwaysVisibleCondition() : condition;
}
