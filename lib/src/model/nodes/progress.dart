/// Progress nodes: the bar and the ring.
part of '../node.dart';

final class ProgressBarNode extends ChildNode {
  const ProgressBarNode({
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
    required this.value,
    required this.max,
    required this.color,
    required this.labelFormat,
    this.thickness,
    this.trackColor,
    this.gradient,
    this.segments,
    this.currentColor,
    this.cap,
    this.animateChanges = false,
  });

  /// Round ends (9.21.0); `null` is the ends as before: the theme's `pill` radius.
  final ProgressCap? cap;

  /// The value leads to a new value from data instead of jumping (9.21.0); only the literal `true` is read.
  final bool animateChanges;

  final BindableNumber value;
  final BindableNumber max;

  /// The fill color is part of the widget (`props`), not the foreground.
  final FieldColor color;
  final ProgressLabelFormatToken labelFormat;

  /// Steps (9.11.0): an integer 2..12; `null` means there is no field or it is unreadable, and the bar is
  /// solid. The color of the current step; `null` means as an unfilled one.
  final int? segments;
  final ColorRef? currentColor;

  /// Track thickness, track color and fill gradient (9.7.0); see [CircularProgressNode.thickness].
  final ScaleRef? thickness;
  final ColorRef? trackColor;
  final GradientRef? gradient;
}

ProgressBarNode _parseProgressBar(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return ProgressBarNode(
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
    value: BindableNumber.parse(props['value']),
    max: BindableNumber.parse(props['max'], fallback: 100),
    color: FieldColor.parse(props['color'], fieldDefault: ColorToken.primary),
    labelFormat: ProgressLabelFormatToken.parse(props['labelFormat']),
    thickness: readProgressThickness(props['thickness']),
    trackColor: ColorRef.tryParse(props['trackColor']),
    gradient: GradientRef.tryParse(props['gradient']),
    segments: readSegments(props['segments']),
    currentColor: ColorRef.tryParse(props['currentColor']),
    cap: ProgressCap.parse(props['cap']),
    animateChanges: props['animateChanges'] == true,
  );
}

/// The progress ring (8.7.0): the same scale as the bar's, bent into an arc.
///
/// THE CENTER BELONGS TO THE DOCUMENT (a decision of 8.7.0 that still stands): a rank in a ring is a
/// `Text` in a `Stack`, and progress around a badge is the badge itself.
///
/// [labelFormat] appeared in 8.16.0 with the default [ProgressLabelFormatToken.none], i.e. the previous
/// behaviour. There is one reason to add it: a percentage is a DERIVED number, absent from the data, so a
/// stack over a ring could not express "75 %". There is also one reason to keep the default empty: the
/// label occupies the center, and the center has already been promised to the document, so a silent change
/// would take that place from every existing ring.
final class CircularProgressNode extends ChildNode {
  const CircularProgressNode({
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
    required this.value,
    required this.max,
    required this.color,
    required this.size,
    this.labelFormat = ProgressLabelFormatToken.none,
    this.thickness,
    this.trackColor,
    this.gradient,
    this.labelTypography,
    this.labelColor,
    this.cap,
    this.animateChanges = false,
  });

  /// Round ends of the arc (9.21.0); `null` is square ends, as before.
  final ProgressCap? cap;

  /// The value leads to a new value from data instead of jumping (9.21.0); only the literal `true` is read.
  final bool animateChanges;

  /// Own style of the label in the center (9.17.0): `null` means there is no field or it has the wrong
  /// shape, and `caption` / `onSurface` applies. A token the theme does not know gives the fallback style
  /// AS A WHOLE. The label inherits nothing and does not grow with the diameter.
  final TypographyRef? labelTypography;
  final ColorRef? labelColor;

  final BindableNumber value;
  final BindableNumber max;

  /// The fill color is part of the widget (`props`), not the foreground.
  final FieldColor color;

  /// The diameter. Three values rather than a number: the ring size is a design decision, and arbitrary
  /// pixels in the document would take it out of the design system the way a raw hex takes a color out.
  final CircularSizeToken size;

  /// The label in the CENTER of the ring (8.16.0). The default is "nothing".
  final ProgressLabelFormatToken labelFormat;

  /// Three look fields of the scale (9.7.0), the same as in [ProgressBarNode]. All are optional and
  /// WITHOUT a default in the schema: `null` means there is no field or it has the wrong shape, and the
  /// usual applies (`defaultThickness`, `defaultTrackColor`, a solid `color`). Each is read separately: one
  /// broken field does not cancel the rest.
  final ScaleRef? thickness;
  final ColorRef? trackColor;
  final GradientRef? gradient;
}

CircularProgressNode _parseCircularProgress(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return CircularProgressNode(
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
    value: BindableNumber.parse(props['value']),
    max: BindableNumber.parse(props['max'], fallback: 100),
    color: FieldColor.parse(props['color'], fieldDefault: ColorToken.primary),
    size: CircularSizeToken.parse(props['size']),
    // The RING's default is "nothing", unlike the bar, where it is `valueOfMax`. So `fallback` is named
    // explicitly: the parser's usual one is different, and silent inheritance would take the center from
    // every existing ring.
    labelFormat: ProgressLabelFormatToken.parse(
      props['labelFormat'],
      fallback: ProgressLabelFormatToken.none,
    ),
    thickness: readProgressThickness(props['thickness']),
    trackColor: ColorRef.tryParse(props['trackColor']),
    gradient: GradientRef.tryParse(props['gradient']),
    // 9.17.0: own label style; a wrong shape means no field, and the fallback applies.
    labelTypography: TypographyRef.tryParse(props['labelTypography']),
    labelColor: ColorRef.tryParse(props['labelColor']),
    cap: ProgressCap.parse(props['cap']),
    animateChanges: props['animateChanges'] == true,
  );
}
