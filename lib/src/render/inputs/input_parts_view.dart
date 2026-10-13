/// The marks and the counter of a text field (schema 9.19.0, `x-style.layout.inputParts`).
library;

import 'package:flutter/material.dart';

import '../../model/input_parts.dart';
import '../../model/tokens.dart';
import '../icon_box.dart';

/// A mark as it is drawn: the shown text (already cut to its limit, never empty) or an icon.
sealed class ShownAffix {
  const ShownAffix();
}

final class ShownAffixText extends ShownAffix {
  const ShownAffixText(this.text);

  final String text;
}

final class ShownAffixIcon extends ShownAffix {
  const ShownAffixIcon(this.icon);

  final IconToken icon;
}

/// The shown mark for [affix]: [shownText] is the text of a text mark after the translation and the data. A text
/// mark whose shown text is empty is no mark at all, gap included.
ShownAffix? shownAffixOf(FieldAffix? affix, String Function(AffixText mark) shownText) => switch (affix) {
  null => null,
  AffixIcon(:final icon) => ShownAffixIcon(icon),
  final AffixText mark => () {
    final text = affixTextShown(shownText(mark));
    return text.isEmpty ? null : ShownAffixText(text);
  }(),
};

/// The text a screen reader reads for a mark: the text, never the icon.
String? heardAffixText(ShownAffix? affix) => affix is ShownAffixText ? affix.text : null;

/// One mark inside the box: the text in the font of the field and `muted`, one line that never shrinks; or an icon in
/// the box of one line of the field's font. A press focuses the field and is never an action.
class FieldMark extends StatelessWidget {
  const FieldMark({
    required this.affix,
    required this.style,
    required this.strut,
    required this.color,
    required this.onPress,
    super.key,
  });

  final ShownAffix affix;
  final TextStyle style;
  final StrutStyle strut;
  final Color color;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final glyph = style.fontSize ?? 0;
    final content = switch (affix) {
      ShownAffixText(:final text) => Text(
        text,
        style: style.copyWith(color: color),
        strutStyle: strut,
        maxLines: 1,
        softWrap: false,
      ),
      ShownAffixIcon(:final icon) => IconBox(box: Size(glyph, glyph * (style.height ?? 1)), icon: icon, color: color),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPress,
      child: ExcludeSemantics(child: content),
    );
  }
}

/// The row inside the box: the mark at the logical start, the field, the mark at the logical end, by the direction of
/// the SCREEN. A mark never shrinks; the field takes the rest. A mark stands in the centre of a one-line field and on
/// the first line of a field of several.
Widget fieldRowWithMarks({
  required Widget field,
  required Widget? prefix,
  required Widget? suffix,
  required double gap,
  required bool multiline,
}) {
  if (prefix == null && suffix == null) return field;
  return Row(
    crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
    children: [
      ?prefix,
      if (prefix != null) SizedBox(width: gap),
      Expanded(child: field),
      if (suffix != null) SizedBox(width: gap),
      ?suffix,
    ],
  );
}

/// The row under the box: the note from the logical start takes the rest, the counter stands at the logical end as
/// one line that never shrinks; without a note the counter holds the row alone.
Widget noteRowWithCounter({required Widget? note, required Widget counter, required double gap}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (note == null) const Spacer() else Expanded(child: note),
    SizedBox(width: gap),
    counter,
  ],
);
