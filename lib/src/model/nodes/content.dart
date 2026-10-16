/// Content nodes: spacer, divider, text, image, icon and badge.
part of '../node.dart';

final class SpacerNode extends ChildNode {
  const SpacerNode({
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
    required this.size,
    required this.orientation,
  });

  final FieldSpacing size;
  final OrientationToken orientation;
}

SpacerNode _parseSpacer(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return SpacerNode(
    id: node.leafId(),
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
    size: FieldSpacing.parse(props['size'], fieldDefault: SpacingToken.md),
    orientation: OrientationToken.parse(props['orientation']),
  );
}

final class DividerNode extends ChildNode {
  const DividerNode({
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
    required this.color,
    required this.spacing,
    required this.orientation,
  });

  /// The color of the LINE is part of the widget, hence in `props` and not in `style`: otherwise the
  /// divider would inherit the color of an ancestor's text.
  final FieldColor color;
  final FieldSpacing spacing;
  final OrientationToken orientation;
}

DividerNode _parseDivider(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return DividerNode(
    id: node.leafId(),
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
    // The default is `border`, not `muted`: in 7.3.0 the `border` token appeared precisely for dividers,
    // yet the field default stayed the color of secondary TEXT, so a document without `color` was drawn with
    // a dark line. The schema closed this gap (`DividerProps.color.default: "border"`), and the mirror must
    // follow it; otherwise two readers draw the same document differently again.
    color: FieldColor.parse(props['color'], fieldDefault: ColorToken.border),
    spacing: FieldSpacing.parse(props['spacing'], fieldDefault: SpacingToken.sm),
    orientation: OrientationToken.parse(props['orientation']),
  );
}

final class TextNode extends ChildNode {
  const TextNode({
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
    required this.content,
    required this.align,
    required this.maxLines,
    required this.overflow,
    this.spans = const {},
    this.marker = TextMarker.none,
  });

  /// The list item marker (9.17.0). [TextMarker.none] is plain text.
  final TextMarker marker;

  final BindableString content;
  final AlignToken align;
  final int? maxLines;
  final TextOverflowToken overflow;

  /// Styles of the parts of the string (9.6.0), as the reader read them: tolerantly, field by field.
  /// Whether each one applies is decided by `activeTextSpans` against `content`.
  final Map<String, TextSpanStyle> spans;
}

TextNode _parseText(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return TextNode(
    id: node.leafId(),
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
    content: BindableString.parse(props['content'], key: node.key('content')),
    align: AlignToken.parse(props['align']),
    maxLines: _intIn(props, 'maxLines', 1, 20),
    overflow: TextOverflowToken.parse(props['overflow']),
    spans: readTextSpans(props['spans']),
    // 9.17.0: a list item. A word outside the list, or a non-string, means no marker.
    marker: readTextMarker(props['marker']),
  );
}

final class ImageNode extends ChildNode {
  const ImageNode({
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
    required this.source,
    required this.aspectRatio,
    required this.alt,
    required this.fit,
  });

  final ImageSource source;
  /// The frame ratio (9.9.0): a word of the list or an own pair. It computes only a height from the
  /// width, and only when `style.height` is not named.
  final ImageRatio aspectRatio;
  final BindableString? alt;

  /// How the image lies in the frame (8.11.0).
  final ImageFitToken fit;
}

ImageNode _parseImage(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return ImageNode(
    id: node.leafId(),
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
    source: ImageSource.parse(props['source']),
    // 9.9.0: a word of the list or a `{ width, height }` pair; anything unreadable gives `16:9`.
    aspectRatio: ImageRatio.parse(props['aspectRatio']),
    alt: _altOf(props['alt'], node.key('alt')),
    // 8.11.0; the default `cover` is what was always done.
    fit: ImageFitToken.parse(props['fit']),
  );
}

final class IconNode extends ChildNode {
  const IconNode({
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
    required this.name,
    required this.size,
    required this.alt,
    this.glyphSize,
    this.iconPath,
  });

  final IconToken name;

  /// A data path that holds the name of the icon (9.19.0); the document's [name] is drawn when the data has none.
  final String? iconPath;
  final IconSizeToken size;

  /// The description for a screen reader (9.19.0): a string of the document, translated under the key of the field.
  final BindableString? alt;

  /// Own glyph size (9.16.0): an integer 8..128, or `null` when there is no field or it is not readable;
  /// then the [size] word draws.
  final int? glyphSize;
}

IconNode _parseIcon(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return IconNode(
    id: node.leafId(),
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
    // A field that is not there at all gives the field default from the artifact (`star`), as with all
    // props. A field that IS there and is not readable (an unknown name, an object, a number, `null`) is NOT
    // the default but an empty box: `unknownIcon` is stronger than `unknownToken` (9.3.0).
    name: props.containsKey('name') ? IconToken.parse(props['name']) : IconToken.star,
    size: IconSizeToken.parse(props['size']),
    alt: _altOf(props['alt'], node.key('alt')),
    glyphSize: ownGlyphSizeOf(props['glyphSize']),
    iconPath: iconPathOf(props['iconPath']),
  );
}

final class BadgeNode extends ChildNode {
  const BadgeNode({
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
    required this.label,
    required this.tone,
    this.icon,
    this.iconPath,
    this.iconPosition = kDefaultIconPosition,
  });

  final BindableString label;
  final BadgeToneToken tone;

  /// A data path that holds the name of the icon (9.19.0); read only when [icon] is there.
  final String? iconPath;

  /// An icon beside the label (9.5.0): the "chip" of mockups is a badge with an icon. The badge has no
  /// action, and none was added.
  final IconToken? icon;
  final IconPositionToken iconPosition;
}

BadgeNode _parseBadge(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return BadgeNode(
    id: node.leafId(),
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
    label: BindableString.parse(props['label'], key: node.key('label')),
    tone: BadgeToneToken.parse(props['tone']),
    icon: iconBesideTextOf(props['icon']),
    iconPath: iconPathOf(props['iconPath']),
    iconPosition: IconPositionToken.parse(props['iconPosition']),
  );
}
