/// What the reader decided on its own and the host may want to know about.
library;

import 'package:flutter/foundation.dart' show immutable;

/// Something the renderer ignored, replaced or refused on its own.
///
/// A document and a theme come from a network, so the reader never trusts their shape: whatever it
/// cannot use is skipped, replaced by a default or not drawn, and the screen goes on. The reader says
/// so through `onReport` of `renderDocument` and `renderScreen`, so the host sees it in a release
/// build too (a log line is printed in debug builds only).
///
/// A report is delivered once per cause for the life of one screen widget: a rebuild does not repeat
/// it. At most 50 distinct reports are delivered over that life, so a corrupt document cannot flood
/// the host's log. The report never carries the document's data values.
@immutable
sealed class HotlayoutReport {
  const HotlayoutReport();

  /// The kind in the words shared with the other readers of the contract:
  /// `ignored-input`, `theme-fallback`, `unknown-theme-id`, `invalid-theme-values`,
  /// `incompatible-document`, `newer-minor-document`, `unknown-entry`.
  String get kind;

  /// The report in words, English, for logs.
  String get message;

  @override
  bool operator ==(Object other) => other is HotlayoutReport && other.kind == kind && other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'HotlayoutReport($kind: $message)';
}

/// A part of the document, of the bound data or of a request to the host was ignored because it
/// does not have the shape the contract promises: a node of an unknown type, a token the theme does
/// not have, a picture address the image policy refused, a write path the document had no right to
/// name, a list cut by the budget. The rest of the screen is drawn.
final class IgnoredInputReport extends HotlayoutReport {
  const IgnoredInputReport({required this.where, required this.reason});

  /// Where: `node "hero"`, `screen "main"`, `picture`, `write path`.
  final String where;

  /// What was done instead.
  final String reason;

  @override
  String get kind => 'ignored-input';

  @override
  String get message => '$where: $reason';
}

/// The document was NOT drawn: its schema major differs from the reader's, or the version is garbage.
final class IncompatibleDocumentReport extends HotlayoutReport {
  const IncompatibleDocumentReport({
    required this.documentVersion,
    required this.readerVersion,
    required this.reason,
    required this.documentIsOlder,
  });

  /// The version the document declares.
  final String documentVersion;

  /// The schema version this build reads.
  final String readerVersion;

  /// Why it cannot be read.
  final String reason;

  /// `true`: the layout is older than the reader and must be republished from the builder; the user
  /// can do nothing. `false`: the app must be updated.
  final bool documentIsOlder;

  @override
  String get kind => 'incompatible-document';

  @override
  String get message => 'document $documentVersion was not drawn: $reason (the reader is $readerVersion)';
}

/// The document comes from a newer minor version: it is drawn, unknown widgets and tokens are skipped.
final class NewerMinorDocumentReport extends HotlayoutReport {
  const NewerMinorDocumentReport({required this.documentVersion});

  /// The version the document declares.
  final String documentVersion;

  @override
  String get kind => 'newer-minor-document';

  @override
  String get message => 'document $documentVersion is newer than this reader; unknown widgets and tokens are skipped';
}

/// `entry` names an entry point the document does not have; the initial screen is shown.
final class UnknownEntryReport extends HotlayoutReport {
  const UnknownEntryReport({required this.entry});

  /// The name that was asked for.
  final String entry;

  @override
  String get kind => 'unknown-entry';

  @override
  String get message => 'entry point "$entry" is not in the document; the initial screen is shown';
}

/// The theme could not be read and the built-in theme is used.
final class ThemeFallbackReport extends HotlayoutReport {
  const ThemeFallbackReport({required this.reason});

  /// Why the theme was not used.
  final String reason;

  @override
  String get kind => 'theme-fallback';

  @override
  String get message => 'the built-in theme is used: $reason';
}

/// The theme set does not have the theme that was asked for; another one is used.
final class UnknownThemeIdReport extends HotlayoutReport {
  const UnknownThemeIdReport({required this.themeId, required this.used});

  /// The id that was asked for.
  final String themeId;

  /// The id of the theme that is used instead.
  final String used;

  @override
  String get kind => 'unknown-theme-id';

  @override
  String get message => 'theme "$themeId" is not in the set; "$used" is used';
}

/// Values of the theme that do not have the shape of the theme schema were ignored or replaced.
final class InvalidThemeValuesReport extends HotlayoutReport {
  const InvalidThemeValuesReport({required this.paths});

  /// The places in the theme, for example `colors.brand` or `roles.button.primary`.
  final List<String> paths;

  @override
  String get kind => 'invalid-theme-values';

  @override
  String get message => 'theme values that do not have the shape of the theme schema were ignored: ${paths.join(', ')}';
}

/// The host callback for reports (`onReport`).
typedef HotlayoutReportCallback = void Function(HotlayoutReport report);
