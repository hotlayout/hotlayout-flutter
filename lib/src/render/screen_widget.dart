/// Builds the widget of one screen of a document.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/screen_data.dart';
import '../model/composition_rules.dart' show kReaderParseLimit;
import '../model/localization.dart';
import '../model/record_scope.dart';
import '../model/tokens.dart';
import '../model/ui_document.dart';
import '../theme/render_theme.dart';
import 'carousel.dart';
import 'host_callbacks.dart';
import 'inputs.dart';
import 'labels.dart';
import 'node_renderer.dart';
import 'screen_form.dart';
import 'version_notice.dart';
import 'width_class_scope.dart';

Widget screenWidget(
  ScreenEntry screen, {
  required RenderTheme theme,
  required Map<String, Object?> data,
  required Map<String, String> params,
  required Map<String, Object?>? record,
  required Map<String, Object?> session,
  required ScreenScopeResolver? scopeFor,
  required LocalizedStrings strings,
  required String? locale,
  required DateTime? now,
  required ActionHandler? handler,
  required SduiValueWrite? onWrite,
  required RendererLabels labels,
  bool autofill = true,
  CarouselMemory? memory,
  ScreenPresentationToken? presentation,
}) {
  // A tree deeper than the reader's parse limit is a screen the reader does not draw (`depth.readerAboveParseLimit`):
  // a neutral notice stands in its place, the host's app goes on.
  if (screen.tooDeep) {
    if (kDebugMode) debugPrint('[hotlayout] screen "${screen.screenId}" is deeper than $kReaderParseLimit levels: not drawn');
    return UnavailableNotice(theme: theme, text: labels.screenUnavailable, icon: IconToken.parse('info'));
  }
  // WIDTH CLASS: the box this screen is painted in is measured (the root with its insets), not
  // the window or the device, because the block may sit in a column or in part of a tablet
  // screen. A modal layer measures its own box, since the screen is painted inside it. There is
  // one class per screen. The tree is resolved for the class (`ScreenEntry.rootIn`, cached per
  // screen entry) and then painted as an ordinary document; when the class changes (rotation,
  // split screen) the same tree is repainted with other props, and the field keys and the
  // carousels' memory of the frame stay.
  return WidthClassScope(
    builder: (context, widthClass) {
      final root = screen.rootIn(widthClass);
      // The host's record is the same input as the rest: only the form's own data path keys, no
      // `null` values.
      final screenRecord = safeRecord(record);
      // First the data WITHOUT the scope, which is what the host reads when deciding which entity to
      // supply. Then the same scope goes on top of it as layer 3.
      final base = ScreenData.scoped(document: data, record: screenRecord, session: session);
      final scope = scopeFor?.call((params: params, record: screenRecord, read: base.lookup)) ?? const {};
      // Data layers of THIS screen (without a list item's row record): the screen's form is computed
      // from them, because the form is about the screen, not a node.
      final screenData = ScreenData.scoped(
        document: data,
        record: screenRecord,
        session: session,
        scope: scope,
      );
      final renderer = NodeRenderer(
        theme: theme,
        data: screenData,
        form: ScreenForm(root: root, data: screenData),
        strings: strings,
        locale: locale,
        // READER CLOCK (`readerClock: 'injectable-read-at-render'`). Read ONCE per screen, here, at
        // paint time: all strings of a frame count days from one instant, and the screen does not
        // repaint as time passes; the computed value stands until the next paint.
        now: now ?? DateTime.now(),
        onAction: handler,
        onWrite: onWrite,
        labels: labels,
        carouselMemory: memory,
        shownScreenId: screen.screenId,
      );
      // Root of THIS screen's input fields: the registry for the "next" key and the host's
      // `autofill` parameter. One per screen, so "next" does not jump to the screen under a modal.
      return InputScope(
        autofill: autofill,
        child: renderer.renderRoot(
          root,
          presentation: presentation ?? screen.presentation,
          placement: screen.placement,
          widthClass: widthClass,
        ),
      );
    },
  );
}
