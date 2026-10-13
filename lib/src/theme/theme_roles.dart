/// Parts of a theme: a font family, and the colours of a semantic role.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The font family of one role: a primary name plus a list of fallbacks.
///
/// The list arrives from the contract as is. The reader does not "fix" it for the platform, even
/// when some names are web-specific (`system-ui`, `-apple-system`): replacing them silently would
/// draw with something other than what the theme said. The engine simply skips a name it does
/// not know.
@immutable
final class ThemeFontFamily {
  const ThemeFontFamily({required this.primary, required this.fallback});

  final String primary;
  final List<String> fallback;

  @override
  bool operator ==(Object other) =>
      other is ThemeFontFamily && other.primary == primary && listEquals(other.fallback, fallback);

  @override
  int get hashCode => Object.hash(primary, Object.hashAll(fallback));

  @override
  String toString() => 'ThemeFontFamily($primary, fallback: $fallback)';
}

/// The colours of one semantic role, as **palette token names**, not hex.
///
/// The map ("the `warning` tone is the `warning` background with `onPrimary` text") is carried by
/// the theme, so it is defined in one place rather than hand-written separately in each reader.
///
/// The values are token names: a rebrand changes the palette and the roles follow it. Hex values
/// here would reintroduce two parallel colour vocabularies.
///
/// [background] and [border] are **optional, which is not the same as a "transparent colour"**:
/// in Flutter "no fill" means a different widget (`TextButton` instead of `FilledButton`), not a
/// fill of colour `transparent`. CSS has no such difference, so the builder flattens it to
/// `transparent`; on the Dart side it must not be flattened. [foreground] is required: text has
/// to be drawn in some colour.
@immutable
final class ThemeRole {
  const ThemeRole({required this.foreground, this.background, this.border});

  final String? background;
  final String foreground;
  final String? border;

  @override
  bool operator ==(Object other) =>
      other is ThemeRole &&
      other.background == background &&
      other.foreground == foreground &&
      other.border == border;

  @override
  int get hashCode => Object.hash(background, foreground, border);

  @override
  String toString() =>
      'ThemeRole(bg: $background, fg: $foreground, border: $border)';
}

/// The same role resolved to the colours of a specific theme.
///
/// A `null` reaches the renderer as `null`; that is exactly why the type is separate:
/// substituting a "transparent" colour here would silently lose information.
@immutable
final class RoleColors {
  const RoleColors({required this.foreground, this.background, this.border});

  final Color? background;
  final Color foreground;
  final Color? border;

  @override
  bool operator ==(Object other) =>
      other is RoleColors &&
      other.background == background &&
      other.foreground == foreground &&
      other.border == border;

  @override
  int get hashCode => Object.hash(background, foreground, border);

  @override
  String toString() => 'RoleColors(bg: $background, fg: $foreground, border: $border)';
}
