import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/media_chrome_rules.dart';
import '../model/wide_chrome_rules.dart';
import 'wide_nav_group.dart';

/// App bar layout: three zones in reading order (`x-style.layout.appBar`, schema 9.9.0).
///
/// Children in order: the "back" arrow (if [hasBack]), the title block, the group of navigation
/// items (if [hasNav], schema 9.18.0), then the app bar actions (their count is the remaining
/// children). The formula is [appBarZones] (with items, [wideAppBarZones]), the same one the
/// `appBarCases` / `wideAppBarCases` table exercises; this class only measures the children and
/// places them.
///
/// The ITEM GROUP ([WideNavGroup]) is part of the TRAILING zone, before the actions: "items,
/// app bar gap, actions" form one block pressed to the end of the row. The app bar decides the
/// look of the items from their NATURAL widths; whatever does not fit is cut at the END of the
/// app bar.
///
/// Why not `Row` / `NavigationToolbar` / `CustomMultiChildLayout`: the title sits in the CENTRE
/// OF THE APP BAR while it fits, otherwise it shifts by exactly as much as needed not to
/// overlap a zone; a gap exists only for zones that have content; the app bar's height is the
/// tallest of the three zones. `CustomMultiChildLayout` requires the size before the children
/// are measured, and `NavigationToolbar` always puts a gap and centres in the remainder.
class AppBarLayout extends MultiChildRenderObjectWidget {
  const AppBarLayout({
    super.key,
    required this.hasBack,
    required this.backSide,
    required this.gap,
    required this.actionGap,
    this.leadingIsNode = false,
    this.titleAlign = AppBarTitleAlign.center,
    this.hasNav = false,
    required super.children,
  });

  /// After the title comes the navigation item group ([WideNavGroup]): the navigation bar in
  /// the app bar on a wide place (schema 9.18.0).
  final bool hasNav;

  /// The first child is the content of the leading zone: the "back" arrow or (since schema
  /// 9.16.0, see [leadingIsNode]) a document node.
  final bool hasBack;

  /// The leading zone's content is a document node (a button or icon button with the `zone`
  /// field), not the built-in arrow. Its width is natural but at most half the app bar
  /// (`appBarLeadingWidth`).
  final bool leadingIsNode;

  /// Where the title block stands (schema 9.16.0): `start` means right after the leading zone.
  final AppBarTitleAlign titleAlign;

  /// Side of the arrow's square, in dp (step `xl`).
  final double backSide;

  /// Gap between a zone and the title (`sm`).
  final double gap;

  /// Gap between actions (`xs`).
  final double actionGap;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderAppBarLayout(
    hasBack: hasBack,
    backSide: backSide,
    gap: gap,
    actionGap: actionGap,
    leadingIsNode: leadingIsNode,
    titleAlign: titleAlign,
    hasNav: hasNav,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderAppBarLayout renderObject) {
    renderObject
      ..hasBack = hasBack
      ..backSide = backSide
      ..gap = gap
      ..actionGap = actionGap
      ..leadingIsNode = leadingIsNode
      ..titleAlign = titleAlign
      ..hasNav = hasNav
      ..textDirection = Directionality.of(context);
  }
}

class _AppBarParentData extends ContainerBoxParentData<RenderBox> {}

class RenderAppBarLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<RenderBox, ContainerBoxParentData<RenderBox>> {
  RenderAppBarLayout({
    required bool hasBack,
    required double backSide,
    required double gap,
    required double actionGap,
    bool leadingIsNode = false,
    AppBarTitleAlign titleAlign = AppBarTitleAlign.center,
    bool hasNav = false,
    required TextDirection textDirection,
  }) : _hasNav = hasNav,
       _hasBack = hasBack,
       _backSide = backSide,
       _gap = gap,
       _actionGap = actionGap,
       _leadingIsNode = leadingIsNode,
       _titleAlign = titleAlign,
       _textDirection = textDirection;

  bool _hasNav;
  set hasNav(bool value) {
    if (_hasNav == value) return;
    _hasNav = value;
    markNeedsLayout();
  }

  /// The navigation items did not fit even as drawings only: the app bar's edge cuts the excess.
  bool _clipped = false;

  /// The look of the navigation items in the app bar as last laid out (for tests); `null` means
  /// there are no items.
  WideNavMode? get navMode => _navMode;
  WideNavMode? _navMode;

  bool _leadingIsNode;
  set leadingIsNode(bool value) {
    if (_leadingIsNode == value) return;
    _leadingIsNode = value;
    markNeedsLayout();
  }

  AppBarTitleAlign _titleAlign;
  set titleAlign(AppBarTitleAlign value) {
    if (_titleAlign == value) return;
    _titleAlign = value;
    markNeedsLayout();
  }

  bool _hasBack;
  set hasBack(bool value) {
    if (_hasBack == value) return;
    _hasBack = value;
    markNeedsLayout();
  }

  double _backSide;
  set backSide(double value) {
    if (_backSide == value) return;
    _backSide = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  double _actionGap;
  set actionGap(double value) {
    if (_actionGap == value) return;
    _actionGap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AppBarParentData) child.parentData = _AppBarParentData();
  }

  /// Layout without side effects: [measure] measures a child (for real or as a dry run), [place]
  /// puts it. Returns the app bar's size.
  Size _arrange(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints childConstraints) measure,
    void Function(RenderBox child, Offset offset)? place,
  ) {
    final children = <RenderBox>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      children.add(child);
    }
    if (children.isEmpty) return constraints.smallest;

    var index = 0;
    final back = _hasBack && children.length > 1 ? children[index++] : null;
    final title = children[index++];
    final nav = _hasNav && index < children.length && children[index] is RenderWideNavGroup
        ? children[index++] as RenderWideNavGroup
        : null;
    final actions = children.sublist(index);
    final node = back != null && _leadingIsNode;

    const natural = BoxConstraints();
    var backSize = back == null ? Size.zero : measure(back, natural);
    // Natural width of the leading zone's node; `null` means an arrow or nothing is there.
    final leadingNatural = node ? backSize.width : null;
    final actionSizes = [for (final action in actions) measure(action, natural)];
    final titleNatural = measure(title, natural);
    final actionSides = [for (final size in actionSizes) size.width];
    // NAVIGATION ITEMS (schema 9.18.0): the natural widths of their captions do not depend on the
    // look, so the look cannot change what decides it.
    final navLabels = nav?.naturalLabelWidths ?? const <double>[];
    final navMetrics = nav?.metrics;

    AppBarZones zonesFor(double width) => appBarZones(
      width: width,
      showBack: back != null,
      backSide: _backSide,
      actionSides: actionSides,
      gap: _gap,
      actionGap: _actionGap,
      titleNatural: titleNatural.width,
      leadingNatural: leadingNatural,
      titleAlign: _titleAlign.name,
    );
    WideAppBarZones wideFor(double width) => wideAppBarZones(
      width: width,
      showBack: back != null,
      backSide: _backSide,
      actionSides: actionSides,
      gap: _gap,
      actionGap: _actionGap,
      titleNatural: titleNatural.width,
      leadingNatural: leadingNatural,
      titleAlign: _titleAlign.name,
      navLabels: navLabels,
      nav: navMetrics!,
    );

    // App bar width: tight/bounded if given; otherwise (infinite: the app bar is not in its place)
    // the natural one: zones and title in one line.
    double naturalWidth() {
      if (nav != null) {
        final wide = wideFor(double.infinity);
        return wide.zones.leading + titleNatural.width + wide.zones.trailing;
      }
      final zones = zonesFor(double.infinity);
      return zones.leading + titleNatural.width + zones.trailing;
    }

    final width = constraints.hasBoundedWidth ? constraints.maxWidth : constraints.constrainWidth(naturalWidth());

    final wide = nav == null ? null : wideFor(width);
    final zones = wide?.zones ?? zonesFor(width);
    final actionStarts = wide?.actionStarts ?? zones.actionStarts;
    // A node wider than half the app bar gets exactly half and lays its content out within it (a
    // button caption wraps by the button rule); the title is squeezed first.
    if (node && backSize.width > zones.leadingWidth + 0.001) {
      backSize = measure(back, BoxConstraints(maxWidth: zones.leadingWidth));
    }
    final titleSize = measure(title, BoxConstraints(maxWidth: zones.titleWidth, minWidth: zones.titleWidth));
    // The item group gets exactly the width the reference implementation computes for the chosen
    // look.
    final navSize = nav == null ? null : measure(nav, BoxConstraints.tightFor(width: wide!.navWidth));

    // Across the row everything is centred; the height is the tallest zone.
    var height = math.max(back == null ? 0.0 : backSize.height, titleSize.height);
    if (navSize != null) height = math.max(height, navSize.height);
    for (final size in actionSizes) {
      height = math.max(height, size.height);
    }
    height = constraints.constrainHeight(height);

    if (place != null) {
      _navMode = wide?.navMode;
      _clipped = wide?.clipped ?? false;
      // Zone coordinates run from the start of the row; in right-to-left writing, from the right edge.
      double x(double start, double extent) => _textDirection == TextDirection.ltr ? start : width - start - extent;
      if (back != null) {
        // The arrow is a `backSide` square, not the child's size: the child may be larger.
        place(back, Offset(x(0, backSize.width), (height - backSize.height) / 2));
      }
      place(title, Offset(x(zones.titleStart, titleSize.width), (height - titleSize.height) / 2));
      if (nav != null) {
        place(nav, Offset(x(wide!.navStart, navSize!.width), (height - navSize.height) / 2));
      }
      for (var i = 0; i < actions.length; i += 1) {
        place(actions[i], Offset(x(actionStarts[i], actionSizes[i].width), (height - actionSizes[i].height) / 2));
      }
    }
    return Size(width, height);
  }

  @override
  void performLayout() {
    size = _arrange(constraints, (child, childConstraints) {
      child.layout(childConstraints, parentUsesSize: true);
      return child.size;
    }, (child, offset) => (child.parentData! as ContainerBoxParentData<RenderBox>).offset = offset);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _arrange(constraints, (child, childConstraints) => child.getDryLayout(childConstraints), null);

  double _sumIntrinsic(double Function(RenderBox child) of) {
    var total = 0.0;
    var count = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      total += of(child);
      count += 1;
    }
    // Gaps: a zone has one only where it EXISTS.
    final zones = math.max(0, count - 1);
    return total + (zones > 0 ? _gap * math.min(zones, 2) : 0);
  }

  @override
  // The title is cut with an ellipsis, so the app bar has no minimum width.
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => _sumIntrinsic((child) => child.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) => _highest((child) => child.getMinIntrinsicHeight(double.infinity));

  @override
  double computeMaxIntrinsicHeight(double width) => _highest((child) => child.getMaxIntrinsicHeight(double.infinity));

  double _highest(double Function(RenderBox child) of) {
    var result = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      result = math.max(result, of(child));
    }
    return result;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    // Items and actions are never squeezed: whatever does not fit even as drawings only is cut at
    // the END of the app bar (`overflow.clipped`).
    if (_clipped) {
      context.pushClipRect(needsCompositing, offset, Offset.zero & size, defaultPaint);
    } else {
      defaultPaint(context, offset);
    }
  }
}
