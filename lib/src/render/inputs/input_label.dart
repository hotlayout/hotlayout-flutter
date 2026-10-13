/// The label of an input and the mark of a required field.
library;

import 'package:flutter/material.dart';

import '../../model/form_rules.dart';

/// The required-field mark (schema 9.14.0, `form.required.mark`): a `*` right after the label
/// text, on the same line, separated by [gap] (`xs`), drawn in [color] (`danger`) and in the
/// label's font.
class RequiredMark {
  const RequiredMark({required this.color, required this.gap});

  final Color color;
  final double gap;
}

/// A label with an optional asterisk: ONE text that wraps as a whole, not two widgets side by
/// side. The asterisk is part of the line, so in RTL it ends up on the left of the label by
/// itself. It does not change the accessible name: the input widget sets the name
/// (`Semantics.label`), and this label is hidden from screen readers.
Widget requiredLabel(String label, {required TextStyle style, required StrutStyle strut, RequiredMark? mark}) {
  if (mark == null) return Text(label, style: style, strutStyle: strut);
  return Text.rich(
    TextSpan(
      text: label,
      children: [
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox(width: mark.gap)),
        TextSpan(text: kRequiredMarkText, style: TextStyle(color: mark.color)),
      ],
    ),
    style: style,
    strutStyle: strut,
  );
}
