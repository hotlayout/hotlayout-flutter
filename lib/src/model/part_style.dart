import 'package:flutter/foundation.dart';

import 'style_values.dart';
import 'visibility.dart';

/// THE STYLE OF ONE PART of a composite widget (schema 9.19.0, `x-style.layout.partStyle`): a colour and a font,
/// named apart from the node, each a token or an own value like a field of `style`.
///
/// A field that is not named is not applied: the part keeps what it had (the named colour of the node, or the
/// built-in one). The style goes nowhere down the tree.
@immutable
final class PartStyle {
  const PartStyle({this.color, this.typography});

  final ColorRef? color;
  final TypographyRef? typography;

  bool get isEmpty => color == null && typography == null;

  /// This style with [over] laid on top, per field.
  PartStyle over(PartStyle? base) => PartStyle(color: color ?? base?.color, typography: typography ?? base?.typography);
}

/// The part style of a raw value, or `null` when nothing in it can be read. Each field is read on its own: a
/// colour of the wrong form does not cancel a good font.
PartStyle? readPartStyle(Object? raw) {
  if (raw is! Map) return null;
  final style = PartStyle(color: ColorRef.tryParse(raw['color']), typography: TypographyRef.tryParse(raw['typography']));
  return style.isEmpty ? null : style;
}

/// One state of a part: the condition (the same as `visibleIf`) and the style laid over the base style while it
/// holds.
@immutable
final class PartStyleCase {
  const PartStyleCase({required this.when, required this.style});

  final VisibilityCondition when;
  final PartStyle style;
}

/// The readable states of a part, in document order. An entry that cannot be read is skipped and the next one
/// counts.
List<PartStyleCase> readPartStyleCases(Object? raw) {
  if (raw is! List) return const [];
  final cases = <PartStyleCase>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final when = VisibilityCondition.parse(entry['when']);
    final style = readPartStyle(entry['style']);
    if (when == null || style == null) continue;
    cases.add(PartStyleCase(when: when, style: style));
  }
  return List.unmodifiable(cases);
}

/// THE STYLE OF A PART NOW (`resolvePartStyle`): the base style, with the first state whose condition holds laid
/// over it per field. No state holds: the base style. [isMet] answers a condition in the data scope of the node.
///
/// [applicable] drops from a style the fields the theme will not apply (a token it does not know), BEFORE the
/// state is laid over the base: the base field then stays (`x-style.layout.partStyle.unknownToken`).
PartStyle? resolvePartStyle(
  PartStyle? base,
  List<PartStyleCase> cases,
  bool Function(VisibilityCondition when) isMet, {
  PartStyle? Function(PartStyle style)? applicable,
}) {
  final own = base == null || applicable == null ? base : applicable(base);
  for (final entry in cases) {
    if (!isMet(entry.when)) continue;
    final state = applicable == null ? entry.style : applicable(entry.style);
    return state?.over(own) ?? own;
  }
  return own;
}
