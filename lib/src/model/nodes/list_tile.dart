/// The list row and its leading and trailing slots.
part of '../node.dart';

/// The leading slot of a row (6.0.0).
///
/// Before 6.0.0 this was a prop `icon: IconToken`, i.e. "there is always an icon", and a row without
/// decoration was expressed by an icon that the manager hoped nobody would notice. Now it is a union with
/// an explicit `none`, and "nothing" is a value like the others.
sealed class ListTileLeading {
  const ListTileLeading();

  /// A broken or missing shape gives [LeadingNone], NOT the schema default
  /// (`{kind: 'icon', icon: 'chevron'}`). The reason: the field is required, so its absence is not "the
  /// manager relied on the default" but a broken document, and drawing an icon in it would invent content.
  static ListTileLeading parse(Object? raw) {
    if (raw is Map) {
      final kind = raw['kind'];
      if (kind == 'none') return const LeadingNone();
      if (kind == 'icon') {
        // 9.19.0: the colour of the glyph and the tile under it. Each is read on its own; a colour of the wrong
        // form is no colour, a tile without a readable colour is no tile.
        return LeadingIcon(IconToken.parse(raw['icon']), color: ColorRef.tryParse(raw['color']), tile: leadingTileOf(raw));
      }
      if (kind == 'image') return LeadingImage(ImageSource.parse(raw['source']));
      if (kDebugMode) debugPrint('[hotlayout] unknown ListTile.leading.kind "$kind": drawn without it');
    }
    return const LeadingNone();
  }
}

final class LeadingNone extends ListTileLeading {
  const LeadingNone();
}

final class LeadingIcon extends ListTileLeading {
  const LeadingIcon(this.icon, {this.color, this.tile});

  final IconToken icon;

  /// The colour of the glyph (9.19.0, `leading.color`): stronger than the named colour of the node. `null`
  /// means there is no readable field.
  final ColorRef? color;

  /// The tinted square under the glyph (9.19.0, `leading.tile`); `null` means no tile.
  final LeadingTile? tile;
}

final class LeadingImage extends ListTileLeading {
  const LeadingImage(this.source);

  /// The same [ImageSource] as in `Image`: an asset or an https URL. The reuse matters more than it seems:
  /// a product photo from Firebase Storage works in a row precisely because this is not a new kind of
  /// source.
  final ImageSource source;
}

/// The trailing slot of a row (6.0.0): nothing, text, a chevron or a selection option.
///
/// Before 6.0.0 there were two independent props, `trailing: BindableString?` and `showChevron: bool`,
/// which could both legally be on. The union removed the possibility of such a document.
sealed class ListTileTrailing {
  const ListTileTrailing();

  static ListTileTrailing parse(Object? raw, {String? key, String? captionKey}) {
    if (raw is Map) {
      final kind = raw['kind'];
      if (kind == 'none') return const TrailingNone();
      if (kind == 'chevron') return const TrailingChevron();
      if (kind == 'text') {
        // An icon AFTER the text ("+100 ◆") is a field of the variant, not a variant of its own: in mockups
        // this is one trailing slot, and splitting it would allow an icon without text, which does not occur
        // there.
        //
        // A MISSING key means "no icon" (and no box). A key that IS there and is not readable (`null`, an object,
        // a number, an unknown name) is an icon the reader cannot draw: an empty box of the same size
        // (`unreadableIconValue`). Hence `containsKey`, not `== null`.
        //
        // 9.19.0: the style of the text and its states (`style`, `styleWhen`), the caption under it and the
        // style of the caption. The style of the caption is read only WITH a caption.
        final captionRaw = raw['caption'];
        final caption = captionRaw == null ? null : BindableString.parse(captionRaw, key: captionKey);
        return TrailingText(
          BindableString.parse(raw['text'], key: key),
          icon: raw.containsKey('icon') ? IconToken.parse(raw['icon']) : null,
          style: readPartStyle(raw['style']),
          styleWhen: readPartStyleCases(raw['styleWhen']),
          caption: caption,
          captionStyle: caption == null ? null : readPartStyle(raw['captionStyle']),
          captionStyleWhen: caption == null ? const [] : readPartStyleCases(raw['captionStyleWhen']),
        );
      }
      if (kind == 'radio') {
        final optionValue = raw['optionValue'];
        // An option without a name is not identified, so it cannot even theoretically be selected. A circle
        // without a name is not an option but decoration.
        if (optionValue is String && optionValue.isNotEmpty) {
          return TrailingRadio(optionValue);
        }
        if (kDebugMode) debugPrint('[hotlayout] ListTile.trailing.radio without optionValue: drawn without the slot');
        return const TrailingNone();
      }
      if (kDebugMode) debugPrint('[hotlayout] unknown ListTile.trailing.kind "$kind": drawn without it');
    }
    return const TrailingNone();
  }
}

final class TrailingNone extends ListTileTrailing {
  const TrailingNone();
}

final class TrailingText extends ListTileTrailing {
  const TrailingText(
    this.text, {
    this.icon,
    this.style,
    this.styleWhen = const [],
    this.caption,
    this.captionStyle,
    this.captionStyleWhen = const [],
  });

  final BindableString text;

  /// The style of the text and its states (9.19.0): stronger than the named colour of the node and its states.
  final PartStyle? style;
  final List<PartStyleCase> styleWhen;

  /// One line under the text (9.19.0), and its own style: the style of the text does not reach it.
  final BindableString? caption;
  final PartStyle? captionStyle;
  final List<PartStyleCase> captionStyleWhen;

  /// An optional icon to the right of the text (8.11.0). `null` means there is no icon;
  /// [IconToken.unknown] means there is an icon but nothing to draw it with.
  final IconToken? icon;
}

final class TrailingChevron extends ListTileTrailing {
  const TrailingChevron();
}

/// An option of a mutually exclusive choice.
///
/// The node names ITSELF (`optionValue`), not its state: whether it is selected is decided by the
/// ancestor's [ChoiceGroupNode.value]. That is why there is no `selected` field here: a document with two
/// selected rows cannot be expressed structurally.
final class TrailingRadio extends ListTileTrailing {
  const TrailingRadio(this.optionValue);

  final String optionValue;
}

final class ListTileNode extends ChildNode {
  const ListTileNode({
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
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.action,
    this.titleMaxLines,
    this.subtitleMaxLines,
  });

  /// The line limits of the title and the subtitle (9.19.0), as the document wrote them: [listTileLinesOf]
  /// decides whether a value is a limit.
  final Object? titleMaxLines;
  final Object? subtitleMaxLines;

  final ListTileLeading leading;
  final BindableString title;
  final BindableString? subtitle;
  final ListTileTrailing trailing;

  /// A row's action (6.1.0): the same structure as `Button.action`.
  ///
  /// `null` means the row cannot be pressed. The field was added as a minor precisely because it is
  /// optional: a 6.1.0 document is shown in full by a 6.0.0 reader, whose row simply stays neutral.
  final ButtonAction? action;

  /// Whether this row is an option of a mutually exclusive choice.
  ///
  /// The question is not about look but about who owns the touch: an option row belongs to the choice, and
  /// its [action] is not executed (see `render_document.dart`).
  bool get isOption => trailing is TrailingRadio;
}

ListTileNode _parseListTile(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  final hiddenByClass = node.hiddenByClass;
  final style = node.style;
  final styleWhen = node.styleWhen;
  return ListTileNode(
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
    leading: ListTileLeading.parse(props['leading']),
    title: BindableString.parse(props['title'], key: node.key('title')),
    subtitle: props['subtitle'] == null
        ? null
        : BindableString.parse(props['subtitle'], key: node.key('subtitle')),
    // `trailing.text` is precisely the case for which a key has a PATH and not just a field name: the text
    // lies inside the slot's union. Without it the value on the right of a row would stay in the source
    // language in another language's version, and there would be no error, just a mixture.
    trailing: ListTileTrailing.parse(props['trailing'], key: node.key('trailing.text'), captionKey: node.key('trailing.caption')),
    // 6.1.0. The field is OPTIONAL, and `null` here means exactly "no action", not `ButtonAction.none`: a
    // button's action is required, so "do nothing" had to be expressed by a value there; for a row it is
    // expressed by the field's absence. The difference is visible: a row without `action` is not a touch
    // target at all.
    action: props['action'] == null ? null : ButtonAction.parse(props['action']),
    titleMaxLines: props['titleMaxLines'],
    subtitleMaxLines: props['subtitleMaxLines'],
  );
}
