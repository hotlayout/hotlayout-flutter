/// Progress: the bar, the ring and the label inside the ring.
library;

import 'package:flutter/material.dart';

import '../../model/bindable.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/progress_cap.dart';
import '../../model/progress_rules.dart';
import '../../model/segment_transition.dart';
import '../../model/style_values.dart';
import '../../model/tokens.dart';
import '../layout/quiet_flex.dart';
import '../node_renderer.dart';
import '../progress_paint.dart';
import '../render_scope.dart';
import '../value_transition.dart' show TransitionLeads;
import 'node_box.dart';
import 'render_tokens.dart';

extension ProgressWidgets on NodeRenderer {
  /// The scale's paint (track and fill) resolved against the theme, for the bar and the ring.
  /// The track lies under the WHOLE scale, the fill on top.
  (Color, ProgressFill) _progressPaint(
    FieldColor color,
    ColorRef? trackColor,
    GradientRef? gradient,
  ) {
    final paint = theme.resolveProgressPaint(color: color, trackColor: trackColor, gradient: gradient);
    final colors = paint.colors;
    return (
      paint.track,
      colors == null ? ProgressFill.solid(paint.fill!) : ProgressFill.gradient(colors, paint.positions!),
    );
  }

  /// The scale thickness (schema 9.7.0): a spacing token or an integer from the document; if
  /// there is no field, it has the wrong shape or the theme does not know the token, then
  /// `defaultThickness`.
  double _progressThickness(ScaleRef? ref) =>
      (ref == null ? null : theme.resolveSpacing(ref)) ?? theme.spacing[kDefaultProgressThickness] ?? 0;

  /// The label of a scale. `percent` is the SHOWN ratio; `valueOfMax` writes the numbers in steps while they are being
  /// led to their new values (schema 9.21.0): whole when both ends are whole, otherwise three digits. Without a
  /// transition [NodeRenderer.data] is the data itself and this is the plain label.
  String? _progressLabel(
    ProgressLabelFormatToken format,
    BindableNumber valueRef,
    BindableNumber maxRef,
    double ratio,
  ) => switch (format) {
    ProgressLabelFormatToken.valueOfMax =>
      '${formatNumber(valueRef.resolve(data.labelView))} / ${formatNumber(maxRef.resolve(data.labelView))}',
    ProgressLabelFormatToken.percent => '${(ratio * 100).round()}%',
    ProgressLabelFormatToken.none => null,
  };

  /// The steps filled WHILE a value leads (schema 9.25.0, `x-segmentsTransition`): a number with a fraction between the
  /// whole steps of the two ends. `null` when neither the value nor the max runs a transition now, and the bar is
  /// drawn in whole steps from the ratio it has.
  double? _segmentUnits(ProgressBarNode node, TransitionLeads leads) {
    final segments = node.segments;
    if (segments == null) return null;
    ({num from, num to})? leadOf(BindableNumber ref) => ref is BoundNumber ? leads[ref.path] : null;
    final valueLead = leadOf(node.value);
    final maxLead = leadOf(node.max);
    if (valueLead == null && maxLead == null) return null;
    final shownValue = node.value.resolve(data);
    final shownMax = node.max.resolve(data);
    final fromRatio = progressRatio(valueLead?.from ?? shownValue, maxLead?.from ?? shownMax);
    final toRatio = progressRatio(valueLead?.to ?? shownValue, maxLead?.to ?? shownMax);
    final eased = valueLead != null
        ? transitionShareOf(valueLead.from, valueLead.to, shownValue)
        : transitionShareOf(maxLead!.from, maxLead.to, shownMax);
    return segmentUnitsAt(fromRatio: fromRatio, toRatio: toRatio, segments: segments, eased: eased);
  }

  /// The progress bar. Geometry and paint follow `x-style.layout.progress.bar`; see
  /// [ProgressTrack].
  Widget buildProgressBar(ProgressBarNode node, {TransitionLeads leads = const {}}) {
    final value = node.value.resolve(data);
    final rawMax = node.max.resolve(data);
    // `max` is also a binding, so zero or a negative value from data is a real scenario: a
    // limit that is not a positive number means NO scale, not a full bar.
    final ratio = progressRatio(value, rawMax);
    final label = _progressLabel(node.labelFormat, node.value, node.max, ratio);
    final (trackColor, fill) = _progressPaint(node.color, node.trackColor, node.gradient);
    return QuietColumn(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The track has no width of its own (`unweightedStretchInRow`): in a natural-width row a
        // bar without a label is zero wide, and with a label it is as wide as the label.
        Semantics(
          value: '${(ratio * 100).round()}',
          child: ProgressTrack(
            ratio: ratio,
            thickness: _progressThickness(node.thickness),
            pillRadius: theme.radius(RadiusToken.pill),
            trackColor: trackColor,
            fill: fill,
            // Segments (schema 9.11.0): the same scale drawn differently. A screen reader sees ONE
            // scale (`segmentsSemantics`), so there is a single semantics node.
            segments: node.segments,
            segmentGap: theme.spacing[kProgressSegmentGap] ?? 0,
            currentColor: node.currentColor == null ? null : theme.resolveColor(node.currentColor!),
            roundEnds: node.cap == ProgressCap.round,
            segmentUnits: node.segments == null ? null : _segmentUnits(node, leads),
            glow: node.glow,
          ),
        ),
        if (label != null) ...[
          SizedBox(height: theme.space(SpacingToken.xs)),
          // `bar.labelAlign: 'end'`: the label sits at the logical end of the track (the right in
          // left-to-right writing, the left in right-to-left).
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              label,
              style: theme
                  .text(TypographyToken.caption)
                  .copyWith(color: theme.color(ColorToken.muted)),
            ),
          ),
        ],
      ],
    );
  }

  /// The progress ring: the same scale as the bar, bent into an arc.
  ///
  /// THE DIAMETER AND THICKNESS COME FROM THE THEME, not from pixels: the diameter is a few
  /// units of the scale's largest spacing, the thickness is the same token that sets the bar
  /// track's height. This is not saving on constants: the ring and the bar are ONE scale in two
  /// forms, and a different thickness would read as different concepts. The same numbers are used
  /// by the other readers, so all of them measure the ring identically.
  ///
  /// The label is drawn only when `labelFormat` asks for it. By default the ring's center belongs
  /// to the document: what to put there is up to a `Stack`.
  Widget buildCircularProgress(CircularProgressNode node, NodeStyle? own, Slot slot) {
    final value = node.value.resolve(data);
    final rawMax = node.max.resolve(data);
    // `max` is bindable, so zero from data is a real scenario, not a document error: there is
    // nothing to divide by, and the arc is simply absent.
    final ratio = progressRatio(value, rawMax);

    final geometry = _ringGeometry(node, own, slot);
    final diameter = geometry.diameter;

    /*
     * The label in the CENTER (schema 8.16.0). The expression is the same as the bar's, on
     * purpose: a divergence would mean "75 %" in the ring and "75 %" in the bar could differ on
     * the same data.
     */
    final label = _progressLabel(node.labelFormat, node.value, node.max, ratio);

    final (trackColor, fill) = _progressPaint(node.color, node.trackColor, node.gradient);
    final ring = CustomPaint(
      size: Size.square(diameter),
      painter: RingPainter(
        ratio: ratio,
        thickness: geometry.thickness,
        trackColor: trackColor,
        fill: fill,
        roundEnds: node.cap == ProgressCap.round,
        glow: node.glow,
      ),
    );

    return RingPlacement(
      diameter: diameter,
      /*
       * Without a label, just the ring. An extra `Stack` would draw nothing in the most common
       * case, but it would appear in the widget tree, and so in every test that reads that tree.
       */
      child: Semantics(
        value: '${(ratio * 100).round()}',
        child: label == null
            ? ring
            : Stack(
                alignment: Alignment.center,
                // A label wider than the ring's box (a large font in a small circle) lies over
                // the arc and sticks out of the box: the Stack does not clip it.
                clipBehavior: Clip.none,
                children: [
                  ring,
                  // The label is ONE centered line that does not wrap and is NOT clipped by the
                  // ring (schema 9.17.0, `progressLabel.overflow`): it lies over the arc and
                  // changes neither the node's box nor the diameter. It does not scale with the
                  // diameter: a 240 ring has the same `caption` as a 48 ring.
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: _ringLabelStyle(node),
                  ),
                ],
              ),
      ),
    );
  }

  /// The RING LABEL STYLE (schema 9.17.0, `progressLabel`): the named `labelTypography` and
  /// `labelColor`, and where they are absent or of the wrong shape, `caption` / `onSurface`. A
  /// token the theme does not know gives the fallback style WHOLE: the overrides from
  /// `{token: 'hero', fontSize: 40}` are not carried over to `caption`. The label inherits
  /// nothing, neither the node's `style.color` / `typography` nor its emphasis, so it is taken
  /// from the theme and not from [currentForeground]. It has no italics or line.
  TextStyle _ringLabelStyle(CircularProgressNode node) {
    final named = node.labelTypography == null ? null : theme.resolveTypography(node.labelTypography!);
    final color = node.labelColor == null ? null : theme.resolveColor(node.labelColor!);
    // Tabular figures: a label like "74 / 119" keeps its width when the digits change and does
    // not push the slash.
    return (named ?? theme.text(TypographyToken.caption)).copyWith(
      color: color ?? theme.color(ColorToken.onSurface),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// The ring's diameter and thickness (`ring.diameter`, `namedSide`, `maxThickness`).
  ///
  /// A side is named by any of the three fields of its axis, but only one the reader APPLIES:
  /// under a row weight the three width fields do not apply, and on a full-stack layer none do
  /// (`_sizeLimits` counts the same way). A size given by the PARENT does not name the diameter.
  RingGeometry _ringGeometry(CircularProgressNode node, NodeStyle? own, Slot slot) {
    final inline = slot == Slot.free;
    final block = slot != Slot.fill;
    final padding = theme.resolveBoxSpacing(own?.padding);
    return ringGeometry(
      RingBoxInput(
        size: node.size.wire,
        unit: theme.spacing[kRingSizeUnit] ?? 0,
        thickness: _progressThickness(node.thickness),
        width: inline ? dimension(own?.width) : null,
        minWidth: inline ? dimension(own?.minWidth) : null,
        maxWidth: inline ? dimension(own?.maxWidth) : null,
        height: block ? dimension(own?.height) : null,
        minHeight: block ? dimension(own?.minHeight) : null,
        maxHeight: block ? dimension(own?.maxHeight) : null,
        paddingInline: padding?.horizontal ?? 0,
        paddingBlock: padding?.vertical ?? 0,
        border: borderSide(own?.border)?.width ?? 0,
      ),
    );
  }

}
