/// How tests locate a contract icon.
///
/// Before 9.3.0 an icon was a Material glyph and tests found it with `find.byIcon`.
/// Now the drawing is contract data and the widget is `IconGlyph` carrying the
/// set NAME: we search by name, i.e. by what the document said, not by what draws it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';

export 'package:hotlayout_flutter/src/render/icon_glyph.dart' show IconGlyph, IconGlyphPainter, kAppBarBackGlyphKey;

/// Drawings of the icon with the given name.
Finder findIcon(IconToken icon) =>
    find.byWidgetPredicate((widget) => widget is IconGlyph && identical(widget.icon, icon), description: 'IconGlyph($icon)');

/// The top bar's back arrow (`chevron`, rotated by a half turn).
final Finder findAppBarBack = find.byKey(kAppBarBackGlyphKey);

/// The colour the single icon found is drawn in.
Color iconColorOf(WidgetTester tester, Finder finder) => tester.widget<IconGlyph>(finder).color;
