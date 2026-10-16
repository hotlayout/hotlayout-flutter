import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'compatibility.dart';
import 'composition_rules.dart' show exceedsParseLimit;
import 'locale_resolve.dart';
import 'localization.dart';
import 'media_chrome_rules.dart';
import 'motion_rules.dart' show backdropBlurOf;
import 'node.dart';
import 'style_values.dart' show isForbiddenKey;
import 'tokens.dart';
import 'width_class.dart';

/// One screen of a document: `{ screenId, name, root }`.
///
/// A document is the unit of delivery and versioning; a screen is the unit of display and the
/// target of a navigation.
final class ScreenEntry {
  /// Creates a screen. Documents are normally parsed, not built.
  const ScreenEntry({
    required this.screenId,
    required this.name,
    required this.root,
    this.presentation = ScreenPresentationToken.page,
    this.modalPlacement,
    this.statusBarIcons,
    this.backdropBlur,
    this.source,
    this.tooDeep = false,
  });

  /// The tree is deeper than the reader's parse limit ([exceedsParseLimit]): the screen is not drawn, a notice
  /// stands in its place.
  final bool tooDeep;

  /// The id navigation actions refer to.
  final String screenId;
  /// The name a manager gave the screen in the builder. Not shown to users.
  final String name;
  /// The root node of the screen.
  final UiNode root;

  /// Whether the screen replaces the previous one or is laid over it (since 8.12.0).
  ///
  /// Documents older than 8.12.0 have no such field and read as `page`, which is what screens
  /// always did. `modal` names no size: the contract states only what is equally true for every
  /// reader, that the previous screen stays in place and visible beneath it.
  final ScreenPresentationToken presentation;

  /// The placement the document names for a modal screen (`bottom` or
  /// `center`), or `null` when it names none (or names a word this reader does
  /// not know).
  ///
  /// An unknown word and an absent field are both `null` here. The effective placement is
  /// [placement]: a page never reads the field (`modalPlacementOnPage`).
  final ModalPlacement? modalPlacement;

  /// Where the layer lies: the named placement of a modal screen, a sheet
  /// otherwise (`unknownModalPlacement: bottom`). A page never reads the field.
  ModalPlacement get placement => presentation == ScreenPresentationToken.modal
      ? (modalPlacement ?? ModalPlacement.bottom)
      : ModalPlacement.bottom;

  /// The blur of everything under the modal layer of this screen (9.20.0), in logical pixels, or `null` for
  /// none. Read only for a modal screen drawn as a layer: a page has no layer to blur under
  /// (`x-backdropBlur.onPage`).
  final int? backdropBlur;

  /// The status bar icon colour this screen asks the host for (`light` or
  /// `dark`), or `null` when it asks for nothing.
  ///
  /// The reader never touches the system status bar: the request travels to the host in the
  /// screen-shown event (`statusBarIcons: 'handed-to-host-reader-touches-nothing'`).
  final StatusBarIcons? statusBarIcons;

  /// The raw root, kept so the tree can be resolved for a width class.
  /// `null` for a screen built by hand.
  ///
  /// A `null` source means the screen was not built from a document, so `root` is drawn at every
  /// width. A document without width-class fields still has a source, but `adaptive` is false and
  /// no copy of the tree is made.
  final ScreenSource? source;

  /// The tree of this screen as a reader of the given [widthClass] sees it.
  ///
  /// `compact` is `root` (the document base is the phone layout), and a document without
  /// `showOn` / `styleOn` / `propsOn` gives `root` at any width. Otherwise the tree is resolved
  /// ONCE per class and cached for as long as the screen entry lives: new data does not require
  /// re-resolving, while a new document version produces new screen entries.
  UiNode rootIn(WidthClass widthClass) {
    final from = source;
    if (from == null || !from.adaptive || widthClass == WidthClass.compact) return root;
    final cache = _resolved[this] ??= {};
    return cache[widthClass] ??= UiNode.parse(from.root, keys: from.keys, widthClass: widthClass);
  }
}

final Expando<Map<WidthClass, UiNode>> _resolved = Expando('resolved screen trees');

/// What a screen keeps of its JSON to be resolved for a width class.
final class ScreenSource {
  /// Creates the source. Normally made by [UiDocument.fromJson].
  const ScreenSource(this.root, this.keys, {required this.adaptive});

  /// The raw root node.
  final Object? root;

  /// The localization keys the screen was parsed with.
  final LocalizationKeys keys;

  /// Whether the root uses `showOn`, `styleOn` or `propsOn` anywhere.
  final bool adaptive;
}

bool _usesWidthClass(Object? node) {
  if (node is! Map) return false;
  if (node.containsKey('showOn') || node.containsKey('styleOn') || node.containsKey('propsOn')) return true;
  final children = node['children'];
  return children is List && children.any(_usesWidthClass);
}

/// A document: a set of screens built from widgets, as published by the
/// HotLayout builder.
///
/// JSON shape: `{ schemaVersion, documentId, name, initialScreenId, screens }` plus the optional
/// `localization` section (since 7.2.0).
///
/// Parse one with [fromJsonString] or load it through a `DocumentSource`, then
/// draw it with `renderDocument`. Parsing does not fail on unknown widgets,
/// tokens or fields; it fails only when there is no usable screen at all.
final class UiDocument {
  /// Creates a document. Documents are normally parsed, not built.
  const UiDocument({
    required this.schemaVersion,
    required this.documentId,
    required this.name,
    required this.initialScreenId,
    required this.screens,
    this.entryPoints = const {},
    this.localization,
  });

  /// The document contract version this renderer understands.
  ///
  /// It is one operand of the compatibility rule, not an equality check: see [versionVerdict]
  /// and `compatibility.dart`.
  static const String supportedSchemaVersion = kSupportedSchemaVersion;

  /// The contract version the document was built for.
  final String schemaVersion;
  /// The id of the document in its project.
  final String documentId;
  /// The name a manager gave the document in the builder. Not shown to users.
  final String name;
  /// The screen shown first when no entry point is asked for.
  final String initialScreenId;

  /// Public entry-point names and the screens they open. Pass a name as
  /// `entry` to `renderDocument`.
  ///
  /// A `screenId` is local to the document, so entry points give a push, a banner or a link a
  /// stable "document + screen" address. An empty map is the most common case and loses
  /// nothing: such a document opens at its initial screen.
  final Map<String, String> entryPoints;

  /// All screens of the document.
  final List<ScreenEntry> screens;

  /// The languages and translations of the document; `null` for a document
  /// in one language.
  ///
  /// `null` is the most common case, and it is what made the section a minor change: a document
  /// without it is drawn exactly as before.
  final DocumentLocalization? localization;

  /// The languages a user could switch between. Empty when there are fewer
  /// than two: a switch with one item is not a switch.
  List<String> get locales {
    final table = localization;
    if (table == null || table.locales.length < 2) return const [];
    return table.locales;
  }

  /// The translations to draw for [locale]. Needed only with `renderScreen`;
  /// `renderDocument` does this itself.
  ///
  /// An unknown language, the default language and a missing section all give the same result:
  /// an empty table, i.e. the literals.
  LocalizedStrings stringsFor(String? locale) =>
      localization?.stringsFor(locale) ?? LocalizedStrings.none;

  /// The language the document is actually shown in when the host asks for
  /// [requested]: the document's own tag (`ar` for `ar-EG`), or the source
  /// language when nothing matches. `null` for a document without
  /// `localization`.
  ///
  /// With `null` the document names no language; the reader then uses the device language.
  String? shownLocale(String? requested) => localization?.shownLocale(requested);

  /// The full answer for [requested]: the language of the text, of the
  /// formats and of the writing direction (schema 9.1.0).
  ///
  /// A document without localization also answers: it names no language, so the only word on it
  /// is the host's request (`translation` is then `null`).
  LocaleResolution localeResolution(String? requested) =>
      localization?.resolve(requested) ?? resolveLocale(requested, const [], null);

  /// Whether this renderer can read the document.
  VersionVerdict get versionVerdict => checkSchemaVersion(schemaVersion);

  /// Shorthand for `versionVerdict.canRender`.
  bool get isSupportedVersion => versionVerdict.canRender;

  /// The screen with this id, or `null`.
  ScreenEntry? screenById(String id) {
    for (final screen in screens) {
      if (screen.screenId == id) return screen;
    }
    return null;
  }

  /// The screen behind a public entry-point name, or `null`.
  ///
  /// `null` means "no such entry point", which is a normal state, not a failure: a name outlives
  /// the document. It may already be in a push or a banner and come back a week later, after the
  /// document was updated. What to do about it is the contract policy
  /// (`unknownEntryPoint: 'use-initial'`), carried out by [screenForEntry]; this method only
  /// answers whether the name exists.
  ScreenEntry? screenByEntry(String entry) {
    final target = entryPoints[entry];
    return target == null ? null : screenById(target);
  }

  /// The screen to open for [entry]: its target, or the initial screen when
  /// [entry] is `null` or unknown to the document.
  ///
  /// This is the `unknownEntryPoint: 'use-initial'` policy: showing the initial screen beats an
  /// empty window, and the user is not at fault for a stale name.
  ScreenEntry screenForEntry(String? entry) {
    if (entry == null) return initialScreen;

    final target = screenByEntry(entry);
    if (target != null) return target;
    if (kDebugMode) {
      debugPrint('[hotlayout] the document has no entry point "$entry": opening the initial screen');
    }
    return initialScreen;
  }

  /// The screen shown first.
  ///
  /// If `initialScreenId` points nowhere, the first screen is used instead of failing: showing
  /// the wrong screen beats showing none.
  ScreenEntry get initialScreen {
    final target = screenById(initialScreenId);
    if (target != null) return target;
    if (kDebugMode) {
      debugPrint(
        '[hotlayout] initialScreenId "$initialScreenId" matches no screen: '
        'opening the first one ("${screens.first.screenId}")',
      );
    }
    return screens.first;
  }

  /// Parses a document from JSON text.
  ///
  /// Throws a [FormatException] when the text is not JSON or has no usable
  /// screen.
  static UiDocument fromJsonString(String source) => fromJson(jsonDecode(source));

  /// Parses a document from decoded JSON.
  ///
  /// Throws a [FormatException] when there is no usable screen. This is the only place where
  /// parsing may throw, and only when there is nothing to draw: one broken screen out of five
  /// does not sink the document.
  static UiDocument fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('The document is not a JSON object');
    }
    final json = Map<String, Object?>.from(raw);
    final rawScreens = json['screens'];
    final screens = <ScreenEntry>[];
    // Localization is read BEFORE the screens for a reason: with no section, keys are not built at
    // all, so tree parsing costs the same as for a single-language document (no extra strings
    // in memory, no extra concatenation per node).
    final localization = DocumentLocalization.parse(json['localization']);

    if (rawScreens is List) {
      for (final entry in rawScreens) {
        final screen = _parseScreen(entry, localized: localization != null);
        if (screen != null) screens.add(screen);
      }
    }

    if (screens.isEmpty) {
      throw const FormatException('The document has no usable screen');
    }

    return UiDocument(
      schemaVersion: json['schemaVersion'] as String? ?? '',
      documentId: json['documentId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      initialScreenId: json['initialScreenId'] as String? ?? '',
      entryPoints: _parseEntryPoints(json['entryPoints']),
      screens: List.unmodifiable(screens),
      localization: localization,
    );
  }

  /// The entry-point map from raw JSON.
  ///
  /// Pairs of the wrong shape are skipped SILENTLY rather than failing the document: an entry
  /// point is addressing, not content, and a document with one broken entry is better opened at
  /// its initial screen than not opened at all. The builder never emits such a document, but the
  /// document arrives from the network.
  static Map<String, String> _parseEntryPoints(Object? raw) {
    if (raw is! Map) return const {};

    final entries = <String, String>{};
    for (final entry in raw.entries) {
      final name = entry.key;
      final target = entry.value;
      if (name is String && name.isNotEmpty && !isForbiddenKey(name) && target is String && target.isNotEmpty) {
        entries[name] = target;
      }
    }
    return entries;
  }

  static ScreenEntry? _parseScreen(Object? raw, {required bool localized}) {
    if (raw is! Map || raw['root'] is! Map) {
      if (kDebugMode) debugPrint('[hotlayout] a screen without a root, skipped');
      return null;
    }
    final json = Map<String, Object?>.from(raw);
    final screenId = json['screenId'] as String? ?? '';
    final keys = localized ? LocalizationKeys(screenId) : LocalizationKeys.off;
    return ScreenEntry(
      screenId: screenId,
      name: json['name'] as String? ?? '',
      root: UiNode.parse(json['root'], keys: keys),
      source: ScreenSource(json['root'], keys, adaptive: _usesWidthClass(json['root'])),
      tooDeep: exceedsParseLimit(json['root']),
      presentation: ScreenPresentationToken.parse(json['presentation']),
      modalPlacement: ModalPlacement.tryParse(json['modalPlacement']),
      statusBarIcons: StatusBarIcons.of(json['statusBarIcons']),
      backdropBlur: backdropBlurOf(json['backdropBlur']),
    );
  }
}
