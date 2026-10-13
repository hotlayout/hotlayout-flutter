// What is shown instead of a document this renderer cannot read.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/compatibility.dart';
import '../model/tokens.dart';
import '../model/ui_document.dart';
import '../theme/render_theme.dart';
import 'icon_glyph.dart';
import 'labels.dart';
import 'layout/quiet_flex.dart';

/// A document that cannot be read. Also shown in release builds: an empty screen would look
/// to the user like a broken app rather than an outdated one.
class VersionNotice extends StatelessWidget {
  const VersionNotice({
    super.key,
    required this.theme,
    required this.verdict,
    required this.documentVersion,
    required this.labels,
  });

  /// The theme to draw with.
  final RenderTheme theme;
  final VersionVerdict verdict;
  final String documentVersion;
  final RendererLabels labels;

  @override
  Widget build(BuildContext context) {
    // Versions and the REASON go to the developer, in the log: contract numbers mean nothing to
    // the person holding the phone, and the host supplies their text in its own language
    // ([RendererLabels]). The reason matters more than the numbers: "update the app" and
    // "republish the document" are different actions for different people.
    if (kDebugMode) {
      const reader = UiDocument.supportedSchemaVersion;
      debugPrint(switch (verdict) {
        VersionVerdict.newerMajor =>
          '[hotlayout] document schema $documentVersion is a newer major than this renderer '
              'reads ($reader): update the hotlayout_flutter package → "update the app" notice '
              'instead of the screen',
        VersionVerdict.olderMajor =>
          '[hotlayout] document schema $documentVersion is an older major than this renderer '
              'reads ($reader): updating the app will not help, the document has to be '
              'republished from the builder → neutral notice instead of the screen',
        _ =>
          '[hotlayout] document schema "$documentVersion" is not a version (expected '
              'major.minor.patch; this renderer reads $reader) → neutral notice instead of the '
              'screen',
      });
    }
    // "Update" is said only where updating helps. An older major version and an unreadable
    // version get neutral text and a neutral icon.
    final updatable = verdict == VersionVerdict.newerMajor;
    final text = updatable ? labels.updateRequired : labels.screenUnavailable;
    return UnavailableNotice(theme: theme, text: text, icon: IconToken.parse(updatable ? 'download' : 'info'));
  }
}

/// A neutral notice that fills the place of what cannot be drawn: an icon of the set and one line of the host's own
/// words.
class UnavailableNotice extends StatelessWidget {
  const UnavailableNotice({super.key, required this.theme, required this.text, required this.icon});

  final RenderTheme theme;
  final String text;
  final IconToken icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: theme.color(ColorToken.surface),
    child: Center(
      child: Padding(
        padding: theme.padding(SpacingToken.lg),
        child: QuietColumn(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A drawing from the contract's icon set, not a Material glyph: a host without
            // `uses-material-design` would show a square.
            IconGlyph(icon, color: theme.color(ColorToken.muted), size: theme.iconSize(IconSizeToken.lg)),
            SizedBox(height: theme.space(SpacingToken.sm)),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.text(TypographyToken.bodyM).copyWith(color: theme.color(ColorToken.onSurface)),
            ),
          ],
        ),
      ),
    ),
  );
}
