import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/wide_chrome_rules.dart';

/// The group of navigation bar items placed at the top (schema 9.18.0,
/// `x-style.layout.wideNav`).
///
/// Children are ready-made items, one per caption in [labels]. An item's width is NATURAL:
/// "inset, drawing, gap, caption (at most 160 wide), inset", with a gap between items; there
/// are no equal shares. The formulas are [wideNavItemWidth] and [wideNavGroupWidth], the same
/// ones the `wideNavItemCases` / `wideAppBarCases` / `wideNavBarCases` tables exercise; this
/// class only measures captions and places items.
///
/// The ITEM LOOK (with captions / drawings only) is decided by the width the parent gave:
/// with captions when they fit ALL TOGETHER (`overflow.perItem: 'no'`), otherwise drawings
/// only, each item being "inset, drawing, inset". An app-bar parent gives the width of the
/// already chosen look (tight), a standalone strip gives the content column width; in both
/// cases the rule is the same: "with captions if [wideNavGroupWidth] in the `labels` look is
/// not greater than the given width". So the look is a pure function of the natural widths
/// and the given width, and there is no "look -> width -> look" cycle.
///
/// A caption's natural width is measured with a [TextPainter] with no width limit, so it does
/// not depend on the look. A hidden caption stays in the tree (the item itself carries
/// `Semantics` with its name), so it becomes invisible but does not vanish for a screen
/// reader.
class WideNavGroup extends MultiChildRenderObjectWidget {
  const WideNavGroup({
    super.key,
    required this.labels,
    required this.labelStyle,
    required this.paddingInline,
    required this.iconWidth,
    required this.gap,
    required this.between,
    required super.children,
  });

  /// Item captions in child order.
  final List<String> labels;

  /// Caption font together with its colour; captions are measured with it.
  final TextStyle labelStyle;

  /// Item numbers before system scaling: side inset, drawing box width (font size), gap between
  /// drawing and caption, gap between items.
  final double paddingInline;
  final double iconWidth;
  final double gap;
  final double between;

  @override
  RenderWideNavGroup createRenderObject(BuildContext context) => RenderWideNavGroup(
    labels: labels,
    labelStyle: labelStyle,
    paddingInline: paddingInline,
    iconWidth: iconWidth,
    gap: gap,
    between: between,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderWideNavGroup renderObject) {
    renderObject
      ..labels = labels
      ..labelStyle = labelStyle
      ..paddingInline = paddingInline
      ..iconWidth = iconWidth
      ..gap = gap
      ..between = between
      ..textDirection = Directionality.of(context)
      ..textScaler = MediaQuery.textScalerOf(context);
  }
}

class _GroupParentData extends ContainerBoxParentData<RenderBox> {}

class RenderWideNavGroup extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RelayoutWhenSystemFontsChangeMixin {
  RenderWideNavGroup({
    required List<String> labels,
    required TextStyle labelStyle,
    required double paddingInline,
    required double iconWidth,
    required double gap,
    required double between,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) : _labels = labels,
       _labelStyle = labelStyle,
       _paddingInline = paddingInline,
       _iconWidth = iconWidth,
       _gap = gap,
       _between = between,
       _textDirection = textDirection,
       _textScaler = textScaler;

  List<String> _labels;
  List<double>? _measured;
  set labels(List<String> value) {
    if (_sameLabels(_labels, value)) return;
    _labels = value;
    _measured = null;
    markNeedsLayout();
  }

  TextStyle _labelStyle;
  set labelStyle(TextStyle value) {
    if (_labelStyle == value) return;
    _labelStyle = value;
    _measured = null;
    markNeedsLayout();
  }

  double _paddingInline;
  set paddingInline(double value) {
    if (_paddingInline == value) return;
    _paddingInline = value;
    markNeedsLayout();
  }

  double _iconWidth;
  set iconWidth(double value) {
    if (_iconWidth == value) return;
    _iconWidth = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  double _between;
  set between(double value) {
    if (_between == value) return;
    _between = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _measured = null;
    markNeedsLayout();
  }

  TextScaler _textScaler;
  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _measured = null;
    markNeedsLayout();
  }

  static bool _sameLabels(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The caption font (or the Arabic fallback) finished loading or changed: a measurement taken
  /// with the fallback font is stale, and a caption that would not fit the old width would be
  /// cut off with an ellipsis. Resets the measurement and lays the group out again.
  @override
  void systemFontsDidChange() {
    super.systemFontsDidChange();
    _measured = null;
    markNeedsLayout();
  }

  /// Natural caption widths: one line, no width limit. The cache lives only while the font,
  /// text, direction and scale stay the same (see [systemFontsDidChange]).
  List<double> get naturalLabelWidths => _measured ??= [
    for (final label in _labels)
      (TextPainter(
        text: TextSpan(text: label, style: _labelStyle),
        textDirection: _textDirection,
        textScaler: _textScaler,
        maxLines: 1,
      )..layout()).width,
  ];

  /// Item numbers in points (the drawing grows with the system font scale, like `IconBox`).
  WideNavMetrics get metrics {
    final scale = _iconWidth == 0 ? 1.0 : _textScaler.scale(_iconWidth) / _iconWidth;
    return WideNavMetrics(paddingInline: _paddingInline, iconWidth: _iconWidth * scale, gap: _gap, between: _between);
  }

  /// The item look at a given width: with captions if they all fit together.
  WideNavMode modeFor(double width) {
    if (!width.isFinite) return WideNavMode.labels;
    return wideNavGroupWidth(naturalLabelWidths, metrics, WideNavMode.labels) <= width + 1e-6
        ? WideNavMode.labels
        : WideNavMode.icons;
  }

  /// The look the group was last painted in (for tests).
  WideNavMode get drawnMode => _drawnMode;
  WideNavMode _drawnMode = WideNavMode.labels;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GroupParentData) child.parentData = _GroupParentData();
  }

  List<RenderBox> get _items {
    final items = <RenderBox>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      items.add(child);
    }
    return items;
  }

  Size _arrange(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints c) measure,
    void Function(RenderBox, Offset)? place,
  ) {
    final items = _items;
    if (items.isEmpty) return constraints.smallest;
    final widths = naturalLabelWidths;
    final m = metrics;
    final mode = modeFor(constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity);
    final starts = wideNavItemStarts(0, widths, m, mode);
    final natural = wideNavGroupWidth(widths, m, mode);
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : constraints.constrainWidth(natural);
    final sizes = <Size>[
      for (var i = 0; i < items.length; i += 1)
        measure(
          items[i],
          BoxConstraints(
            minWidth: i < starts.widths.length ? starts.widths[i] : 0,
            maxWidth: i < starts.widths.length ? starts.widths[i] : 0,
          ),
        ),
    ];
    var height = 0.0;
    for (final size in sizes) {
      height = math.max(height, size.height);
    }
    height = constraints.constrainHeight(height);
    if (place != null) {
      _drawnMode = mode;
      for (var i = 0; i < items.length && i < starts.starts.length; i += 1) {
        final x = _textDirection == TextDirection.ltr ? starts.starts[i] : width - starts.starts[i] - starts.widths[i];
        place(items[i], Offset(x, (height - sizes[i].height) / 2));
      }
    }
    return Size(width, height);
  }

  @override
  void performLayout() {
    size = _arrange(constraints, (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    }, (child, offset) => (child.parentData! as ContainerBoxParentData<RenderBox>).offset = offset);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _arrange(constraints, (child, c) => child.getDryLayout(c), null);

  @override
  double computeMinIntrinsicWidth(double height) => wideNavGroupWidth(naturalLabelWidths, metrics, WideNavMode.icons);

  @override
  double computeMaxIntrinsicWidth(double height) => wideNavGroupWidth(naturalLabelWidths, metrics, WideNavMode.labels);

  double _highest(double Function(RenderBox child, double width) of) {
    final widths = wideNavItemStarts(0, naturalLabelWidths, metrics, WideNavMode.labels).widths;
    var result = 0.0;
    var i = 0;
    for (var child = firstChild; child != null; child = childAfter(child), i += 1) {
      result = math.max(result, of(child, i < widths.length ? widths[i] : 0));
    }
    return result;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _highest((child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) => _highest((child, w) => child.getMaxIntrinsicHeight(w));

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // The group is a navigation landmark, like the bottom bar (`navBar.semantics.bar`).
    config
      ..role = SemanticsRole.navigation
      ..explicitChildNodes = true;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
