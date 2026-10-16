import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/screen_top_rules.dart';

/// SCREEN ZONES: the app bar stays, only the body scrolls (`x-style.layout.screen`).
///
/// From one child (the body) to four (app bar, body, pinned block, bottom). WHY A LAYOUT OF
/// ITS OWN rather than `Column[bar, Expanded(scroll)]`: a pulled first body child (`pull`,
/// schema 9.10.0) raises the body AREA by its overlap above the app bar's bottom edge, and only
/// the layout knows the app bar's height. A `Column` cannot express this (`Transform` neither
/// makes the area taller nor moves hits), and a `Stack` does not know the app bar's height
/// before layout.
///
///  * app bar: full width, own height (with its own top and side insets);
///  * body: from `app bar bottom edge - overlap` to the bottom, full width. The body is
///    painted OVER the app bar (`body.paintOrder`) and catches touches in the overlap strip;
///    whatever goes beyond the body's bounds is clipped by the scroll itself, and whatever goes
///    beyond the top of the screen is also clipped by this object;
///  * [overlap] is not clamped at the top of the screen: the body then starts above zero and
///    [paint] clips to the screen. The scroll already has a top inset of the same number, so
///    the first child stands where the flow puts it (`pullFlow`), and the area is "not above
///    the top of the screen" (the `zoneCases` row: overlap greater than the whole app bar);
///  * BOTTOM ZONE (schema 9.12.0, `x-style.layout.bottomZone`): the pinned block and the
///    navigation bar stand at the bottom of the screen and do not scroll. The body ends at the
///    TOP EDGE of the zone (`bodyArea`) and is clipped by it: a block with no background is
///    transparent, and the screen background shows through it, not text. The zone is painted
///    OVER the body. Only the layout knows its height and the body is measured after it, so it
///    is the third child of this same object, not a wrapper on top;
///  * KEYBOARD (schema 9.13.0, `bottomZone.keyboard`): the pinned block rides ABOVE it, the
///    "low" part (navigation bar with the safe area inset) stays UNDER it, and the body ends
///    above the pinned block, so a focused field scrolls into this area. The keyboard height
///    is [keyboard], `MediaQuery.viewInsets.bottom` of the reader's own context: a host whose
///    `Scaffold` has already shrunk the screen gives zero, and nothing is subtracted twice. The
///    zone rises by `keyboard - low` if the keyboard is taller than the low part; if shorter,
///    the bar is visible and the zone stays put. Only for a page (not a layer: the layer lifts
///    itself);
///  * [shrink] (modal layer): the height is the content PLUS the zone, but not more than
///    available; for taller content the body scrolls, while the layer's app bar and zone stay.
///
/// Children in order: `[app bar?, body, pinned block?, low?]`; the presence of the first,
/// third and fourth is told by [hasBar], [hasPinned], [hasLow] (the child count could not
/// tell them apart).
class ScreenZones extends MultiChildRenderObjectWidget {
  const ScreenZones({
    super.key,
    required this.shrink,
    required this.overlap,
    this.keyboard = 0,
    this.bodyAtScreenTop = false,
    this.topInset = 0,
    this.hasBar = false,
    this.hasPinned = false,
    this.hasLow = false,
    this.tail,
    required super.children,
  });

  /// The floating bottom zone (schema 9.22.0): when set, the zone lies OVER the body, the body area reaches the
  /// bottom of the screen, and the holder is told the height of the zone for the end of the body's content.
  final ZoneTail? tail;

  final bool shrink;
  final double overlap;

  /// The body area starts at the top edge of the screen and the app bar lies over it (9.19.0).
  final bool bodyAtScreenTop;

  /// The top safe inset above the body area of a screen with no app bar (9.19.0).
  final double topInset;

  /// Height of the on-screen keyboard above this widget's bottom (`viewInsets.bottom`).
  final double keyboard;
  final bool hasBar;
  final bool hasPinned;
  final bool hasLow;

  @override
  RenderScreenZones createRenderObject(BuildContext context) => RenderScreenZones(
    shrink: shrink,
    overlap: overlap,
    keyboard: keyboard,
    bodyAtScreenTop: bodyAtScreenTop,
    topInset: topInset,
    hasBar: hasBar,
    hasPinned: hasPinned,
    hasLow: hasLow,
    tail: tail,
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderScreenZones renderObject) {
    renderObject
      ..shrink = shrink
      ..overlap = overlap
      ..keyboard = keyboard
      ..bodyAtScreenTop = bodyAtScreenTop
      ..topInset = topInset
      ..hasBar = hasBar
      ..hasPinned = hasPinned
      ..hasLow = hasLow
      ..tail = tail;
  }
}

class _ZoneParentData extends ContainerBoxParentData<RenderBox> {}

class RenderScreenZones extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<RenderBox, ContainerBoxParentData<RenderBox>> {
  RenderScreenZones({
    required bool shrink,
    required double overlap,
    required double keyboard,
    required bool bodyAtScreenTop,
    required double topInset,
    required bool hasBar,
    required bool hasPinned,
    required bool hasLow,
    ZoneTail? tail,
  }) : _shrink = shrink,
       _tail = tail,
       _overlap = overlap,
       _keyboard = keyboard,
       _bodyAtScreenTop = bodyAtScreenTop,
       _topInset = topInset,
       _hasBar = hasBar,
       _hasPinned = hasPinned,
       _hasLow = hasLow;

  ZoneTail? _tail;
  set tail(ZoneTail? value) {
    if (_tail == value) return;
    _tail = value;
    markNeedsLayout();
  }

  bool _bodyAtScreenTop;
  set bodyAtScreenTop(bool value) {
    if (_bodyAtScreenTop == value) return;
    _bodyAtScreenTop = value;
    markNeedsLayout();
  }

  double _topInset;
  set topInset(double value) {
    if (_topInset == value) return;
    _topInset = value;
    markNeedsLayout();
  }

  double _keyboard;
  set keyboard(double value) {
    if (_keyboard == value) return;
    _keyboard = value;
    markNeedsLayout();
  }

  bool _hasBar;
  set hasBar(bool value) {
    if (_hasBar == value) return;
    _hasBar = value;
    markNeedsLayout();
  }

  bool _hasPinned;
  set hasPinned(bool value) {
    if (_hasPinned == value) return;
    _hasPinned = value;
    markNeedsLayout();
  }

  bool _hasLow;
  set hasLow(bool value) {
    if (_hasLow == value) return;
    _hasLow = value;
    markNeedsLayout();
  }

  bool _shrink;
  set shrink(bool value) {
    if (_shrink == value) return;
    _shrink = value;
    markNeedsLayout();
  }

  double _overlap;
  set overlap(double value) {
    if (_overlap == value) return;
    _overlap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ZoneParentData) child.parentData = _ZoneParentData();
  }

  RenderBox? get _bar => _hasBar ? firstChild : null;
  RenderBox? get _body => _hasBar ? childAfter(firstChild!) : firstChild;
  RenderBox? get _pinned => _hasPinned ? childAfter(_body!) : null;
  RenderBox? get _low => _hasLow ? lastChild : null;

  Size _arrange(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints c) measure,
    void Function(RenderBox, Offset)? place, {
    void Function(double zoneHeight)? onZoneHeight,
  }) {
    final width = constraints.maxWidth;
    final bar = _bar;
    final body = _body;
    final pinned = _pinned;
    final low = _low;
    final bounded = constraints.hasBoundedHeight;
    final maxHeight = bounded ? constraints.maxHeight : double.infinity;
    var barHeight = 0.0;
    if (bar != null) {
      final size = measure(bar, BoxConstraints(minWidth: width, maxWidth: width, maxHeight: maxHeight));
      barHeight = size.height;
      place?.call(bar, Offset.zero);
    }
    // The bottom zone is measured BEFORE the body: its height does not depend on the scroll, and
    // the body takes what is left above it (`bodyArea`). The zone's height does not depend on the
    // screen: a screen shorter than its own zone gives the body zero and the zone extends past its
    // bottom, which causes no overflow.
    final tight = BoxConstraints(minWidth: width, maxWidth: width);
    final pinnedHeight = pinned == null ? 0.0 : measure(pinned, tight).height;
    final lowHeight = low == null ? 0.0 : measure(low, tight).height;
    final bottomHeight = pinnedHeight + lowHeight;
    // A FLOATING ZONE (schema 9.22.0): lies over the body, and the body's content gets its height at the end. Only with
    // a finite height and not in a layer sized to its content: there is no bottom of the screen to float over.
    final floats = _tail != null && bounded && !_shrink && low != null;
    if (floats) onZoneHeight?.call(bottomHeight);
    // The keyboard raises the zone only by the part by which it is taller than the low part: the
    // low part stays under it, the pinned block goes above it. Only for a page (not a layer) and
    // only with a finite height: the layer lifts itself.
    final lift = bounded && !_shrink ? math.max(0.0, _keyboard - lowHeight) : 0.0;
    // Top of the body area; may be above the screen (overlap greater than the app bar). From the top
    // edge of the screen with `bodyTop: screenTop`; below the inset on a screen without an app bar.
    final top = _bodyAtScreenTop ? 0.0 : (bar == null ? _topInset : barHeight - _overlap);
    var bodyBottom = top;
    if (body != null) {
      final room = bounded ? math.max(0.0, maxHeight - (floats ? 0.0 : bottomHeight) - lift - top) : double.infinity;
      final fill = bounded && !_shrink;
      // A layer as tall as its content is not lower than the app bar that lies over it: the body area
      // reaches the bar's bottom edge (`bodyTop` with a bar in a layer).
      final floor = _shrink && _bodyAtScreenTop ? math.max(0.0, barHeight - bottomHeight) : 0.0;
      final size = measure(
        body,
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          minHeight: fill ? room : math.min(floor, room),
          maxHeight: room,
        ),
      );
      place?.call(body, Offset(0, top));
      bodyBottom = top + size.height;
    }
    // Top of the bottom zone = bottom of the body area, but not above the app bar's bottom edge.
    // A floating zone stands at the bottom of the screen whatever the body is: it is over it, not below it.
    final zoneTop = math.max(floats ? maxHeight - lift - bottomHeight : bodyBottom, barHeight);
    if (pinned != null) place?.call(pinned, Offset(0, zoneTop));
    if (low != null) place?.call(low, Offset(0, zoneTop + pinnedHeight));
    var height = zoneTop + bottomHeight;
    if (bounded) height = math.min(height, maxHeight);
    if (bounded && !_shrink) height = maxHeight;
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    size = _arrange(
      constraints,
      (child, c) {
        child.layout(c, parentUsesSize: true);
        return child.size;
      },
      (child, offset) => (child.parentData! as ContainerBoxParentData<RenderBox>).offset = offset,
      // The end of the body's content is a child of ours, and its size changes with the zone: the update is made
      // in a layout callback, before the body is measured, as a `LayoutBuilder` does.
      onZoneHeight: (height) => invokeLayoutCallback<BoxConstraints>((_) => _tail!.height = height),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _arrange(constraints, (child, c) => child.getDryLayout(c), null);

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsic(width, (child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsic(width, (child, w) => child.getMaxIntrinsicHeight(w));

  double _intrinsic(double width, double Function(RenderBox child, double width) of) {
    final bar = _bar;
    final body = _body;
    final barHeight = bar == null ? 0.0 : of(bar, width);
    final bodyHeight = body == null ? 0.0 : of(body, width);
    final pinned = _pinned;
    final low = _low;
    final bottomHeight = (pinned == null ? 0.0 : of(pinned, width)) + (low == null ? 0.0 : of(low, width));
    final bodyEnd = _bodyAtScreenTop
        ? bodyHeight
        : (bar == null ? _topInset + bodyHeight : barHeight - _overlap + bodyHeight);
    return math.max(barHeight, bodyEnd) + bottomHeight;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    var result = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      result = math.max(result, child.getMaxIntrinsicWidth(height));
    }
    return result;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_bodyAtScreenTop) return defaultHitTestChildren(result, position: position);
    // The app bar lies over the body, so it is asked first (after the bottom zone, which is over both).
    for (final child in [_low, _pinned, _bar, _body]) {
      if (child == null) continue;
      final parentData = child.parentData! as ContainerBoxParentData<RenderBox>;
      final hit = result.addWithPaintOffset(
        offset: parentData.offset,
        position: position,
        hitTest: (result, transformed) => child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final bar = _bar;
    final body = _body;
    // With `bodyTop: screenTop` the app bar is painted OVER the body, after it.
    if (bar != null && !_bodyAtScreenTop) {
      context.paintChild(bar, (bar.parentData! as ContainerBoxParentData<RenderBox>).offset + offset);
    }
    if (body != null) {
      final local = (body.parentData! as ContainerBoxParentData<RenderBox>).offset;
      if (local.dy >= 0) {
        context.paintChild(body, local + offset);
      } else {
        // The body area is taller than the top of the screen (overlap greater than the app bar): the
        // part above is clipped by the screen.
        context.pushClipRect(needsCompositing, offset, Offset.zero & size, (context, at) {
          context.paintChild(body, local + at);
        });
      }
    }
    if (bar != null && _bodyAtScreenTop) {
      context.paintChild(bar, (bar.parentData! as ContainerBoxParentData<RenderBox>).offset + offset);
    }
    // The bottom zone is OVER the body and does not scroll; the body's scroll clips whatever went
    // past the zone's top edge (the body area ends here).
    final pinned = _pinned;
    if (pinned != null) {
      context.paintChild(pinned, (pinned.parentData! as ContainerBoxParentData<RenderBox>).offset + offset);
    }
    final low = _low;
    if (low != null) {
      context.paintChild(low, (low.parentData! as ContainerBoxParentData<RenderBox>).offset + offset);
    }
  }
}

/// The top safe inset the reader adds, from the reader's OWN context (`MediaQuery.viewPadding.top`;
/// a host that wrapped the reader in a `SafeArea` gives zero). Clamped by the screen height when the
/// context knows it: a host's `MediaQuery` that carries no size does not turn the inset into zero.
double topInsetOf(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  return safeTopOf(MediaQuery.viewPaddingOf(context).top, height > 0 ? height : double.infinity);
}

/// The height of the floating bottom zone, handed from [RenderScreenZones] to the end of the body's content
/// ([ZoneTailPadding]) while the zone is being laid out.
class ZoneTail {
  double _height = 0;
  final Set<RenderZoneTailPadding> _pads = {};

  double get height => _height;

  set height(double value) {
    if (_height == value) return;
    _height = value;
    for (final pad in _pads) {
      pad.markNeedsLayout();
    }
  }
}

/// Space at the end of the body's content as tall as the floating zone: the last row scrolls clear of it. The
/// space is a part of the content, so the free space `Screen.justify` distributes is counted without it.
class ZoneTailPadding extends SingleChildRenderObjectWidget {
  const ZoneTailPadding({super.key, required this.tail, required super.child});

  final ZoneTail tail;

  @override
  RenderZoneTailPadding createRenderObject(BuildContext context) => RenderZoneTailPadding(tail);

  @override
  void updateRenderObject(BuildContext context, covariant RenderZoneTailPadding renderObject) {
    renderObject.tail = tail;
  }
}

class RenderZoneTailPadding extends RenderShiftedBox {
  RenderZoneTailPadding(this._tail) : super(null);

  ZoneTail _tail;
  set tail(ZoneTail value) {
    if (_tail == value) return;
    _tail._pads.remove(this);
    _tail = value;
    if (attached) _tail._pads.add(this);
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _tail._pads.add(this);
  }

  @override
  void detach() {
    _tail._pads.remove(this);
    super.detach();
  }

  BoxConstraints _inner(BoxConstraints constraints) => constraints.deflate(EdgeInsets.only(bottom: _tail.height));

  @override
  double computeMinIntrinsicHeight(double width) => (child?.getMinIntrinsicHeight(width) ?? 0) + _tail.height;

  @override
  double computeMaxIntrinsicHeight(double width) => (child?.getMaxIntrinsicHeight(width) ?? 0) + _tail.height;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = child?.getDryLayout(_inner(constraints)) ?? Size.zero;
    return constraints.constrain(Size(inner.width, inner.height + _tail.height));
  }

  @override
  void performLayout() {
    final box = child;
    if (box == null) {
      size = constraints.constrain(Size(0, _tail.height));
      return;
    }
    box.layout(_inner(constraints), parentUsesSize: true);
    (box.parentData! as BoxParentData).offset = Offset.zero;
    size = constraints.constrain(Size(box.size.width, box.size.height + _tail.height));
  }
}

/// Owns the [ZoneTail] of a screen with a floating bar for as long as the screen is drawn, and builds the zones with it.
class ZoneTailHost extends StatefulWidget {
  const ZoneTailHost({super.key, required this.builder});

  final Widget Function(ZoneTail tail) builder;

  @override
  State<ZoneTailHost> createState() => _ZoneTailHostState();
}

class _ZoneTailHostState extends State<ZoneTailHost> {
  final ZoneTail _tail = ZoneTail();

  @override
  Widget build(BuildContext context) => widget.builder(_tail);
}
