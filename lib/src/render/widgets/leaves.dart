/// Spacer, divider and the placeholder of an unknown node.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../model/compatibility.dart';
import '../../model/node.dart';
import '../../model/tokens.dart';
import '../layout/quiet_flex.dart';
import '../node_renderer.dart';
import 'column.dart';

extension LeafWidgets on NodeRenderer {
  /// The axis comes from the document, not from where the node is placed: a horizontal spacer
  /// is a strip `size` high, a vertical one is `size` wide.
  Widget buildSpacer(SpacerNode node) {
    final size = theme.fieldSpacing(node.size);
    return switch (node.orientation) {
      OrientationToken.horizontal => SizedBox(height: size),
      OrientationToken.vertical => SizedBox(width: size),
    };
  }

  /// The divider is drawn in EXACTLY the color the document names.
  ///
  /// The color is never dimmed by the reader: an alpha applied here would paint a color the
  /// theme never declared (a theme is values, not names), and other readers would show the same
  /// document differently. A document that asks for `muted` gets a dark line, which is what it
  /// asked for; the light hairline color is the `border` token.
  Widget buildDivider(DividerNode node) {
    // Both fields are `props` with a default: an unknown token yields the FIELD's default.
    // Since schema 9.0.0 a state (`styleWhen`) does not recolor the line: a widget part's color
    // lives in `props`, and states change only `style`.
    final gap = theme.fieldSpacing(node.spacing);
    final color = theme.fieldColor(node.color);
    return switch (node.orientation) {
      OrientationToken.horizontal => Padding(
        padding: EdgeInsets.symmetric(vertical: gap),
        child: SizedBox(
          height: 1,
          width: double.infinity,
          child: ColoredBox(color: color),
        ),
      ),
      OrientationToken.vertical => Padding(
        padding: EdgeInsets.symmetric(horizontal: gap),
        // The contract gives a vertical line no length and its neighbors do not set one, so
        // take a text line's height: the minimum that looks sensible.
        child: SizedBox(width: 1, height: 20, child: ColoredBox(color: color)),
      ),
    };
  }

  /// The strategy for a node type the app does not know.
  ///
  /// With server-driven UI the backend is updated before the mobile app rolls out, so an unknown
  /// node is a normal event, not a failure. Therefore:
  ///  * the rest of the screen is drawn as usual: one foreign node breaks nothing;
  ///  * the children of an unknown node are still rendered: if it is a new container, its
  ///    content usually consists of old, known widgets, and losing real content because of an
  ///    unfamiliar wrapper is worse than showing it in a plain stack;
  ///  * in debug a visible banner with the type name is added, so the document author sees the
  ///    problem at once; in release there is no banner, since "Unknown widget: Chart" means
  ///    nothing to an end user.
  Widget buildUnknown(UnknownNode node) {
    final body = node.children.isEmpty
        ? null
        : buildChildColumn(node.children, gap: theme.space(SpacingToken.sm), align: AlignToken.start);

    if (!kDebugMode) return body ?? const SizedBox.shrink();

    return Container(
      key: ValueKey('sdui-unknown-${node.id}'),
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: theme.space(SpacingToken.xs)),
      padding: theme.padding(SpacingToken.sm),
      decoration: BoxDecoration(
        color: theme.color(ColorToken.warning).withValues(alpha: 0.12),
        borderRadius: theme.borderRadius(RadiusToken.sm),
        border: Border.all(color: theme.color(ColorToken.warning)),
      ),
      child: QuietColumn(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            describeWidgetOrigin(node.type, widgetOriginOf(node.type)),
            style: theme
                .text(TypographyToken.caption)
                .copyWith(color: theme.color(ColorToken.onSurface)),
          ),
          if (body != null) ...[SizedBox(height: theme.space(SpacingToken.xs)), body],
        ],
      ),
    );
  }
}
