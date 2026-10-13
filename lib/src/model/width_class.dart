// Width-class adaptivity (schema 9.18.0): the width class and everything that follows from it.
// Mirrors `width-class.ts` of the reference implementation verbatim; the case table is
// `fixtures/adaptive/adaptive-cases.json`, run by `test/adaptive_cases_test.dart`.
//
// ONE DOCUMENT FOR ALL WIDTHS, BUILT PHONE-FIRST. The base is what the document always held;
// wider classes OVERRIDE it, and the cascade runs from narrow to wide: `medium` is laid over the
// base, `expanded` over the base with `medium`.
//
// HOW THE READER EXECUTES THIS: it does not teach every rule the word "class". It first RESOLVES
// the tree for its own class (effective `props`, `style` with width layers, `showOn` as a
// "hidden by class" flag) and then draws an ordinary 9.17 document. All rules about props (who
// accepts weights, where the main axis is, how many columns) run unchanged, since they look at
// the effective props.
//
// Visibility remains the ONE question `isVisible`: the class is one half, the data condition
// the other.

import 'package:flutter/foundation.dart';

/// The width class. There are three and no fourth: a very wide box is still `expanded`.
enum WidthClass {
  compact('compact'),
  medium('medium'),
  expanded('expanded');

  const WidthClass(this.wire);

  /// The document word (`showOn`, keys of `styleOn` / `propsOn`).
  final String wire;

  /// Document word to class; `null` means an unknown word (a class from a newer minor version).
  static WidthClass? tryParse(Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.wire == raw) return value;
    }
    return null;
  }
}

/// The width at which each class starts, in logical pixels (`widthClass.classes`).
///
/// The numbers are artifact DATA, not reader knowledge; a theme cannot customise them
/// (`customisable: 'no'`).
const Map<WidthClass, double> kWidthClassFrom = {
  WidthClass.compact: 0,
  WidthClass.medium: 600,
  WidthClass.expanded: 1024,
};

/// The class while the width is UNKNOWN (`unknownWidth`): the first frame, an infinite box.
const WidthClass kUnknownWidthClass = WidthClass.compact;

/// The WIDTH CLASS for the width of the box the screen is drawn in.
///
/// The width is NOT ROUNDED: 599.9 is `compact`, 600 is `medium`. A non-finite or negative width
/// means "unknown": `compact`.
WidthClass widthClassOf(num? width) {
  if (width == null || !width.isFinite || width < 0) return kUnknownWidthClass;
  if (width >= kWidthClassFrom[WidthClass.expanded]!) return WidthClass.expanded;
  if (width >= kWidthClassFrom[WidthClass.medium]!) return WidthClass.medium;
  return WidthClass.compact;
}

const List<WidthClass> _noLayers = [];
const List<WidthClass> _mediumLayers = [WidthClass.medium];
const List<WidthClass> _allLayers = [WidthClass.medium, WidthClass.expanded];

/// The override LAYERS that apply in a class, in the order they are laid on (`cascade`).
List<WidthClass> widthClassLayers(WidthClass widthClass) => switch (widthClass) {
  WidthClass.compact => _noLayers,
  WidthClass.medium => _mediumLayers,
  WidthClass.expanded => _allLayers,
};

// ───────────────────────────── visibility ─────────────────────────────

/// The classes on which a node is shown, if it NAMED them. `null` means the field is absent or of
/// the wrong shape (not an array, empty), so the node is visible everywhere. No known word at all
/// (classes from a newer minor version) is also `null`: hiding the node would leave a screen
/// without it at every width (`showOn.unknownClass`).
List<WidthClass>? showOnOf(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final known = <WidthClass>[];
  for (final entry in raw) {
    final parsed = WidthClass.tryParse(entry);
    if (parsed != null) known.add(parsed);
  }
  return known.isEmpty ? null : known;
}

/// Whether a node with this `showOn` is shown in this class, ignoring the data condition.
bool showsOnWidthClass(List<WidthClass>? classes, WidthClass widthClass) =>
    classes == null || classes.contains(widthClass);

// ───────────────────────────── properties ─────────────────────────────

/// The CLOSED LIST of properties each node type allows to be overridden
/// (`widthClass.props.byWidget`). Other types have none: their `propsOn` is not read.
const Map<String, List<String>> kResponsiveProps = {
  'Screen': ['gap', 'align', 'justify', 'contentMaxWidth'],
  'Column': ['gap', 'align', 'justify'],
  'Row': ['gap', 'align', 'justify', 'carousel'],
  'Container': ['direction', 'gap', 'align', 'justify'],
  'Grid': ['columns', 'gap'],
  'Repeater': ['direction', 'columns', 'gap', 'carousel'],
};

/// Limits of `columns` IN AN OVERRIDE (`widthClass.props.columns`): the base keeps 2..4, and a
/// single column is a grid with one cell per row.
const int kOverrideMinColumns = 1;
const int kOverrideMaxColumns = 6;

/// What is left of `props` after the layers of a class are laid on.
@immutable
final class EffectiveProps {
  const EffectiveProps(this.props, {this.columnsFromOverride = false});

  final Map<String, Object?> props;

  /// `columns` came from a layer, so its limits are 1..6, not the base's 2..4.
  final bool columnsFromOverride;
}

/// The properties a layer may REMOVE with `unset` (`widthUnset.props.byWidget`): a property whose absence is a state
/// of its own. Another property says "as without it" with an explicit value.
const Map<String, List<String>> kUnsettableProps = {
  'Screen': ['contentMaxWidth'],
};

/// The field names the `unset` key of [layersObject] (`styleOn` or `propsOn`) lists for [layer] (`unsetNamesOf`).
/// Nothing is removed by a key that is not an object, a list that is not a list, or an entry that is not a string;
/// a name outside [allowed] (when given) is skipped.
Set<String> unsetNamesOf(Object? layersObject, WidthClass layer, {Iterable<String>? allowed}) {
  if (layersObject is! Map) return const {};
  final unset = layersObject['unset'];
  if (unset is! Map) return const {};
  final names = unset[layer.wire];
  if (names is! List) return const {};
  final allowedSet = allowed?.toSet();
  return {
    for (final name in names)
      if (name is String && (allowedSet == null || allowedSet.contains(name))) name,
  };
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) return null;
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

/// The EFFECTIVE PROPS OF A NODE IN A WIDTH CLASS: the base with the `propsOn` layers laid on
/// (`effectivePropsOf`).
///
///  1. layers go from narrow to wide (`widthClassLayers`);
///  2. a layer overrides only the keys it NAMED; the rest stays as the layer below has it;
///  3. only a key from the CLOSED list of its own type is read; a key outside it leaves the base
///     alone;
///  4. `null` does not override; a layer or `propsOn` that is not an object is skipped;
///  5. of a carousel exactly `perView` is overridden, and only where a carousel ALREADY exists.
///
/// If nothing is overridden, the same props object is returned.
EffectiveProps effectivePropsOf(
  String type,
  Map<String, Object?> props,
  Object? propsOn,
  WidthClass widthClass,
) {
  final allowed = kResponsiveProps[type];
  final layers = widthClassLayers(widthClass);
  final all = _asMap(propsOn);
  if (allowed == null || layers.isEmpty || all == null) return EffectiveProps(props);

  Map<String, Object?>? result;
  var columns = false;
  for (final layer in layers) {
    // 9.19.0: what the layer REMOVES goes first (from the properties of the type that may be removed); what
    // it names comes after, so a property both removed and named takes the named value.
    for (final removed in unsetNamesOf(all, layer, allowed: kUnsettableProps[type] ?? const <String>[])) {
      if ((result ?? props).containsKey(removed)) {
        result ??= {...props};
        result.remove(removed);
      }
    }
    final override = _asMap(all[layer.wire]);
    if (override == null) continue;
    for (final key in allowed) {
      if (!override.containsKey(key)) continue;
      final current = result ?? props;
      final next = _overlaid(key, current[key], override[key]);
      if (next == null) continue;
      result ??= {...props};
      result[key] = next;
      if (key == 'columns') columns = true;
    }
  }
  return result == null ? EffectiveProps(props) : EffectiveProps(result, columnsFromOverride: columns);
}

/// One overriding value laid over the current one. `null` means the layer does NOT override
/// this key.
Object? _overlaid(String key, Object? below, Object? value) {
  if (value == null) return null;
  if (key != 'carousel') return value;
  final base = _asMap(below);
  final over = _asMap(value);
  if (base == null || over == null) return null;
  final perView = over['perView'];
  return perView == null ? null : {...base, 'perView': perView};
}

// ───────────────────────────── screen content width ─────────────────────────────

const int kContentMaxWidthMin = 320;
const int kContentMaxWidthMax = 1920;

/// The LARGEST CONTENT WIDTH as the reader reads it: an integer within the schema limits. A
/// non-number or non-integer means the field is absent; out of range it is clamped
/// (`literalOutOfRange`).
int? contentMaxWidthOf(Object? raw) {
  if (raw is! num || !raw.isFinite || raw != raw.truncateToDouble()) return null;
  return raw.toInt().clamp(kContentMaxWidthMin, kContentMaxWidthMax);
}

/// The screen content column: offset from the START of the box, and width.
@immutable
final class ScreenContentBox {
  const ScreenContentBox(this.start, this.width);

  final double start;
  final double width;

  @override
  bool operator ==(Object other) => other is ScreenContentBox && other.start == start && other.width == width;

  @override
  int get hashCode => Object.hash(start, width);

  @override
  String toString() => 'ScreenContentBox($start, $width)';
}

/// The SCREEN CONTENT COLUMN (`Screen.contentMaxWidth`).
///
/// [available] is the width the content would have WITHOUT the field. The column is no wider
/// than the number and is CENTRED; half of the remainder is not rounded. A screen narrower than
/// the number is unchanged.
ScreenContentBox screenContentBox(double available, int? contentMaxWidth) {
  final space = available < 0 ? 0.0 : available;
  if (contentMaxWidth == null || contentMaxWidth >= space) return ScreenContentBox(0, space);
  return ScreenContentBox((space - contentMaxWidth) / 2, contentMaxWidth.toDouble());
}

/// A strip along the screen width measured from the LEFT edge of the root box, in either writing
/// direction.
@immutable
final class ScreenInlineRect {
  const ScreenInlineRect(this.x, this.width);

  final double x;
  final double width;

  @override
  bool operator ==(Object other) => other is ScreenInlineRect && other.x == x && other.width == width;

  @override
  int get hashCode => Object.hash(x, width);

  @override
  String toString() => 'ScreenInlineRect($x, $width)';
}

/// Inline insets in logical terms: start and end.
typedef InlineInset = ({double start, double end});

/// Reference implementation: where along the width the CONTENT of each screen zone stands with
/// `contentMaxWidth` (`screenContentRects`).
///
///  * the BODY and the PINNED BLOCK are a column in the root box without its inline padding;
///  * the APP BAR keeps its BOX between the root's inline padding, and the content inside it is a
///    column in its own content box;
///  * the NAVIGATION BAR box runs edge to edge, and its items are a column in its content box.
({ScreenInlineRect body, ScreenInlineRect pinned, ScreenInlineRect appBar, ScreenInlineRect navBar})
screenContentRects({
  required double width,
  required InlineInset padding,
  required int? contentMaxWidth,
  InlineInset appBarInset = (start: 0, end: 0),
  InlineInset navBarInset = (start: 0, end: 0),
  required bool rtl,
}) {
  ScreenInlineRect column(double outer, InlineInset inset, double before) {
    final box = screenContentBox(outer - inset.start - inset.end, contentMaxWidth);
    final start = before + inset.start + box.start;
    return ScreenInlineRect(rtl ? width - start - box.width : start, box.width);
  }

  final inside = width - padding.start - padding.end;
  final body = column(width, padding, 0);
  return (
    body: body,
    pinned: body,
    appBar: column(inside, appBarInset, padding.start),
    navBar: column(width, navBarInset, 0),
  );
}

/// Mirror of `x-style.layout.widthClass` (scalar and list values); checked against the artifact
/// in `test/adaptive_cases_test.dart`. The `cases` block is the table address, not a rule.
const Map<String, Object> kWidthClassLayout = {
  'classes': [
    {
      'class': 'compact',
      'from': 0,
    },
    {
      'class': 'medium',
      'from': 600,
    },
    {
      'class': 'expanded',
      'from': 1024,
    },
  ],
  'unit': 'logical-px',
  'measured': 'the-box-the-screen-root-is-drawn-in-with-its-padding',
  'notMeasured': ['window', 'device', 'orientation', 'parent-node'],
  'rounding': 'none',
  'perScreen': 'one-class-for-the-whole-screen',
  'modalLayer': 'its-own-class-from-its-own-box',
  'unknownWidth': 'compact',
  'customisable': 'no',
  'cascade': {
    'order': ['base', 'medium', 'expanded'],
    'compact': 'base-only',
    'medium': 'base-then-medium',
    'expanded': 'base-then-medium-then-expanded',
    'merge': 'named-keys-replace-whole-top-level-values',
  },
  'showOn': {
    'field': 'showOn',
    'on': 'every-node-but-the-screen-root',
    'shown': 'class-is-listed-AND-visibleIf-holds',
    'noField': 'shown-on-every-class',
    'hidden': 'as-hidden-by-visibleIf-everywhere-the-contract-asks-visible',
    'asks': [
      'screen-zones',
      'app-bar-actions',
      'nav-items',
      'list-numbering',
      'form-required',
      'tabs',
      'stack-layers',
      'row-weights',
      'carousel-cards',
      'pinned-block',
    ],
    'unknownClass': 'word-skipped-none-known-means-shown',
  },
  'styleOn': {
    'field': 'styleOn',
    'order': ['style', 'styleOn.medium', 'styleOn.expanded', 'styleWhen'],
    'merge': 'top-level-fields-as-styleWhen',
    'stateOverWidth': 'the-first-matching-state-wins-over-every-width-layer',
    'inherits': 'the-resolved-style-as-any-style',
  },
  'props': {
    'field': 'propsOn',
    'byWidget': [
      {
        'type': 'Screen',
        'props': ['gap', 'align', 'justify', 'contentMaxWidth'],
      },
      {
        'type': 'Column',
        'props': ['gap', 'align', 'justify'],
      },
      {
        'type': 'Row',
        'props': ['gap', 'align', 'justify', 'carousel'],
      },
      {
        'type': 'Container',
        'props': ['direction', 'gap', 'align', 'justify'],
      },
      {
        'type': 'Grid',
        'props': ['columns', 'gap'],
      },
      {
        'type': 'Repeater',
        'props': ['direction', 'columns', 'gap', 'carousel'],
      },
    ],
    'columns': {
      'min': 1,
      'max': 6,
      'base': 'keeps-its-own-limits',
    },
    'carousel': {
      'overrides': ['perView'],
      'rest': 'from-base',
    },
    'carouselWithoutBase': 'not-read',
    'keyOutsideList': 'not-read',
    'values': 'read-by-the-same-rules-as-the-base-value',
    'rulesAboutProps': 'hold-in-every-class-with-the-effective-props',
    'parentField': 'legal-if-the-parent-accepts-it-in-some-class-read-only-where-it-does',
  },
  'contentMaxWidth': {
    'prop': 'contentMaxWidth',
    'min': 320,
    'max': 1920,
    'limits': ['app-bar-content', 'body-content', 'bottom-zone-content'],
    'edgeToEdge': ['root-background', 'app-bar-background', 'bottom-zone-background'],
    'parts': {
      'body': 'the-children-in-the-root-box-minus-root-inline-padding',
      'pinned': 'the-pinned-block-itself-same-column-as-the-body',
      'appBar': 'the-content-inside-the-bar-box-the-box-keeps-its-width',
      'navBar': 'the-items-inside-the-bar-box-the-box-stays-edge-to-edge',
    },
    'place': 'centred-same-in-ltr-and-rtl',
    'rounding': 'none',
    'narrower': 'no-effect',
    'dependsOnClass': 'no',
    'modalLayer': 'applies-inside-the-layer-box',
  },
  'olderReader': {
    'showOn': 'node-shown-on-every-width',
    'styleOn': 'base-style',
    'propsOn': 'base-props',
    'contentMaxWidth': 'full-width',
    'showOnLeadingZone':
        'node-in-the-leading-zone-of-the-app-bar-without-compact-in-showOn-is-drawn-on-the-phone-instead-of-the-back-arrow',
  },
};
