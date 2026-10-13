/// Text: plain, composed of styled parts, and as a list item with a marker.
library;

import 'package:flutter/material.dart';

import '../../model/bindable.dart';
import '../../model/binding_format.dart' show AmountPart;
import '../../model/list_marker.dart';
import '../../model/node.dart';
import '../../model/shown_text.dart';
import '../../model/text_emphasis.dart';
import '../../model/text_spans.dart';
import '../layout/marker_column_end.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import 'render_tokens.dart';

extension TextWidgets on NodeRenderer {
  /// Text.
  ///
  /// **`overflow` applies only together with `maxLines`; this is not a simplification but a
  /// fix for a platform divergence.** In Flutter `TextOverflow.ellipsis` without `maxLines`
  /// collapses the paragraph into ONE line with an ellipsis: that is how `ellipsis` in
  /// `ParagraphStyle` works without a line limit. On the web the same combination does nothing:
  /// `text-overflow: ellipsis` without `white-space: nowrap` has no effect and the text simply
  /// wraps. The same document would give three lines in one reader and one clipped line in
  /// another.
  ///
  /// The contract describes these props as independent: `maxLines` says how many lines,
  /// `overflow` says what to do with the excess. So when lines are not limited, there is no
  /// excess and `overflow` is irrelevant. This follows the contract's semantics, not an engine
  /// quirk.
  ///
  /// COLOR AND FONT ARE INHERITED (schema 9.0.0). Text has no fields of its own for them: it is
  /// drawn with what the nearest ancestor named (or what it names itself in its `style`), and at
  /// the root with `onSurface` and `bodyM`.
  Widget buildText(TextNode node) {
    final foreground = currentForeground;
    // `textAlign` works within the widget's width. In a column text is always stretched (it is
    // not in `naturalWidth`), so there is no stretching of its own here: the parent gives the
    // width (`columnChildWidth`).
    final base = foreground.style.copyWith(color: foreground.color);
    final overflow = node.maxLines == null ? TextOverflow.clip : textOverflowOf(node.overflow);

    // COMPOSED TEXT (schema 9.6.0): only the styles of places that `content` declares apply. With
    // no effective styles this is the same `Text` as before 9.6.0.
    final content = node.content;
    final active = activeTextSpans(content, node.spans);
    final Widget body;
    if (active.isEmpty || content is! TemplateString) {
      // Text without parts is one run with the node's emphasis (schema 9.17.0). The line sits on
      // the run itself: here the paragraph is the run.
      body = Text(
        text(content),
        textAlign: textAlignOf(node.align),
        maxLines: node.maxLines,
        overflow: overflow,
        style: _withEmphasis(base, foreground.emphasis),
      );
    } else {
      body = _richText(
        content,
        active,
        base: base,
        emphasis: foreground.emphasis,
        textAlign: textAlignOf(node.align),
        maxLines: node.maxLines,
        overflow: overflow,
      );
    }
    final marker = drawnMarkerOf(node.marker);
    return marker == null ? body : _listItem(node, marker, body, base);
  }

  /// The style of a run with emphasis (schema 9.17.0). Slant is `FontStyle`, the line is
  /// `decoration` on the run itself, in the TEXT color of that run (`decorationColor` is not set:
  /// by default it is the text color). `normal` and `none` add nothing: there is no slant or line
  /// above the run (the paragraph does not carry them).
  TextStyle _withEmphasis(TextStyle style, TextEmphasis emphasis) => emphasis.isRoot
      ? style
      : style.copyWith(
          fontStyle: emphasis.fontStyle == EmphasisFontStyle.italic ? FontStyle.italic : null,
          decoration: _decorationOf(emphasis.textDecoration),
        );

  static TextDecoration? _decorationOf(EmphasisDecoration decoration) => switch (decoration) {
    EmphasisDecoration.none => null,
    EmphasisDecoration.underline => TextDecoration.underline,
    EmphasisDecoration.lineThrough => TextDecoration.lineThrough,
  };

  /// A LIST ITEM (schema 9.17.0): a BASELINE-aligned row with the marker column at the logical
  /// start, a gap, and the text taking the rest of the width. The text is its own column, so the
  /// second and later lines start under the first line of the TEXT (a hanging indent). A
  /// `WidgetSpan` at the start of the paragraph would not do here.
  ///
  /// The column and the gap are FRACTIONS OF THE FONT SIZE of the node's base text style, together
  /// with the system font scale ([listMarkerGeometry]), not a measured glyph width. The mark, a
  /// bullet or a number, uses the TEXT's font (family, size, weight, color), without italics or a
  /// line, pushed against the END of the column; if wider than the column it extends toward the
  /// start and is not clipped. It sits on the first baseline and adds no height. `maxLines` and
  /// `overflow` clip only the text; `align` applies within the text column.
  ///
  /// Screen reader: a bullet is not announced (decoration), a number is announced BEFORE the text
  /// as a single node.
  Widget _listItem(TextNode node, DrawnTextMarker marker, Widget body, TextStyle base) {
    final instance = listInstance;
    final numbered = instance != null && identical(instance.template, node)
        ? (number: instance.number, groupSize: instance.groupSize)
        : (siblingNumbers[node] ?? (number: 1, groupSize: 1));
    final label = listMarkerText(marker, numbered.number, locale);
    final spoken = marker == DrawnTextMarker.number ? '$label ${text(node.content)}' : null;
    final item = LayoutBuilder(
      builder: (context, constraints) {
        final scaled = MediaQuery.textScalerOf(context).scale(base.fontSize ?? 14);
        final geometry = listMarkerGeometry(marker, scaled, groupSize: numbered.groupSize);
        // If the width is tight, the text takes the rest; otherwise (a natural-width row) the node
        // is as wide as the column, the gap and the text's natural width.
        final textColumn = constraints.hasTightWidth ? Expanded(child: body) : Flexible(child: body);
        return Row(
          mainAxisSize: constraints.hasTightWidth ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: geometry.column,
              child: MarkerColumnEnd(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: base,
                  ),
                ),
              ),
            ),
            SizedBox(width: geometry.gap),
            textColumn,
          ],
        );
      },
    );
    return spoken == null ? item : Semantics(label: spoken, excludeSemantics: true, child: item);
  }

  static FontWeight _weightOf(int number) => switch (number) {
    400 => FontWeight.w400,
    500 => FontWeight.w500,
    600 => FontWeight.w600,
    _ => FontWeight.w700,
  };

  /// A paragraph with parts in their own styles: ONE `Text.rich`, giving one semantics node with
  /// the whole string (`richTextSemantics`), word wrapping across parts (`wrap: paragraph`), a
  /// shared baseline (`TextSpan`s within one paragraph; `WidgetSpan` and `Row` are not used) and
  /// bidi ordering over the whole string, without isolating the parts (`bidi: no-isolation`).
  ///
  /// THE LINE PITCH is a strut ([richTextStrut]) with `forceStrutHeight`: without it a line with a
  /// large run would be taller and a line without it shorter, and the paragraph height would
  /// depend on which line the large word wrapped onto.
  Widget _richText(
    TemplateString content,
    Map<String, TextSpanStyle> active, {
    required TextStyle base,
    required TextEmphasis emphasis,
    required TextAlign textAlign,
    required int? maxLines,
    required TextOverflow overflow,
  }) {
    // The style of each effective part: layered over the text's style by the inheritance rule. A
    // color the theme does not know and a font it does not know leave the base unchanged
    // (`unknownInheritedToken`).
    // The places AND their declared parts (9.19.0): `place` and `place.part`, each part laid over its place.
    final all = spanStylesWithParts(active);
    final styles = <String, TextStyle>{};
    for (final entry in all.entries) {
      final color = entry.value.color == null ? null : theme.resolveColor(entry.value.color!);
      final font = entry.value.typography == null ? null : theme.resolveTypography(entry.value.typography!);
      // A part's font style replaces the base WHOLE: a field the token lacks (tracking) is not
      // inherited from the text but reset.
      final whole = font == null ? base : font.copyWith(color: base.color, letterSpacing: font.letterSpacing ?? 0);
      styles[entry.key] = whole.copyWith(color: color ?? base.color);
    }

    // The strut: the line of every EFFECTIVE style, whether or not this locale's string mentions
    // it (`unusedSpan`: not drawn, but counted in the height).
    LineMetric metricOf(TextStyle style) =>
        (fontSize: style.fontSize ?? 14, lineHeight: style.height ?? 1);
    final strut = richTextStrut(metricOf(base), {
      for (final entry in styles.entries) entry.key: metricOf(entry.value),
    });
    final strutStyle = strut.span == null ? base : styles[strut.span]!;

    // THE EMPHASIS OF A RUN (schema 9.17.0): the text supplies slant and line, a part replaces
    // EACH of its own fields separately, and only a part names a weight, which beats the weight
    // of the font style (`copyWith` AFTER resolving `typography`). Each run carries the line
    // itself: the paragraph has none, so a part's `none` really cancels it inside underlined text.
    // The strut stays derived from `styles`: neither slant, weight nor line changes it.
    TextStyle? runStyle(String? place, AmountPart? amountPart) {
      final name = place == null ? null : (amountPart == null ? place : '$place.${amountPart.wire}');
      final part = name == null ? null : all[name];
      final run = runEmphasisOf(emphasis, part);
      var style = name == null ? null : styles[name];
      final weight = run.weight;
      if (weight != null) style = (style ?? const TextStyle()).copyWith(fontWeight: _weightOf(weight));
      final folded = TextEmphasis(fontStyle: run.fontStyle, textDecoration: run.textDecoration);
      if (folded.isRoot) return style;
      return _withEmphasis(style ?? const TextStyle(), folded);
    }

    final runs = collapseShownRuns<TextPartRun>(
      spanPartRuns(content.partedRuns(data, strings, locale, now), active),
      (run) => run.text,
      (run, text) => (text: text, span: run.span, part: run.part),
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final run in runs) TextSpan(text: run.text, style: runStyle(run.span, run.part)),
        ],
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: base,
      strutStyle: StrutStyle(
        fontFamily: strutStyle.fontFamily,
        fontFamilyFallback: strutStyle.fontFamilyFallback,
        fontSize: strutStyle.fontSize,
        fontWeight: strutStyle.fontWeight,
        height: strutStyle.height,
        forceStrutHeight: true,
      ),
    );
  }
}
