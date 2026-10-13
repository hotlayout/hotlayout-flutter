/// Contract tokens as Flutter values, and small helpers of the flow layouts.
library;

import 'package:flutter/material.dart';

import '../../model/bindable.dart';
import '../../model/tokens.dart';

Axis flowOf(ContainerDirectionToken direction) =>
    direction == ContainerDirectionToken.row ? Axis.horizontal : Axis.vertical;

/// Inserts [gap] between already built items.
List<Widget> spacedItems(List<Widget> items, double gap, Axis axis) {
  if (gap <= 0 || items.length < 2) return items;

  final spaced = <Widget>[];
  for (var index = 0; index < items.length; index += 1) {
    if (index > 0) {
      spaced.add(axis == Axis.horizontal ? SizedBox(width: gap) : SizedBox(height: gap));
    }
    spaced.add(items[index]);
  }
  return spaced;
}

/// `start` → -1, `center` → 0, `end` → 1: a coordinate of `AlignmentDirectional`.
///
/// One function for both axes on purpose: in a stack they are equal, and two identical
/// tables would drift apart on the first edit.
double alignFactor(AlignToken token) => switch (token) {
  AlignToken.start => -1,
  AlignToken.center => 0,
  AlignToken.end => 1,
};

WrapAlignment wrapAlign(JustifyToken justify) => switch (justify) {
  JustifyToken.start => WrapAlignment.start,
  JustifyToken.center => WrapAlignment.center,
  JustifyToken.end => WrapAlignment.end,
  JustifyToken.between => WrapAlignment.spaceBetween,
};

CrossAxisAlignment crossAxis(AlignToken align) => switch (align) {
  AlignToken.start => CrossAxisAlignment.start,
  AlignToken.center => CrossAxisAlignment.center,
  AlignToken.end => CrossAxisAlignment.end,
};

WrapCrossAlignment wrapCross(AlignToken align) => switch (align) {
  AlignToken.start => WrapCrossAlignment.start,
  AlignToken.center => WrapCrossAlignment.center,
  AlignToken.end => WrapCrossAlignment.end,
};

TextAlign textAlignOf(AlignToken align) => switch (align) {
  AlignToken.start => TextAlign.start,
  AlignToken.center => TextAlign.center,
  AlignToken.end => TextAlign.end,
};

TextOverflow textOverflowOf(TextOverflowToken token) => switch (token) {
  TextOverflowToken.clip => TextOverflow.clip,
  TextOverflowToken.ellipsis => TextOverflow.ellipsis,
  TextOverflowToken.visible => TextOverflow.visible,
};

String formatNumber(double value) => BoundString.stringify(value);
