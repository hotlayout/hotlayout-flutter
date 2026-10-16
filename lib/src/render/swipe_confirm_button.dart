/// The track of a "swipe to confirm" button (schema 9.22.0, `Button.confirm: 'swipe'`).
///
/// The button is a TRACK with a circular thumb at the inline start. A finger or a mouse drags the thumb along the
/// line; released at or past the threshold it runs the action (once, `track` first, as an ordinary press does), earlier
/// it returns and nothing happens. A press without a drag does nothing. For the keyboard and assistive technology it is
/// an ordinary button named by its label: Enter and Space (not their auto-repeat) and the "activate" semantics action
/// run it at once. A disabled button does not move. The numbers are `model/swipe_confirm.dart`.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/swipe_confirm.dart';
import '../model/tokens.dart';
import 'icon_glyph.dart';
import 'motion.dart';
import 'screen_form.dart';

class SwipeConfirmTrack extends StatefulWidget {
  const SwipeConfirmTrack({
    super.key,
    required this.decorate,
    required this.label,
    required this.typography,
    required this.labelColor,
    required this.verticalPadding,
    required this.border,
    required this.inset,
    required this.thumbColor,
    required this.glyphColor,
    required this.glyph,
    required this.disabled,
    required this.onActivate,
    required this.focusColor,
    this.radius,
  });

  /// Draws the surface of the track (role, own style) around the content; the content is laid out in the full box.
  final Widget Function(Widget content) decorate;

  final String label;
  final TextStyle typography;
  final Color labelColor;

  /// The vertical padding of the size (both sides together); the inline padding is not read.
  final double verticalPadding;

  /// The border on one side, zero without one.
  final double border;

  /// The room between the border and the thumb (the `xs` step).
  final double inset;

  final Color thumbColor;
  final Color glyphColor;
  final IconToken glyph;
  final bool disabled;
  final VoidCallback onActivate;
  final Color focusColor;
  final BorderRadiusGeometry? radius;

  @override
  State<SwipeConfirmTrack> createState() => _SwipeConfirmTrackState();
}

class _SwipeConfirmTrackState extends State<SwipeConfirmTrack> {
  double _dx = 0;
  double _progress = 0;
  bool _dragging = false;
  bool _focused = false;

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  SwipeTrack _track(double width, double height) =>
      (height: height, width: width, border: widget.border, inset: widget.inset);

  double _height(BuildContext context) {
    final fontSize = widget.typography.fontSize ?? 14;
    final line = MediaQuery.textScalerOf(context).scale(fontSize) * (widget.typography.height ?? 1);
    return widget.verticalPadding + 2 * widget.border + line;
  }

  void _activate() {
    if (widget.disabled) return;
    widget.onActivate();
  }

  void _start(DragStartDetails details) {
    if (widget.disabled) return;
    setState(() {
      _dx = 0;
      _dragging = true;
    });
  }

  void _update(DragUpdateDetails details) {
    if (widget.disabled || !_dragging) return;
    final box = context.findRenderObject()! as RenderBox;
    final travel = swipeGeometryOf(_track(box.size.width, box.size.height)).travel;
    _dx += details.delta.dx;
    setState(() => _progress = swipeProgressOf(_dx, travel, rtl: _rtl));
  }

  void _end(DragEndDetails details) {
    final release = swipeReleaseOf(_progress, disabled: widget.disabled);
    setState(() {
      _dragging = false;
      _progress = 0;
    });
    if (release == SwipeRelease.act) widget.onActivate();
  }

  void _cancel() => setState(() {
    _dragging = false;
    _progress = 0;
  });

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final activation =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select;
    if (!activation) return KeyEventResult.ignored;
    // A held key is not a series of presses.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyDownEvent) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final height = _height(context);
    final room = swipeGeometryOf(_track(0, height)).thumbRoom;
    final fontSize = widget.typography.fontSize ?? 14;

    // The label is centred in the strip between the two places of the thumb, so the circle never covers it; the
    // padding of the strip is also what gives the track its natural width (label plus the room on both sides).
    final label = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(room, widget.verticalPadding / 2 + widget.border, room, widget.verticalPadding / 2 + widget.border),
      child: Center(
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          strutStyle: StrutStyle(
            fontFamily: widget.typography.fontFamily,
            fontSize: widget.typography.fontSize,
            height: widget.typography.height,
            forceStrutHeight: true,
          ),
          style: widget.typography.copyWith(color: widget.labelColor),
        ),
      ),
    );

    final duration = _dragging ? Duration.zero : motionOf(context, Motion.quick);
    final thumb = Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final track = _track(box.maxWidth, box.maxHeight);
          final geometry = swipeGeometryOf(track);
          return Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: duration,
                curve: Motion.enter,
                start: swipeThumbStartOf(track, _progress),
                top: widget.border + widget.inset,
                width: geometry.diameter,
                height: geometry.diameter,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: widget.thumbColor, shape: BoxShape.circle),
                    child: Center(child: IconGlyph(widget.glyph, size: fontSize, color: widget.glyphColor)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    Widget track = widget.decorate(Stack(children: [label, thumb]));
    if (_focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      track = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: widget.focusColor, width: 2),
          borderRadius: widget.radius,
        ),
        child: track,
      );
    }

    final gesture = widget.disabled
        ? DisabledPress(child: track)
        : GestureDetector(
            // The drag counts from the moment the finger came down, not from where the recognizer won.
            dragStartBehavior: DragStartBehavior.down,
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onHorizontalDragStart: _start,
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: _end,
            onHorizontalDragCancel: _cancel,
            child: track,
          );

    return Semantics(
      container: true,
      button: true,
      enabled: !widget.disabled,
      label: widget.label.isEmpty ? null : widget.label,
      onTap: widget.disabled ? null : _activate,
      excludeSemantics: true,
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: IntrinsicWidth(child: gesture),
      ),
    );
  }
}
