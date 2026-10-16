/// Controls: button, icon button, text field, switch and checkbox.
part of '../node.dart';

final class ButtonNode extends ChildNode {
  const ButtonNode({
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
    required this.variant,
    required this.action,
    required this.fullWidth,
    this.icon,
    this.iconPath,
    this.iconPosition = kDefaultIconPosition,
    this.size = kDefaultButtonSize,
    this.requiresFilled = false,
    this.disabledIf,
    this.zone,
    this.confirmBySwipe = false,
  });

  /// "Swipe to confirm" (9.22.0, `confirm: 'swipe'`): the button is a track with a thumb; the action runs when the thumb
  /// is dragged past the threshold. Only the word `swipe` is read.
  final bool confirmBySwipe;

  /// App bar zone (9.16.0): `leading` means the node stands in the leading zone of the `AppBar`
  /// instead of the arrow. Read only on a direct child of the app bar.
  final BarZone? zone;

  /// Waits for its screen's form to be filled (9.14.0; only the literal `true`).
  final bool requiresFilled;

  /// Disable condition (9.14.0): the same shape and rules as `visibleIf`.
  final VisibilityCondition? disabledIf;

  final BindableString label;
  final ButtonVariantToken variant;
  final ButtonAction action;
  final bool fullWidth;

  /// An icon beside the label (9.5.0), or `null` when there is no field. If named but not from the set,
  /// [IconToken.unknown]: the empty box and the gap stay.
  final IconToken? icon;

  /// A data path that holds the name of the icon (9.19.0); read only when [icon] is there.
  final String? iconPath;

  /// Where the icon is relative to the label, in the writing direction. Means nothing without [icon].
  final IconPositionToken iconPosition;

  /// Size (9.5.0): the padding and label font from `x-style.layout.buttonSizes`.
  final ButtonSizeToken size;
}

ButtonNode _parseButton(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return ButtonNode(
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
    variant: ButtonVariantToken.parse(props['variant']),
    action: ButtonAction.parse(props['action']),
    // 9.5.0: three optional fields. The defaults come from `x-style.layout` and are not written into the
    // node: a missing field stays missing.
    icon: iconBesideTextOf(props['icon']),
    iconPath: iconPathOf(props['iconPath']),
    iconPosition: IconPositionToken.parse(props['iconPosition']),
    size: ButtonSizeToken.parse(props['size']),
    fullWidth: _bool(props['fullWidth'], true),
    // 9.14.0: a button that waits for a filled form, and the disable condition.
    requiresFilled: isRequiredProp(props['requiresFilled']),
    disabledIf: VisibilityCondition.parse(props['disabledIf']),
    zone: node.zone,
    confirmBySwipe: confirmsBySwipe(props['confirm']),
  );
}

/// The icon button (9.5.0): a circle with a glyph in the center and no visible text.
///
/// A widget with a theme ROLE: [variant] reads the same `buttonVariant` group as the button; the theme
/// has no new group. The size uses the same `buttonSizes` table, so the side equals the height of a
/// button of the same size.
final class IconButtonNode extends ChildNode {
  const IconButtonNode({
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
    required this.icon,
    required this.iconName,
    this.iconPath,
    required this.label,
    required this.variant,
    required this.size,
    required this.action,
    this.requiresFilled = false,
    this.disabledIf,
    this.zone,
    this.glyphSize,
  });

  /// App bar zone (9.16.0): `leading` means the icon button stands in the leading zone.
  final BarZone? zone;

  /// Own glyph size (9.16.0): an integer 8..128; `null` means there is no field or it is not readable,
  /// and the [size] word draws.
  final int? glyphSize;

  /// Waits for its screen's form to be filled (9.14.0; only the literal `true`).
  final bool requiresFilled;

  /// Disable condition (9.14.0).
  final VisibilityCondition? disabledIf;

  /// The glyph; [IconToken.unknown] is an empty box, and the button stays.
  final IconToken icon;

  /// A data path that holds the name of the icon (9.19.0). The accessible name stays the label.
  final String? iconPath;

  /// The icon name AS IN THE DOCUMENT (an unknown one too), or `null` if the value is not a string.
  /// Needed by one rule: a button without a label is named by the icon name in words
  /// (`iconButtonWithoutLabel`).
  final String? iconName;

  /// The accessible name: what a screen reader user hears.
  final BindableString label;
  final ButtonVariantToken variant;
  final ButtonSizeToken size;
  final ButtonAction action;
}

// 9.5.0: a round button without visible text. A leaf with a theme role.
IconButtonNode _parseIconButton(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return IconButtonNode(
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
    // A field that is not there at all gives the field default from the artifact (`info`), as in `Icon`.
    // A field that IS there and is not readable gives an empty box: the button stays.
    icon: props.containsKey('icon') ? IconToken.parse(props['icon']) : IconToken.parse('info'),
    iconName: props.containsKey('icon') ? (props['icon'] is String ? props['icon']! as String : null) : 'info',
    iconPath: iconPathOf(props['iconPath']),
    // The name for a screen reader; it is not drawn on screen.
    label: BindableString.parse(props['label'], key: node.key('label')),
    // The field default of the icon button is `secondary`, not the button's `primary`.
    variant: ButtonVariantToken.parse(props['variant'], fallback: ButtonVariantToken.secondary),
    size: ButtonSizeToken.parse(props['size']),
    action: ButtonAction.parse(props['action']),
    requiresFilled: isRequiredProp(props['requiresFilled']),
    disabledIf: VisibilityCondition.parse(props['disabledIf']),
    zone: node.zone,
    glyphSize: ownGlyphSizeOf(props['glyphSize']),
  );
}

/// The text field (9.13.0): a label above the field, a box, a line below it. A leaf.
///
/// The value is only a PATH ([valuePath]); `null` is a field without a path: it is drawn and works
/// locally, and writes nowhere (`inputWithoutValue`). The raw [keyboard], [maxLength] and [lines] are
/// kept as in the document: what to do with them is said by `inputKeyboardOf`, `clampInputText` and
/// `inputLinesOf` (rules, not shape).
final class TextFieldNode extends ChildNode {
  const TextFieldNode({
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
    required this.valuePath,
    this.placeholder,
    this.helper,
    this.error,
    this.keyboard,
    this.maxLength,
    this.lines,
    this.disabledIf,
    this.required = false,
    this.numeric = false,
    this.parts = FieldParts.none,
  });

  /// The look of the box, the marks and the counter (9.19.0); [FieldParts.none] for a field that names none.
  final FieldParts parts;

  /// Required (9.14.0): only the literal `true`.
  final bool required;

  /// A numeric field (9.14.0, `valueType: 'number'`); everything else is a string field.
  final bool numeric;

  /// The label: visible, and the field's accessible name.
  final BindableString label;
  final String? valuePath;
  final BindableString? placeholder;
  final BindableString? helper;

  /// Error text from the host's data; non-empty (something that can be heard) means the error state.
  final BindableString? error;
  final Object? keyboard;
  final Object? maxLength;
  final Object? lines;
  final VisibilityCondition? disabledIf;
}

// 9.13.0: input fields. Leaves; the value is only a path (`inputPathOf`), any other shape means "no
// path", and the field works locally. `disabledIf` has the same shape as `visibleIf`.
TextFieldNode _parseTextField(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return TextFieldNode(
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
    valuePath: inputPathOf(props['value']),
    placeholder: props['placeholder'] == null
        ? null
        : BindableString.parse(props['placeholder'], key: node.key('placeholder')),
    helper: props['helper'] == null ? null : BindableString.parse(props['helper'], key: node.key('helper')),
    error: props['error'] == null ? null : BindableString.parse(props['error'], key: node.key('error')),
    keyboard: props['keyboard'],
    maxLength: props['maxLength'],
    lines: props['lines'],
    disabledIf: VisibilityCondition.parse(props['disabledIf']),
    required: isRequiredProp(props['required']),
    numeric: isNumberValueType(props['valueType']),
    parts: readFieldParts(props, prefixKey: node.key('prefix.text'), suffixKey: node.key('suffix.text')),
  );
}

/// The switch (9.13.0): a label and a track at the end of the line. A leaf.
final class SwitchNode extends ChildNode {
  const SwitchNode({
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
    required this.valuePath,
    this.disabledIf,
  });

  final BindableString label;
  final String? valuePath;
  final VisibilityCondition? disabledIf;
}

SwitchNode _parseSwitch(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return SwitchNode(
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
    valuePath: inputPathOf(props['value']),
    disabledIf: VisibilityCondition.parse(props['disabledIf']),
  );
}

/// The checkbox (9.13.0): a square at the start of the line and a label. A leaf.
final class CheckboxNode extends ChildNode {
  const CheckboxNode({
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
    required this.valuePath,
    this.disabledIf,
    this.required = false,
  });

  final BindableString label;
  final String? valuePath;
  final VisibilityCondition? disabledIf;

  /// Required (9.14.0): this is a consent, so only an enabled box counts as filled.
  final bool required;
}

CheckboxNode _parseCheckbox(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return CheckboxNode(
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
    valuePath: inputPathOf(props['value']),
    disabledIf: VisibilityCondition.parse(props['disabledIf']),
    required: isRequiredProp(props['required']),
  );
}
