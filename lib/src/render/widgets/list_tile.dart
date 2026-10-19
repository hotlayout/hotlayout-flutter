/// The list row: leading slot, texts and trailing slot.
library;

import '../../report/report_hub.dart';
import 'package:flutter/material.dart';

import '../../model/layout_rules.dart' show isSilentAccessibleName;
import '../../model/list_tile_parts.dart';
import '../../model/node.dart';
import '../../model/tokens.dart';
import '../choice_scope.dart';
import '../icon_glyph.dart';
import '../layout/quiet_flex.dart';
import '../long_press_row.dart';
import '../node_renderer.dart';
import '../press_feedback.dart';
import '../../model/press_feedback.dart';
import '../tap_target.dart';
import 'image.dart';
import 'list_tile_parts.dart';
import 'write_control.dart';

extension ListTileWidgets on NodeRenderer {
  /// The list row. Both of its ends are a union, not a set of flags.
  ///
  /// The key point is that one trailing-slot variant (`radio`) makes the row INTERACTIVE, exactly
  /// when the row is inside a group. Outside a group the circle is drawn but not tappable: that
  /// is how a document the builder flags as `choice_option_outside_group` looks, and pretending
  /// to work where the choice has no owner is worse than an empty circle (the user taps, nothing
  /// happens, and they blame the app).
  ///
  /// `action` is a second claimant to the same tap. The rule is unambiguous: **an option row
  /// belongs to the choice, period.**
  ///
  ///  * there is one tap and it cannot have two meanings, and splitting them by gesture (tap
  ///    selects, long tap navigates) would invent a gesture the contract does not have;
  ///  * if the action won, it would usually lead to another screen, and the option could NEVER be
  ///    selected. The reverse loss is smaller: an action can always be moved to a button below
  ///    the list;
  ///  * outside a group an option is dead even with an action: otherwise the builder's own error
  ///    text ("the tap affects nothing") would become false, and the user would tap the circle
  ///    and navigate somewhere instead of selecting.
  ///
  /// So the ownership of the tap is decided by the SHAPE of the node (it declared itself an
  /// option), not by its surroundings.
  Widget buildListTile(ListTileNode node) {
    final subtitle = node.subtitle == null ? null : text(node.subtitle!);
    final leading = _tileLeading(node.leading);
    final trailing = node.trailing;
    final option = trailing is TrailingRadio ? trailing.optionValue : null;
    final scope = choice;
    final selectable = option != null && scope != null;
    final selected = selectable && scope.selected == option;

    if (option != null && node.action != null) {
      ReportHub.ignored('node "${node.id}"', 'a ListTile that is a choice option does not run its `action`: the tap belongs to the choice');
    }

    // There is no vertical padding around the row here: since schema 9.0.0 it is the registry's
    // `defaultStyle` (`padding: {top, bottom}`), which the builder WRITES into the document. A
    // node without `style` is a row without padding, and that is not an error.
    final row = QuietRow(
      children: [
        if (leading != null) ...[
          leading,
          // The row has ONE gap, `sm`, on both the leading and the trailing side.
          SizedBox(width: theme.space(SpacingToken.sm)),
        ],
        Expanded(
          child: QuietColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The line limits (9.19.0): the rest is cut with an ellipsis at the logical end of the last line; the
              // screen reader still hears the whole text.
              Text(
                text(node.title),
                maxLines: listTileLinesOf(node.titleMaxLines),
                overflow: listTileLinesOf(node.titleMaxLines) == null ? null : TextOverflow.ellipsis,
                style: theme
                    .text(TypographyToken.titleS)
                    .copyWith(color: partColor(ColorToken.onSurface)),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: listTileLinesOf(node.subtitleMaxLines),
                  overflow: listTileLinesOf(node.subtitleMaxLines) == null ? null : TextOverflow.ellipsis,
                  style: theme
                      .text(TypographyToken.bodyS)
                      .copyWith(color: partColor(ColorToken.muted, secondary: true)),
                ),
            ],
          ),
        ),
        ..._tileTrailing(trailing, selected: selected, selectable: selectable),
      ],
    );

    if (option != null) {
      return Semantics(
        container: true,
        inMutuallyExclusiveGroup: true,
        checked: selected,
        enabled: selectable,
        // `GestureDetector`, not `InkWell`: the reader has no right to require a `Material` above
        // it, since the document can be embedded anywhere.
        child: selectable
            ? PressFeedback(
                kind: pressFeedbackKindOf(node),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => scope.select(option),
                  child: row,
                ),
              )
            : row,
      );
    }

    // The row's action uses the same machinery as a button: the reader runs `navigate` itself
    // (see [ScreenFlow]) and hands the rest to the host as opaque. Nothing special for a row, which
    // is the point: a new entry point is not a new way of describing an action.
    final action = node.action;
    final longPress = node.longPress;
    if (action == null && longPress == null) return row;

    // A long press (9.26.0) makes the row a control even without an action: it takes the tap, and a tap does nothing.
    final longLabel = node.longPressLabel == null ? '' : text(node.longPressLabel!);
    final Widget tapped = longPress == null
        ? TapTarget(
            child: PressFeedback(
              kind: pressFeedbackKindOf(node),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => emit(action!, node.id),
                child: row,
              ),
            ),
          )
        : LongPressRow(
            feedback: pressFeedbackKindOf(node),
            longPressLabel: isSilentAccessibleName(longLabel) ? null : longLabel,
            onPress: action == null ? null : () => emit(action, node.id),
            onLongPress: () => emit(longPress, node.id),
            child: row,
          );
    if (action == null) return tapped;
    final control = controlOfAction(action);
    if (control == null) return Semantics(button: true, child: tapped);
    return withWriteControl(
      control: control,
      name: [text(node.title), ?subtitle].where((line) => line.isNotEmpty).join('\n'),
      disabled: false,
      onPress: () => emit(action, node.id),
      child: tapped,
    );
  }

  /// The leading slot. `null` means "nothing", gap included: otherwise a row with no decoration
  /// would be shifted by an empty space.
  Widget? _tileLeading(ListTileLeading leading) => switch (leading) {
    LeadingNone() => null,
    final LeadingIcon icon => leadingIconSlot(icon),
    LeadingImage(:final source) => ClipRRect(
      borderRadius: theme.borderRadius(RadiusToken.sm),
      child: SizedBox(
        // The thumbnail side is two `xl` units of the THEME, not a number from code, so it matches
        // the other readers' size; the contract itself names no size.
        width: _tileThumbnailScale * theme.space(SpacingToken.xl),
        height: _tileThumbnailScale * theme.space(SpacingToken.xl),
        child: imageContent(source, compact: true),
      ),
    ),
  };

  /// The trailing slot together with the gap before it.
  List<Widget> _tileTrailing(
    ListTileTrailing trailing, {
    required bool selected,
    required bool selectable,
  }) {
    final Widget? widget = switch (trailing) {
      TrailingNone() => null,
      /*
       * "+100 ◆" (schema 8.11.0): an icon AFTER the text, in the same slot. Color and size come
       * from the neighboring text, not from props of its own: the contract has none exactly
       * because the icon here is not independent but part of the caption.
       *
       * The trailing text and the icon beside it use the built-in `listTileTrailingColor`
       * (`onSurface`), not a muted color: "120 JOD" at the end of a row is a value, not a
       * secondary note. With a named color both parts are primary parts
       * (`colorParts.ListTile.trailingText` / `trailingIcon`). The gap, centering and order are
       * the shared rule [buildIconBesideText]; the position is fixed (after the text) and the
       * size is a step of the icon scale.
       */
      final TrailingText text => trailingTextSlot(text),
      // The picture is the contract icon set's `chevron`, not a Material glyph. The contract
      // names no box for the chevron, so it uses the plain `md` icon size.
      TrailingChevron() => IconGlyph(
        IconToken.chevron,
        size: theme.iconSize(IconSizeToken.md),
        color: partColor(ColorToken.muted, secondary: true),
      ),
      TrailingRadio(:final optionValue) => ChoiceOptionMark(
        optionValue: optionValue,
        selected: selected,
        enabled: selectable,
        size: theme.iconSize(IconSizeToken.md),
        // The contract does not describe how a SELECTED row looks: theme roles cover `Badge.tone`
        // and `Button.variant`, with no selection state among them. This is the reader's choice: a
        // filled circle in `primary`, the rest of the row unchanged.
        selectedColor: theme.color(ColorToken.primary),
        mutedColor: theme.color(ColorToken.muted),
      ),
    };
    if (widget == null) return const [];
    return [SizedBox(width: theme.space(SpacingToken.sm)), widget];
  }

  /// The thumbnail side in a row, in `xl` units of the theme. `ListTile.leading.image` has neither
  /// a size nor the `aspectRatio` that `Image` has, so this number is a reader convention shared
  /// with the other readers, not part of the contract.
  static const double _tileThumbnailScale = 2;
}
