import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../data/document_source.dart' show DocumentResponse, DocumentTooLargeException, DocumentTransport;

import '../model/compatibility.dart';
import '../model/style_values.dart' show isForbiddenKey;
import 'fallback_theme.dart';
import 'render_theme.dart';

// The version of the THEME CONTRACT this code understands.
//
// A constant separate from [kSupportedSchemaVersion] on purpose: the contracts are independent. A
// rebrand does not change the widget vocabulary, and a new widget does not change the palette.
// What they share is the compatibility rule ([checkContractVersion]), not the number.
//
// What needs a major version: `Theme` in `x-schema` is `additionalProperties: false`, so a NEW
// top-level theme field (such as `roles` or `gradient`) cannot be added in a minor version; an
// older reader reads such a theme as `incompatibleVersion` and falls back, never a silent
// substitution. What a minor version may do: add names to an existing map (`color.border`,
// `color.locked`), narrow the range of an existing field, or add an optional field inside an
// existing entry (`letterSpacing` in a typography entry). No theme written before the change
// becomes invalid.
//
// 4.0.0 opened the token vocabularies: six dictionaries (`color`, `gradient`, `spacing`,
// `radius`, `elevation`, `typography`) carry a mandatory CORE and any number of the project's
// OWN names. Colours gained alpha (`#rrggbbaa`), gradients gained four corner-to-corner
// diagonals, and roles may reference any colour of the theme.
/// The theme contract version this renderer understands.
const String kSupportedThemeContractVersion = '4.0.1';

/// WHAT TO DRAW A COLOUR WITH WHEN THE THEME LACKS IT.
///
/// The contract policy says `partialTheme: 'resolve-missing-to-defaults'`, but "resolve to
/// defaults" without a list of defaults is an instruction to INVENT them, and two readers would
/// invent differently. So the contract supplies the list in `x-optionalColors.fallbacks`, and this
/// map mirrors it.
///
/// The values are not arbitrary: they are exactly the tokens the roles borrowed BEFORE the
/// dedicated names existed. So an older theme looks in a newer reader exactly as it always did,
/// and upgrading the reader changes no pixel.
///
/// WHY A CONSTANT RATHER THAN READING THE ARTIFACT. The fallback is needed exactly when the
/// artifact may not have been readable, and a reader that goes back to the file that just failed
/// on its way to the fallback colour would be left without a colour a second time. A test
/// (`test/theme_contract_test.dart`) guards against drift from the artifact.
///
/// The keys are STRINGS: the theme palette is open, and names are looked up in it.
const Map<String, String> kThemeColorFallbacks = {
  'locked': 'muted',
  'inProgress': 'accent',
  'completed': 'success',
};

/// Default timeout of [ThemeLoad.fromNetwork]: three seconds.
///
/// Shorter than the document timeout on purpose: without a document there is nothing to draw,
/// while without a fresh theme there is a bundled one. Waiting longer for a colour than for
/// content would make the user stare at an empty screen for the sake of a shade.
const Duration kThemeFetchTimeout = Duration(seconds: 3);

/// The key under which the values themselves sit in the artifact envelope.
///
/// `theme.json` is an envelope: the root holds `x-schema` (so a foreign theme can be checked with
/// the same validator) and `x-*` metadata for people, while under [kContractKey] is the payload
/// that THIS schema describes. That way the artifact passes its own embedded schema, which is
/// `additionalProperties: false`, so `x-schema` next to the values at the root would be an extra
/// field.
const String kContractKey = 'contract';

/// The Dart-side mirror of `x-compatibility.policy` of the theme artifact.
///
/// These decisions are contract, not reader taste, and this file only mirrors them, as
/// `compatibility.dart` mirrors the policy of the widget schema.
///
/// `test/theme_contract_test.dart` checks the map against the artifact and, more importantly,
/// checks that every row is also IMPLEMENTED: a mirror that matches in text and differs in
/// behaviour is worse than none.
const Map<String, Object?> kThemeCompatibilityPolicy = {
  // The version rule is the same as for the widget schema; the numbers differ.
  'majorMustMatch': true,
  'minorAdditionsAreOptional': true,
  // An honestly named limit: `x-schema` describes EXACTLY this minor version, so a newer theme
  // cannot be validated with it. A reader that takes fields by key (as this one does) will read
  // it. The promise is true for a reader and false for a validator.
  'schemaDescribesExactVersion': true,
  'newerMinor': 'read-known-fields-only',
  // A theme that could not be read: show the fallback AND say so.
  'unreadableTheme': 'fallback-and-report',
  'unknownThemeId': 'use-default',
  // A name outside the core is NORMAL, not a "token from the future": the theme declares its own
  // tokens.
  'customTokens': 'declared-by-theme',
  // A custom name missing from one theme of the set is, for the document, the same unknown token:
  // the field default in `props`, "not applied" in `style`.
  'missingCustomToken': 'treat-as-unknown-token',
  'partialTheme': 'resolve-missing-to-defaults',
  // With what: a core value missing from an incomplete theme is taken from the BUILT-IN theme of
  // the SAME brightness (`RenderTheme.withMissingFromBuiltIn`). Not filled in: the three optional
  // state colours (they have their own fallbacks), custom tokens, and roles (`missingRole`).
  'partialThemeDefaults': 'built-in-theme-of-same-brightness',
  // `none` in `spacing` / `radius` / `elevation` is always zero. A reader that does not validate
  // enforces this itself (`RenderTheme._zeroNone`), because node defaults rely on the NAME.
  'zeroScaleToken': 'none-is-zero',
  // The reader does not invent a role that is missing from an existing group: it draws neutrally,
  // with `onSurface` text and no background or border. The reason: role keys are an enum from the
  // WIDGET schema that lives in the THEME contract, and the contracts are versioned
  // independently, so a new tone in the schema may get ahead of the theme, and the badge must
  // stay readable rather than disappear.
  'missingRole': 'render-neutral',
  // A role names a colour the theme does not declare: only the SLOT with the broken reference
  // becomes neutral (background and border as absent, foreground as the root colour); the rest of
  // the role stays.
  'unknownRoleColor': 'neutral-slot',
  // A theme without `roles` or with an incomplete core concerns a READER WITHOUT VALIDATION (a
  // validator would reject such a file): a missing role is neutral as a whole (`missingRole`), a
  // missing core value is taken from the built-in theme of the same brightness
  // (`partialThemeDefaults`). The key only names whom the rule applies to.
  'incompleteThemeAppliesTo': 'reader-without-validation',
  // A `__proto__` key in a token or role map: the ENTRY is dropped (`drop-entry`), and the theme
  // and the rest of its entries are read on.
  'protoKeyWithoutValidation': 'drop-entry',
  // The shadow order in the list is the opposite of Flutter's, hence the reversal in
  // `RenderTheme._shadows`.
  'shadowOrder': 'first-is-nearest',
  'lengthUnit': 'logical-pixels',
  'lineHeightUnit': 'font-size-multiple',
  // A typography entry without `letterSpacing` means zero, not the default letter spacing of the
  // platform style (`RenderTheme._typography` builds the style with `letterSpacing ?? 0`).
  'missingLetterSpacing': 'zero',
  // Alpha in a colour string is LAST, as in CSS; Flutter's `Color(int)` expects it first, which
  // `RenderTheme._color` reorders.
  'colorAlpha': 'rrggbbaa-alpha-last',
  // CSS measures a gradient angle against the real box geometry, while Flutter's `Alignment` uses
  // a normalised one, so a diagonal drawn by angle would be approximate and silently so. Axis
  // angles are drawn EXACTLY by both readers, so the translation in `RenderTheme._gradient` is a
  // lookup table, not trigonometry.
  //
  // The diagonals 45/135/225/315 are allowed too, but they mean "corner to corner", not degrees;
  // the table in `RenderTheme.gradientDirection` has eight rows and is still a table.
  'gradientAngleSpace': 'axis-as-css-diagonal-css-to-corner',
  // A diagonal has the exact geometry of CSS `to <corner>`: the 50 % isoline passes through the
  // two OTHER corners of the box. Drawn by `CornerGradient`.
  'diagonalGradientGeometry': 'css-to-corner',
  // JSON Schema cannot express ascending stop positions (it is a rule about neighbouring array
  // elements), so the promise is made by the policy and enforced by the reader.
  'gradientStopOrder': 'non-descending',
  // ... and enforces it like this: an unordered gradient is NOT drawn at all. Skia behaves
  // unpredictably on such stops, and a silently wrong gradient is worse than a missing one, since
  // nobody notices it as an error.
  'unorderedGradient': 'do-not-draw',
};

/// A set of themes: token names and the values behind them.
///
/// One file carries all themes of a project (for example a light and a dark
/// one) and names the default. Pick one with [themeForBrightness],
/// [defaultTheme] or [themeById].
///
/// It is a map rather than a single theme on purpose: the same document must render in a light,
/// dark or partner theme with no change to the document. Choosing the theme is the host's
/// decision, not the screen author's. This is the `contract` block of the artifact `theme.json`:
/// version, default theme and the MAP of themes.
@immutable
final class ThemeContract {
  /// Creates a set of themes. Normally read through [ThemeLoad].
  const ThemeContract({required this.version, required this.defaultThemeId, required this.themes});

  /// The theme built into the package, used when no theme file can be read.
  ///
  /// It is the embedded snapshot of the artifact and is used only through [ThemeLoad].
  factory ThemeContract.fallback() => _parseContract(kFallbackThemeContractJson)!;

  /// The theme contract version of the file.
  final String version;
  /// The id of the theme to use when nothing else is asked for.
  final String defaultThemeId;
  /// All themes by id.
  final Map<String, RenderTheme> themes;

  /// The theme named by [defaultThemeId].
  ///
  /// The trailing `themes.values.first` is not cosmetic: an artifact with a valid set of themes
  /// but a `defaultThemeId` that points nowhere is a generator error, and showing SOME theme
  /// beats showing none.
  RenderTheme get defaultTheme => themes[defaultThemeId] ?? themes.values.first;

  /// The theme with this id; the default theme for `null` or an unknown id.
  ///
  /// An unknown `id` is a normal situation of the same nature as an unknown token: the host may
  /// ask for a theme this artifact does not have yet (or any more).
  RenderTheme themeById(String? id) {
    if (id == null) return defaultTheme;
    final theme = themes[id];
    if (theme != null) return theme;
    if (kDebugMode) {
      debugPrint('[hotlayout] the contract has no theme "$id" → using "$defaultThemeId"');
    }
    return defaultTheme;
  }

  /// The theme marked with this brightness, so that system dark mode needs
  /// no theme ids in app code; the default theme when there is none.
  ///
  /// This is the `unknownThemeId` logic applied to brightness. `Theme.brightness` exists so that
  /// the mapping "dark mode to this theme" need not be hard-coded as a string in app code. If no
  /// theme of the needed brightness exists the default is used: a light theme in dark mode beats
  /// showing nothing.
  RenderTheme themeForBrightness(Brightness brightness) {
    for (final theme in themes.values) {
      if (theme.brightness == brightness) return theme;
    }
    if (kDebugMode) {
      debugPrint(
        '[hotlayout] the contract has no theme with brightness=${brightness.name} '
        '→ using "$defaultThemeId"',
      );
    }
    return defaultTheme;
  }

  /// Whether the set has a theme with this id.
  bool hasTheme(String id) => themes.containsKey(id);

  /// The ids of all themes.
  Iterable<String> get themeIds => themes.keys;
}

/// Why the theme in use is the one in use.
enum ThemeLoadStatus {
  /// The theme was read and is in use.
  ok,

  /// The asset could not be read. The built-in theme is used.
  ///
  /// This usually means the contract sync was not done, i.e. a build error rather than a runtime
  /// condition.
  assetMissing,

  /// The text is not a theme contract: not JSON, no version, or no usable
  /// theme. The built-in theme is used.
  malformed,

  /// The network gave no answer or a status other than 200. The bundled
  /// theme is used.
  ///
  /// Separate from [malformed] on purpose: "the server is silent" and "the server returned
  /// garbage" are different news. The first passes by itself and says nothing about our code; the
  /// second means someone published a broken theme.
  networkUnavailable,

  /// The theme's major contract version differs from the renderer's. The
  /// built-in theme is used.
  ///
  /// Values from such a theme MUST NOT be read: the structure differs, and "reading partially"
  /// would draw in the wrong colour.
  incompatibleVersion;

  /// Whether a fallback theme is in use instead of the one asked for.
  bool get isFallback => this != ThemeLoadStatus.ok;
}

/// A theme contract together with the answer to "where did it come from".
///
/// Loading never throws. When the file cannot be used, [contract] is a
/// fallback and [status] says why.
///
/// The behaviour executes `x-compatibility.policy`; it is not reader taste:
///
/// 1. `unreadableTheme: 'fallback-and-report'`: the app **draws the document with the built-in
///    fallback** ([ThemeContract.fallback]) AND reports the substitution. The reasoning (also in
///    the contract): a theme is presentation, not content. Without fresh colours the user sees a
///    slightly wrong shade; without a screen, nothing. For a document the decision is the
///    opposite (a foreign major gives a notice instead of a screen), which is no contradiction:
///    an incompatible document changes STRUCTURE, i.e. content, while an incompatible theme
///    changes only the look.
/// 2. "Report" is more than a log. [status] and [detail] travel with the contract as DATA: the
///    host may decide otherwise, for example not to show a brand-critical screen in foreign
///    colours. In `kDebugMode` a log line is added.
/// 3. `partialTheme: 'resolve-missing-to-defaults'`: the fallback is NOT pulled in when a theme
///    was read partially. One corrupt token is healed by the default resolver; replacing the
///    whole theme because of it would throw away ten correct values for one broken one.
@immutable
final class ThemeLoad {
  /// Creates a load result.
  const ThemeLoad({required this.contract, required this.status, this.detail});

  /// The themes to draw with.
  final ThemeContract contract;
  /// Why these themes are the ones to draw with.
  final ThemeLoadStatus status;

  /// The reason in words, for logs. English, not localized.
  final String? detail;

  /// Whether a fallback theme is in use.
  bool get isFallback => status.isFallback;

  /// Reads the theme from the app's assets. Never throws.
  ///
  /// The path is required because a default key would point to an asset that does not exist in
  /// someone else's app, so a call without a parameter would always give `assetMissing`, silently,
  /// with the built-in theme and "slightly wrong colours". The asset is declared by the host and
  /// only the host knows its key; whoever wants the built-in theme without a file uses
  /// [ThemeContract.fallback] directly.
  ///
  /// [assetPath] is the key of the theme file declared under `flutter: assets:`
  /// in the pubspec of **your** app. The package ships no theme asset of its
  /// own: its built-in theme is code ([ThemeContract.fallback]) and is what
  /// you get, with [ThemeLoadStatus.assetMissing], when the asset cannot be
  /// read.
  static Future<ThemeLoad> fromBundle({
    required String assetPath,
    AssetBundle? bundle,
  }) async {
    String source;
    try {
      source = await (bundle ?? rootBundle).loadString(assetPath);
    } on Object catch (error) {
      return _fallback(ThemeLoadStatus.assetMissing, 'cannot read $assetPath: $error');
    }
    return parse(source);
  }

  /// Reads the published theme over HTTP, falling back to the asset at
  /// [assetPath] when the network gives none.
  ///
  /// It falls back rather than failing, with the same policy as for an unreadable artifact
  /// (`unreadableTheme: 'fallback-and-report'`) and the same reason: a theme is presentation, not
  /// content. The fallback goes to the bundle, not to the embedded snapshot, because the bundled
  /// artifact is the theme the app was built with, i.e. the freshest thing certain to be
  /// compatible with THIS code; the embedded snapshot stays the last line, which `fromBundle`
  /// supplies. It never throws: the network fails in many ways, from DNS to garbage instead of
  /// JSON, and each has the same answer: draw with the bundled theme and report the substitution.
  /// An exception would mean the app does not start because of a colour.
  ///
  /// Pass [assetPath] — the theme your app was built with — so that a user
  /// without a connection still sees your colors. Without it the fallback is
  /// the package's built-in theme ([ThemeContract.fallback]). Either way
  /// [status] is [ThemeLoadStatus.networkUnavailable].
  ///
  /// Call it before the first frame: replacing colors after a screen is drawn is
  /// a visible jump. Gives up after [timeout].
  static Future<ThemeLoad> fromNetwork(
    Uri url, {
    required DocumentTransport transport,
    AssetBundle? bundle,
    String? assetPath,
    Duration timeout = kThemeFetchTimeout,
  }) async {
    Future<ThemeLoad> fallbackToBundle(String detail) async {
      // Without a path the fallback goes straight to the embedded theme: an invented default key
      // would give the same result, but through an asset read error.
      final bundled = assetPath == null
          ? ThemeLoad(contract: ThemeContract.fallback(), status: ThemeLoadStatus.ok)
          : await fromBundle(bundle: bundle, assetPath: assetPath);
      /*
       * The status is the NETWORK one, the theme comes from the bundle. Otherwise "the server is
       * silent" would look like "all is well", since the bundle was read successfully, and the
       * only sign that no fresh theme is on screen would disappear.
       */
      return ThemeLoad(
        contract: bundled.contract,
        status: ThemeLoadStatus.networkUnavailable,
        detail: detail,
      );
    }

    DocumentResponse response;
    try {
      response = await transport.fetch(url).timeout(timeout);
    } on DocumentTooLargeException catch (error) {
      return _fallback(ThemeLoadStatus.malformed, '$url: the answer is not a theme: $error');
    } on Object catch (error) {
      return fallbackToBundle('$url did not answer: $error');
    }

    if (response.statusCode != 200) {
      // A 404 here is the normal state "no theme published yet", not a fault: the app is drawn
      // with what it was built with.
      return fallbackToBundle('$url answered ${response.statusCode}');
    }

    final parsed = parse(response.body);
    /*
     * Garbage from the network does NOT replace the bundled theme. Reading it halfway would draw
     * part of the screen in foreign colours, and `parse` returns the fallback anyway, but with its
     * OWN status (`malformed`), which is truer than "the network did not answer".
     */
    return parsed;
  }

  /// Reads a theme contract from JSON text.
  ///
  /// Synchronous and bundle-free, so the mechanism can be tested outside an app.
  static ThemeLoad parse(String source) {
    Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException catch (error) {
      return _fallback(ThemeLoadStatus.malformed, 'not JSON: ${error.message}');
    } on Object catch (error) {
      return _fallback(ThemeLoadStatus.malformed, 'the body could not be decoded: ${error.runtimeType}');
    }
    return fromJson(raw);
  }

  /// Reads a theme contract from decoded JSON.
  ///
  /// Never throws: whatever is in [raw], the result is a [ThemeLoad]. A body the reader cannot handle is
  /// `malformed` with the built-in theme, so a hostile theme cannot become an exception in the host.
  static ThemeLoad fromJson(Object? raw) {
    try {
      return _read(raw);
    } on Object catch (error) {
      return _fallback(ThemeLoadStatus.malformed, 'the theme contract could not be read: ${error.runtimeType}');
    }
  }

  static ThemeLoad _read(Object? raw) {
    if (raw is! Map) {
      return _fallback(ThemeLoadStatus.malformed, 'the theme contract is not a JSON object');
    }

    // The values sit in the envelope under `contract`. A bare payload is accepted too: the bundled
    // artifact is always in an envelope, but a theme the host receives over the network may arrive
    // as the payload alone; the envelope exists for `x-schema`, not for delivery.
    final envelope = raw[kContractKey];
    final body = envelope is Map ? envelope : raw;

    // The version is duplicated in the envelope: `x-themeContractVersion` for people next to the
    // other `x-*` keys, and `contract.themeContractVersion` as the field required by `x-schema`.
    // The field is read; the `x-` key is the spare.
    final version =
        body['themeContractVersion'] as String? ?? raw['x-themeContractVersion'] as String?;
    final verdict = checkContractVersion(version, readerVersion: kSupportedThemeContractVersion);
    if (!verdict.canRender) {
      return _fallback(
        // No version at all is a broken artifact, not a foreign major. The difference is not
        // cosmetic: the first means "the sync broke", the second "the app fell behind", and the
        // host may react differently.
        verdict == VersionVerdict.unparsable
            ? ThemeLoadStatus.malformed
            : ThemeLoadStatus.incompatibleVersion,
        'theme contract "${version ?? '<none>'}" against $kSupportedThemeContractVersion: '
        '${verdict.name}',
      );
    }

    final contract = _parseContract(body, version: version);
    if (contract == null) {
      return _fallback(ThemeLoadStatus.malformed, 'the contract has no usable theme');
    }
    return ThemeLoad(contract: contract, status: ThemeLoadStatus.ok);
  }

  static ThemeLoad _fallback(ThemeLoadStatus status, String detail) {
    if (kDebugMode) {
      debugPrint('[hotlayout] theme not read ($detail) → built-in fallback theme');
    }
    return ThemeLoad(contract: ThemeContract.fallback(), status: status, detail: detail);
  }

  @override
  String toString() =>
      'ThemeLoad(${contract.version}, $status${detail == null ? '' : ': $detail'})';
}

/// `null` if there are no usable themes at all, in which case the caller takes the fallback.
///
/// One broken theme out of three does not sink the contract: the same rule as for one broken
/// screen in a document.
ThemeContract? _parseContract(Map<Object?, Object?> raw, {String? version}) {
  final rawThemes = raw['themes'];
  if (rawThemes is! Map) return null;

  final themes = <String, RenderTheme>{};
  for (final entry in rawThemes.entries) {
    final id = entry.key;
    if (id is! String || id.isEmpty || isForbiddenKey(id) || entry.value is! Map) {
      if (kDebugMode) debugPrint('[hotlayout] theme "${entry.key}" is unusable, skipped');
      continue;
    }
    final theme = RenderTheme.fromJson(entry.value);
    // A theme without `roles` (or without a group, or without a single role) is USABLE here:
    // `missingRole: 'render-neutral'` says a role the theme does not describe is drawn neutrally,
    // with no background or border and root-colour text. The neutral look is not invented: the
    // contract describes it (`x-style.roles.neutral`).
    themes[id] = theme;
  }
  if (themes.isEmpty) return null;

  return ThemeContract(
    version: version ?? raw['themeContractVersion'] as String? ?? '',
    defaultThemeId: raw['defaultThemeId'] as String? ?? themes.keys.first,
    themes: Map.unmodifiable(themes),
  );
}
