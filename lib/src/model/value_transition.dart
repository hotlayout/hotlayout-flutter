import 'dart:math' as math;

import 'bindable.dart';
import 'binding_format.dart';
import 'node.dart';

/// A VALUE THAT LEADS TO ITS NEW VALUE (schema 9.21.0, `animateChanges`; rules in `x-valueTransition`).
///
/// A flag on `Text`, `ProgressBar` and `CircularProgress`. When the DATA change the value of a node that is
/// already shown, the reader leads from the old value to the new one: the number of a text counts through the
/// values between, a scale grows. Without the field the value changes at once, exactly as before.
///
/// ONE FORMULA, taken from the contract and not from the platform: `p = min(1, t / 700)`, `e = 1 - (1 - p)^3`
/// (ease-out cubic; neither `Curves.easeOut` nor CSS `ease-out` is the same curve). At `t >= 700` the value
/// is exactly the new one. A number in a text moves in whole steps when both ends are whole, otherwise by the
/// fraction digits of the currency (or three), and the step is cut towards the OLD value, so the number
/// neither jumps over the new value nor reaches it before the end.
///
/// WHAT THIS FILE IS. The model has no widgets: the form of the field, the arithmetic, the decision whether a
/// change leads at all, and the list of numbers a node leads. The widget that holds the state is
/// `render/value_transition.dart`.

/// The duration of a transition, milliseconds. Data, not a field: one for all numbers of a product.
const int kValueTransitionMs = 700;

/// The digits kept of a product before it is cut towards the old value (the `0.1 * 3` trap).
const int kValueTransitionPrecision = 6;

/// The curve: ease-out cubic of the share [progress] of the duration, clamped to 0…1.
double valueTransitionEase(double progress) {
  final p = math.min(1.0, math.max(0.0, progress));
  return 1 - math.pow(1 - p, 3).toDouble();
}

bool _isWhole(num value) => value.isFinite && value == value.truncateToDouble();

/// The step of a number in a text: whole when both ends are whole; otherwise the fraction digits of the
/// currency (`currency` with a code), or three (`number` and no format).
int transitionDigitsOf(num from, num to, BindingFormat? format, String? currency) {
  if (_isWhole(from) && _isWhole(to)) return 0;
  if (format == BindingFormat.currency && isCurrencyCode(currency)) return currencyFractionDigits(currency!);
  return kNumberFormatMaxFractionDigits;
}

/// `Math.round` of the reference implementation: halves go UP, towards plus infinity (Dart's `round` goes away
/// from zero, which differs on a negative half).
double _roundHalfUp(double value) => (value + 0.5).floorToDouble();

double _rounded(double value, int digits) {
  final scale = math.pow(10, digits).toDouble();
  return _roundHalfUp(value * scale) / scale;
}

/// The value shown [t] milliseconds after the transition began. [digits] is the step of a number in a text;
/// `null` is a scale (no step). At `t >= 700` (or a `t` that is not a number) it is exactly [to].
double transitionValueAt({required num from, required num to, required num t, int? digits}) {
  if (!t.isFinite || t >= kValueTransitionMs) return to.toDouble();
  final eased = valueTransitionEase(t / kValueTransitionMs);
  final delta = (to - from) * eased;
  if (digits == null) return from + delta;
  final scale = math.pow(10, digits).toDouble();
  final steps = _rounded(delta * scale, kValueTransitionPrecision).truncateToDouble();
  return _rounded(from + steps / scale, digits + kValueTransitionPrecision);
}

/// Why a change does NOT lead; the first reason in the order of `x-valueTransition.whenNoTransition.order`.
enum NoTransition { noField, firstShow, reducedMotion, localeChanged, notANumber, sameValue }

/// One change of the data under a node, as the decision sees it.
final class TransitionChange {
  const TransitionChange({
    required this.animates,
    required this.shownBefore,
    required this.from,
    required this.to,
    this.localeChanged = false,
    this.reducedMotion = false,
  });

  /// The field `animateChanges` is on the node.
  final bool animates;

  /// The node was already shown with the previous value (not its first frame, not an appearance).
  final bool shownBefore;
  final Object? from;
  final Object? to;
  final bool localeChanged;
  final bool reducedMotion;
}

/// Whether the change leads: `null` when it does, otherwise the reason the value becomes the new one at once.
/// The ORDER of the checks is part of the rule.
NoTransition? noTransitionBecause(TransitionChange change) {
  if (!change.animates) return NoTransition.noField;
  if (!change.shownBefore) return NoTransition.firstShow;
  if (change.reducedMotion) return NoTransition.reducedMotion;
  if (change.localeChanged) return NoTransition.localeChanged;
  bool finite(Object? value) => value is num && value.isFinite;
  if (!finite(change.from) || !finite(change.to)) return NoTransition.notANumber;
  if (change.from == change.to) return NoTransition.sameValue;
  return null;
}

/// A number a node leads: the data path, the format and code of the binding (for the step), and whether it is
/// the value or the max of a scale (the fill grows without a step; only the label steps).
final class TransitionTarget {
  const TransitionTarget(this.path, {required this.scale, this.format, this.currency});

  final String path;
  final bool scale;
  final BindingFormat? format;
  final String? currency;

  /// The same number for the same path: the signature of a document that did not change.
  String get signature => '$path|${format?.wire}|$currency|$scale';
}

/// Whether the number of a text with this format leads: no format, `number` and `currency`. A date, `daysUntil`
/// and a countdown part do not: their number is derived from the time.
bool transitionsInText(BindingFormat? format) =>
    format == null || format == BindingFormat.number || format == BindingFormat.currency;

TransitionTarget? _bindingTarget(BoundString binding, {required bool scale}) {
  if (!scale && !transitionsInText(binding.format)) return null;
  return TransitionTarget(
    binding.path,
    scale: scale,
    format: binding.format,
    currency: isCurrencyCode(binding.currency) ? binding.currency : null,
  );
}

/// The numbers of a node that lead: for a text, the binding `content` and every binding value of a template
/// with a numeric format (or none); for a scale, `value` and `max`, each its own.
List<TransitionTarget> transitionTargetsOf(UiNode node) {
  switch (node) {
    case TextNode(:final content):
      return switch (content) {
        final BoundString binding => [?_bindingTarget(binding, scale: false)],
        final TemplateString template => [
          for (final value in template.values.values)
            if (value is TemplateBinding) ?_bindingTarget(value.binding, scale: false),
        ],
        LiteralString() => const [],
      };
    case ProgressBarNode(:final value, :final max):
      return _scaleTargets(value, max);
    case CircularProgressNode(:final value, :final max):
      return _scaleTargets(value, max);
    default:
      return const [];
  }
}

List<TransitionTarget> _scaleTargets(BindableNumber value, BindableNumber max) => [
  if (value is BoundNumber) TransitionTarget(value.path, scale: true),
  if (max is BoundNumber) TransitionTarget(max.path, scale: true),
];

/// Mirror of `x-valueTransition` (scalar rows); checked against the artifact by a test.
const Map<String, Object> kValueTransitionRules = {
  'prop': 'animateChanges',
  'durationMs': kValueTransitionMs,
  'precision': kValueTransitionPrecision,
  'interrupted': 'a new change during a transition starts from the value shown at that moment, with the full duration',
  'semantics': 'the screen reader hears the final value, not the values between',
};

/// The order of `x-valueTransition.whenNoTransition.order`.
const List<String> kNoTransitionOrder = ['noField', 'firstShow', 'reducedMotion', 'localeChanged', 'notANumber', 'sameValue'];
