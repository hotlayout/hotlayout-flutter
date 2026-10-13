// The selection of a choice group: the scope rows read, the widget that holds it
// and the mark of an option.
library;

import 'package:flutter/material.dart';

/// The choice owned by a group, as seen by a row inside it.
@immutable
final class ChoiceScope {
  const ChoiceScope({required this.selected, required this.select});

  /// Name of the selected option, or `null` for "nothing selected". `null` is a legal state,
  /// not an error: the group may have opened with an empty `value` or with a name that none of
  /// its rows has.
  final String? selected;
  final ValueChanged<String> select;
}

/// The mark of a choice option.
///
/// A separate widget rather than a bare [Icon] on purpose: "selected" is a contract concept,
/// and tests, semantics and the host should ask about it through this widget, not through
/// whichever icon the renderer currently draws it with.
class ChoiceOptionMark extends StatelessWidget {
  const ChoiceOptionMark({
    required this.optionValue,
    required this.selected,
    required this.enabled,
    required this.size,
    required this.selectedColor,
    required this.mutedColor,
    super.key,
  });

  /// The option name from the document (`ListTile.trailing.optionValue`).
  final String optionValue;
  final bool selected;

  /// Whether anyone owns this choice: `false` means the row is outside a `ChoiceGroup`.
  final bool enabled;
  final double size;
  final Color selectedColor;
  final Color mutedColor;

  /// The mark is painted with our own brush (circle and dot), not the `Icons.radio_button_*`
  /// glyph: the glyph lives in the Material font, and a host without `uses-material-design: true`
  /// would show a square in its place. Proportions match the Material glyph (24: ring of radius
  /// 10 and width 2, dot of radius 5).
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RadioMarkPainter(selected: selected, color: selected ? selectedColor : mutedColor),
    ),
  );
}

class _RadioMarkPainter extends CustomPainter {
  const _RadioMarkPainter({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      9 * unit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * unit
        ..isAntiAlias = true
        ..color = color,
    );
    if (selected) {
      canvas.drawCircle(center, 5 * unit, Paint()..color = color..isAntiAlias = true);
    }
  }

  @override
  bool shouldRepaint(_RadioMarkPainter old) => old.selected != selected || old.color != color;
}

/// Selection state of one choice group.
///
/// It lives exactly as long as the group's node on screen. A group with a BOUND `value` also
/// has [onWrite]: a tap puts the chosen name into the same data path the group reads it from,
/// so leaving the screen and coming back shows the user's choice rather than the document's
/// initial value, because the DATA changed and the group reads it again. Local state remains:
/// a group with a literal `value` has nowhere to write, and for it nothing changed.
class ChoiceGroupScope extends StatefulWidget {
  const ChoiceGroupScope({
    required this.documentValue,
    required this.builder,
    this.onWrite,
    super.key,
  });

  /// `ChoiceGroup.value`, already resolved against the data.
  final String documentValue;

  /// Where to put the chosen name, or `null` for "no binding, nowhere to write".
  final ValueChanged<String>? onWrite;

  final Widget Function(String? selected, ValueChanged<String> select) builder;

  @override
  State<ChoiceGroupScope> createState() => _ChoiceGroupScopeState();
}

class _ChoiceGroupScopeState extends State<ChoiceGroupScope> {
  late String? _selected = _fromDocument;

  /// An empty string means "nothing selected", not an option with an empty name: that is what
  /// a binding with nothing in the data looks like.
  String? get _fromDocument =>
      widget.documentValue.isEmpty ? null : widget.documentValue;

  @override
  void didUpdateWidget(covariant ChoiceGroupScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The document wins over the finger: if `value` became different (a new document or new data
    // under the binding), the earlier choice is no longer about it.
    if (oldWidget.documentValue != widget.documentValue) {
      _selected = _fromDocument;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(_selected, _select);

  void _select(String value) {
    final shown = _selected;
    setState(() => _selected = value);
    // The write goes AFTER the local state: it travels up and comes back with the same value
    // (`didUpdateWidget` sees equality and does nothing), and if the host does not accept the
    // write, the mark has moved anyway. An option that is already SHOWN as selected (including by
    // the binding's fallback text) is not written a second time (`form.choice.sameOption`).
    if (value != shown) widget.onWrite?.call(value);
  }
}
