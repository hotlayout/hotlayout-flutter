/// Reading a raw JSON node before its type is chosen, and the small readers of
/// single props.
part of '../node.dart';

/// A raw JSON node, split into parts before the type is chosen.
final class _RawNode {
  const _RawNode(
    this.id,
    this.type,
    this.props,
    this._rawChildren,
    this.visibleIf,
    this.style,
    this.styleWhen,
    this.fill,
    this.weight,
    this.layer,
    this.pull,
    this.pin,
    this.zone,
    this.motion,
    this.styleScrolled,
    this._keys,
    this.widthClass,
    this.hiddenByClass,
    this.columnsFromOverride, [
    this.depth = 0,
  ]);

  static _RawNode of(Object? raw, LocalizationKeys keys, WidthClass widthClass, [int depth = 0]) {
    if (raw is! Map) {
      return _RawNode('<malformed>', '<malformed>', const {}, null, null, null, const [], false, null, null, null, false, null, null, null, keys, widthClass, false, false, depth);
    }
    final json = Map<String, Object?>.from(raw);
    final type = json['type'] is String ? json['type'] as String : '<no-type>';
    final baseProps = json['props'] is Map ? Map<String, Object?>.from(json['props'] as Map) : const <String, Object?>{};
    // 9.18.0: props and style are the EFFECTIVE ones for the class; on `compact` and with no overrides
    // this is exactly what was written.
    final effective = effectivePropsOf(type, baseProps, json['propsOn'], widthClass);
    return _RawNode(
      json['id'] is String ? json['id'] as String : '<no-id>',
      type,
      effective.props,
      json['children'] is List ? json['children'] as List : null,
      json['visibleIf'],
      _styleInClass(json, widthClass),
      StyleCase.parseList(json['styleWhen']),
      // Only `true` means anything: in the contract the field's absence is the "ordinary layer", so any
      // other value is broken data and is read the same as absence.
      json['fill'] == true,
      _weight(json['weight']),
      readLayerValue(json['layer']),
      readSpacingRef(json['pull']),
      // 9.12.0: only the word `bottom` (`unreadablePin`); anything else means no field.
      json['pin'] == 'bottom',
      // 9.16.0: only the word `leading` (`appBarLeading.unknown: 'no-field'`).
      barZoneOf(json['zone']),
      // 9.20.0: a form this reader cannot draw is no motion (the node stands).
      NodeMotion.tryParse(json['motion']),
      // 9.21.0: the scrolled style is read by the schema of the app bar only; the node type decides whether it is
      // used, so a stray field on another node is never read.
      readScrolledStyle(json['styleScrolled']),
      keys,
      widthClass,
      // 9.18.0: `showOn` is the second, independent half of "is the node visible".
      !showsOnWidthClass(showOnOf(json['showOn']), widthClass),
      effective.columnsFromOverride,
      depth,
    );
  }

  /// THE BASE STYLE IN A CLASS (`baseStyleInWidthClass`): `style`, over it `styleOn.medium`, over that
  /// `styleOn.expanded`, field by field at the top level, like states. A layer of the wrong shape is
  /// skipped. The `styleWhen` states come last, at paint time. The layers merge BEFORE the theme is
  /// resolved.
  static NodeStyle? _styleInClass(Map<String, Object?> json, WidthClass widthClass) {
    var style = NodeStyle.parse(json['style']);
    final layers = widthClassLayers(widthClass);
    final all = json['styleOn'];
    if (layers.isEmpty || all is! Map) return style;
    for (final layer in layers) {
      // 9.19.0: the fields the layer removes go first, then the layer is laid on.
      style = style?.without(unsetNamesOf(all, layer));
      final overlay = NodeStyle.parse(all[layer.wire]);
      if (overlay != null) style = overlay.over(style);
    }
    return style;
  }

  final String id;
  final String type;
  final Map<String, Object?> props;
  final List<Object?>? _rawChildren;

  /// The raw visibility condition: [UiNode._parseChild] parses it later.
  final Object? visibleIf;

  /// The node's style (9.0.0). `null` means there is no style.
  final NodeStyle? style;

  /// The node's states (8.9.0). They cannot be applied while parsing: which one is in effect depends on
  /// the DATA, and data changes without the document being re-read.
  final List<StyleCase> styleWhen;

  /// A layer over the whole stack (8.14.0).
  final bool fill;

  /// The share of the row width (8.17.0).
  final int? weight;

  /// The place of a layer in a stack (9.10.0), already as the reader sees it; `null` means there is no
  /// field or it is not an object.
  final LayerPlacement? layer;

  /// Pulling (9.10.0): a spacing reference; `null` means there is no field or it is unreadable.
  final ScaleRef? pull;

  /// Pinned to the bottom (9.12.0): the word `bottom`, otherwise `false`.
  final bool pin;

  /// The app bar zone the child stands in (9.16.0); `null` means there is no field or it is a word from a
  /// newer minor.
  final BarZone? zone;

  /// The endless motion of the node (9.20.0); `null` for no field or a form this reader cannot draw.
  final NodeMotion? motion;

  /// The style of an app bar while its body is scrolled (9.21.0); `null` for no field or none readable.
  final NodeStyle? styleScrolled;

  final LocalizationKeys _keys;

  /// The width class this tree was resolved for (9.18.0).
  final WidthClass widthClass;

  /// The node is hidden BY THE CLASS (`showOn` does not name this class).
  final bool hiddenByClass;

  /// `columns` came from a `propsOn` layer: its bounds are 1..6.
  final bool columnsFromOverride;

  /// The localization key for this node's field, or `null` if the document has no translations at all.
  String? key(String path) => _keys.of(id, path);

  /// How many levels below the screen root this node stands (the root's children are level 1).
  final int depth;

  /// The children, parsed. Past [kReaderParseLimit] levels the subtree is not parsed at all
  /// (`depth.readerAboveParseLimit`): a document that deep is not one the builder publishes, and walking it
  /// recursively is how a stack overflows.
  List<ChildNode> childNodes() => _rawChildren == null || depth >= kReaderParseLimit
      ? const []
      : [for (final child in _rawChildren) UiNode._parseChild(_RawNode.of(child, _keys, widthClass, depth + 1))];

  /// The identifier of a leaf. Schema 4.0.0 gives leaves no `children` field at all, so a child in a
  /// `Text` is a structural error; in debug it shows in the log, and in release it is just ignored.
  String leafId() {
    if (kDebugMode && _rawChildren != null && _rawChildren.isNotEmpty) {
      debugPrint('[hotlayout] leaf node "$type" (id=$id) has children, ignored');
    }
    return id;
  }
}

bool _bool(Object? raw, bool fallback) => raw is bool ? raw : fallback;

/// The `align` word of the 9.15.0 fields: from the list, or "as without the field" (`fallback`), WITHOUT
/// a warning (`alignment.cross.unknownValue: 'as-without-prop'`). The contract has no `stretch` word; it
/// is unknown, like a number.
AlignToken _alignWord(Object? raw, AlignToken fallback) {
  if (raw is String) {
    for (final value in AlignToken.values) {
      if (value.wire == raw) return value;
    }
  }
  return fallback;
}

/// The `justify` word of the 9.15.0 fields, equally quiet (`alignment.main.unknownValue`).
JustifyToken _justifyWord(Object? raw) {
  if (raw is String) {
    for (final value in JustifyToken.values) {
      if (value.wire == raw) return value;
    }
  }
  return JustifyToken.start;
}

/// The `alt` of a picture or an icon (9.19.0, `AltText`): a plain string (translated under the key of the field) or
/// a string of the document (a binding, a template, a wrapped literal). Anything else, and an empty string, is no
/// description.
BindableString? _altOf(Object? raw, String? key) {
  if (raw is String) return raw.isEmpty ? null : LiteralString(raw, key: key);
  return raw is Map ? BindableString.parse(raw, key: key) : null;
}

/// A tab number from the document: a non-negative INTEGER. Everything else (a string, a fraction, a
/// negative, infinity, `null`) is `-1`, "there is no such tab", and what to do about it is decided by
/// `openTabIndex` (`initialTabOutOfRange: 'first-visible'`).
///
/// Before 9.0.0 broken data meant zero, i.e. the first tab, even when it was hidden; now the question
/// "which one is open" has one answer for all cases instead of two.
int _tabIndex(Object? raw) {
  if (raw is! num || !raw.isFinite || raw < 0 || raw != raw.truncateToDouble()) return -1;
  return raw.toInt();
}

/// An integer field with the contract's bounds (the schema's `minimum` / `maximum`): a number outside
/// the bounds is clamped (`literalOutOfRange: 'clamp'`), a NON-number gets the lower bound
/// (`nonNumericLiteral: 'lower-bound'`). A field that is absent from the document altogether is not
/// covered: `null`.
int? _intIn(Map<String, Object?> props, String key, int min, int max) {
  // An explicit `null` means no field (`nullNumericField: 'absent'`).
  final raw = props[key];
  if (raw == null) return null;
  if (raw is! num || raw.isNaN) return min;
  if (raw >= max) return max;
  if (raw <= min) return min;
  return raw.toInt();
}

/// The grid's column count, clamped to the contract bounds.
///
/// Clamping, not rejecting: a document with `columns: 9` describes a grid, and drawing it with four
/// columns is closer to the intent than drawing a column. A value that is not a number at all, however,
/// is not a "wide grid" but broken data, and the schema default is used for it.
///
/// [overridden] (9.18.0) means the number came from a `propsOn` layer: its bounds are 1..6
/// (`widthClass.props.columns`), while the base stays 2..4. One column is a grid with one cell per row.
int _gridColumns(Object? raw, {bool overridden = false}) {
  // A non-number gives the schema default, which is also the lower bound (2). NaN does not get through:
  // `toInt()` throws on it, so it is cut off before that.
  if (raw is! num || raw.isNaN) return kGridDefaultColumns;
  final max = overridden ? kOverrideMaxColumns : kGridMaxColumns;
  final min = overridden ? kOverrideMinColumns : kGridMinColumns;
  if (raw >= max) return max;
  if (raw <= min) return min;
  return raw.toInt();
}
