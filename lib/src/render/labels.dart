/// The few words the renderer itself puts on screen.
///
/// Everything else a person reads comes from the document. These four do not:
/// the document cannot carry the text of a notice shown precisely when the
/// document is unreadable, and the back arrow of an `AppBar` has no label
/// field in the contract. The defaults are English; a host that ships in
/// other languages passes its own, in the language its app is shown in.
library;

import 'package:flutter/foundation.dart';

/// Texts of the renderer's own surfaces. Pass to `renderDocument` or
/// `renderScreen` as `labels`.
@immutable
final class RendererLabels {
  /// English defaults. Override any subset.
  const RendererLabels({
    this.back = 'Back',
    this.imageUnavailable = 'Image unavailable',
    this.updateRequired = 'Update the app to see this screen.',
    this.screenUnavailable = 'This screen is not available right now.',
  });

  /// Accessibility label of the back arrow in an `AppBar`. Never drawn.
  final String back;

  /// Caption under the placeholder of an image that failed to load.
  final String imageUnavailable;

  // Two texts because there are two cases: telling the user to "update the app" for an older
  // document would send them to do something that leaves them looking at the same notice.
  // Defaults are the same words as in `@hotlayout/react`.
  /// Shown instead of a document whose major contract version is **newer**
  /// than the renderer's (`VersionVerdict.newerMajor`): the one case in which
  /// the user can do something.
  final String updateRequired;

  /// Shown instead of a document the user can do nothing about: its major
  /// contract version is **older** than the renderer's
  /// (`VersionVerdict.olderMajor` — it has to be republished from the
  /// builder), or its `schemaVersion` cannot be read
  /// (`VersionVerdict.unparsable`). Neutral on purpose: no advice to update.
  /// The reason and the versions go to the debug log.
  final String screenUnavailable;
}
