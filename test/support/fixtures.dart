import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/document_source.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

/// ISO 8601 string for LOCAL time [local] with the machine's zone offset:
/// `2026-10-31T21:59:59+02:00`.
///
/// Why: Dart cannot override the time zone, so date tests compare text literally
/// at an instant that shows the same wall-clock reading in the machine's zone. Before
/// the 9.4.0 clarification this was a string WITHOUT a zone, which `DateTime.parse` read
/// as local time; such a string is now "not a date" under the contract
/// (`dateValueForm`), and the same intent is written with an offset.
String localIso(DateTime local) {
  assert(!local.isUtc);
  String two(int n) => n.toString().padLeft(2, '0');
  final offset = local.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}'
      'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
      '${offset.isNegative ? '-' : '+'}${two(minutes ~/ 60)}:${two(minutes % 60)}';
}

const List<String> fixtureIds = [
  'reward-catalog-screens',
  'minimal-screen',
  'task-progress-screen',
  'tasks-flow-screens',
  'full-catalog-screen',
  'max-depth-screen',
  'localized-promo',
  // 9.0.0: the first fixture with its OWN theme — see [fixtureThemeFiles].
  'rewards-showcase-screens',
  // 9.3.0: the whole contract icon set — generated, 332 names.
  'icon-library-screens',
  // 9.4.0: template text, numbers, money, days and plurals in three languages.
  'template-text-screens',
  // 9.5.0: buttons with an icon in three sizes, icon buttons, badges, the row slot.
  'buttons-chips-screens',
  // 9.6.0: rich text — parts of a string with their own style, the template word.
  'rich-text-screens',
  // 9.7.0: bar and ring — thickness, track, gradient, diameter from the box.
  'progress-screens',
  // 9.8.0: action catalogue, analytics event, parameter from data, carryRecord.
  'actions-screens',
  // 9.9.0: own image aspect ratio, app bar actions, centred window, status bar
  // icon request; three languages (en / uk / ar).
  'media-chrome-screens',
  // 9.10.0: offset overlays in a stack and pull in the flow; three languages (en / uk / ar).
  'offset-screens',
  // 9.11.0: challenge carousel from data, a row of badges and step milestones; three languages (en / uk / ar).
  'carousel-steps-screens',
  // 9.12.0: bottom zone — a nav bar of three sections, a block pinned to the bottom
  // and a sheet with two pinned buttons; three languages (en / uk / ar).
  'bottom-zone-screens',
  // 9.13.0: input fields — a profile form and settings, three languages (en / uk / ar).
  'inputs-screens',
  // 9.14.0: a three-step survey and a thank-you screen — "required", a disabled button,
  // a number field, a group choice write; three languages (en / uk / ar).
  'survey-screens',
  // 9.15.0: child alignment on both axes — centred on the screen, column and container
  // in both directions, a body at the end between the app bar and a pinned button.
  'alignment-screens',
  // 9.16.0: app bar from a mock-up — a node in the leading zone, title from the start, two actions,
  // a long button clamped to half, a conditional node, own glyph size.
  'app-bar-screens',
  // 9.17.0: text emphasis, bulleted and numbered lists, "old price", a card with
  // inherited italic and line, a large ring with a large label; en and `ar-EG`.
  'text-emphasis-screens',
  // 9.18.0: width adaptivity — home at 393 / 768 / 1280 and the `lab` stand: grid
  // 2 → 3 → 4, "phone only" and "wide only" blocks, style by class, column → row
  // 2 : 1; en, uk, ar.
  'adaptive-screens',
  // 9.19.0: free composition — a card with an icon tile, a pressable card, a list row in a card,
  // a button inside a pressable card, a sheet with a card; en and uk.
  'composition-screens',
  // 9.19.0: money as money — currency sign, sign of the number, the parts of an amount (smaller
  // cents), isolation in Arabic; en, uk, ar.
  'money-screens',
  // 9.19.0: the app bar over a hero — the body from the top edge of the screen, the top safe inset;
  // en, uk, ar.
  'hero-screens',
  // 9.19.0: choice controls and the write action: a segment, chips, cards, a scale.
  'choice-controls-screens',
  // 9.19.0: parts of a list row and of a text field: an operations card and a form.
  'parts-screens',
  // 9.19.0: description of a picture, icon from data, parts of a date, "none" in a width layer.
  'alt-icon-date-screens',
  // 9.20.0: floating and breathing nodes, glass on a card, a sheet over a blurred screen; en and uk.
  'motion-blur-screens',
  // 9.21.0: a balance that counts, a ring and bars that grow, a countdown that ticks, an app bar that turns
  // solid on scroll; en and uk.
  'value-countdown-screens',
  // 9.22.0: a floating bar with a dot, "swipe to confirm", a dashed border; en and uk.
  'float-nav-swipe-screens',
  // 9.23.0: a filtered list, a gradient on the letters, a compact number; en and uk.
  'filter-gradient-compact-screens',
  // 9.24.0: a value that grows when shown, a swipe that stays busy, a dot that flashes, nodes pinned to the top; en and uk.
  'appear-swipe-dot-screens',
  // 9.25.0: glowing scales, steps that fill smoothly, a shadow of the colour of the card, a press that sinks.
  'glow-press-screens',
];

/// We read fixtures from disk rather than through rootBundle: the test does not depend on
/// how the asset bundle is built.
String readFixture(String id) =>
    File('assets/contract/fixtures/$id.json').readAsStringSync();

/// A fixture as a document SOURCE — an embedded copy for network tests.
///
/// Reads from disk: the package declares no assets (they would land in every
/// consumer's bundle), so `rootBundle` has no fixtures in its tests. The bundle is new on
/// every call — see [diskAssetBundle].
BundledDocumentSource diskFixtureSource(String id, {String? title}) => BundledDocumentSource(
  title: title ?? id,
  assetPath: 'assets/contract/fixtures/$id.json',
  bundle: diskAssetBundle(),
);

UiDocument loadFixture(String id) => UiDocument.fromJsonString(readFixture(id));

/// A fixture that has its OWN THEME: the file lies in `fixtures/themes/` — one level
/// down, so that the fixtures folder stays a folder of DOCUMENTS.
///
/// Mirror of the builder's `FIXTURE_THEMES` (`scripts/fixture-themes.ts`): while there were
/// exactly as many tokens as the schema knows, the question "which theme to draw a
/// fixture with" did not exist; since a theme declares its own names, a document with
/// `color: 'brandText'` reads only against a theme that declares that name.
const Map<String, String> fixtureThemeFiles = {
  'rewards-showcase-screens': 'themes/rewards-showcase-theme',
};

/// The fixture's theme contract; for the rest, the built-in snapshot.
ThemeContract fixtureThemeContract(String id) {
  final file = fixtureThemeFiles[id];
  if (file == null) return ThemeContract.fallback();
  final load = ThemeLoad.parse(File('assets/contract/fixtures/$file.json').readAsStringSync());
  expect(load.status, ThemeLoadStatus.ok, reason: 'fixture theme $id: ${load.detail}');
  return load.contract;
}

/// A fixture's theme: by `themeId` or, without it, its default theme.
RenderTheme fixtureTheme(String id, {String? themeId}) =>
    fixtureThemeContract(id).themeById(themeId);

/// The theme artifact — from disk, for the same reason as the fixtures.
String readThemeContract() =>
    File('assets/contract/theme.json').readAsStringSync();

/// A bundle that reads assets from disk — **new for every test**.
///
/// Needed where the whole app is brought up, for exactly one reason:
/// `rootBundle` caches not bytes but a **Future**, and every such Future stays forever
/// bound to the zone it was created in. The second `testWidgets` in a file
/// gets from the cache a Future from the FIRST test's zone — whose fake time no longer
/// ticks, so an `await` on it never completes. That is why
/// `demo_host_test.dart` and `demo_background_test.dart` live in separate files
/// with one test each (the loading indicator was a symptom there,
/// not the cause).
///
/// A fresh instance per test removes the shared cache, and a synchronous read from
/// disk removes the need for real asynchronous I/O.
AssetBundle diskAssetBundle() => _DiskAssetBundle();

class _DiskAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

Future<void> pumpDocument(
  WidgetTester tester,
  UiDocument doc, {
  Map<String, Object?> data = const {},
  SduiActionCallback? onAction,
  SduiRecordActionCallback? onRecordAction,
  RenderTheme? theme,
  String? entry,
  String? locale,
  DateTime? now,
  ValueChanged<ScreenEntry>? onScreenChanged,
  SduiTrackCallback? onTrack,
  SduiHapticCallback? onHaptic,
  SduiScreenShownCallback? onScreenShown,
  ScreenScopeResolver? scopeFor,
  ScreenFlowController? controller,

  /// The system "disable animations" setting — what a person turns on in phone
  /// settings when motion physically bothers them. Motion tests must be able to check
  /// both answers, not only the prettier one.
  bool disableAnimations = false,

  /// The platform's bottom safe inset (`MediaQuery.viewPadding`), which the reader
  /// adds under the bottom zone (9.12.0). Zero — a host that accounted for it itself.
  double safeBottom = 0,

  /// The platform's top safe inset (`MediaQuery.viewPadding.top`), which the reader adds above the
  /// body or inside the app bar (9.19.0). Zero -- a host that accounted for it itself.
  double safeTop = 0,

  /// What an input field writes (9.13.0): a path and a string or boolean.
  SduiValueWrite? onWrite,

  /// The host's `autofill` parameter (9.13.0).
  bool autofill = true,

  /// On-screen keyboard height (`MediaQuery.viewInsets.bottom`).
  double keyboard = 0,

  /// Whether the host's `Scaffold` shrinks the body under the keyboard. `false` — the host does
  /// nothing, and the reader sees the keyboard in its own `MediaQuery`.
  bool resizeToAvoidBottomInset = false,

  /// How one screen replaces another (the host's `transitions`).
  HotlayoutTransitions transitions = HotlayoutTransitions.platform,

  /// The platform the host's theme says it runs on; the test platform when `null`.
  TargetPlatform? platform,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: platform == null ? null : ThemeData(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          viewPadding: EdgeInsets.only(top: safeTop, bottom: safeBottom),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          body: renderDocument(
            doc,
            theme: theme ?? RenderTheme.fallback(),
            data: data,
            entry: entry,
            locale: locale,
            now: now,
            onAction: onAction,
            onRecordAction: onRecordAction,
            // ignore: deprecated_member_use_from_same_package
            onScreenChanged: onScreenChanged,
            onTrack: onTrack,
            onHaptic: onHaptic,
            onScreenShown: onScreenShown,
            scopeFor: scopeFor,
            onWrite: onWrite,
            autofill: autofill,
            controller: controller,
            transitions: transitions,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A FOREIGN MAJOR — one greater than the one the renderer understands.
///
/// Computed rather than written as a number: a literal ("8.0.0", then "9.0.0") used
/// to stand here and twice stopped being foreign on the day the renderer itself moved
/// to that major — the test silently began checking ITS OWN document.
String get foreignMajorVersion =>
    '${int.parse(UiDocument.supportedSchemaVersion.split('.').first) + 1}.0.0';

/// The previous major — a document this reader NO LONGER draws.
String get previousMajorVersion =>
    '${int.parse(UiDocument.supportedSchemaVersion.split('.').first) - 1}.20.0';

/// A newer MINOR of the same major: readable, because a minor only adds optional things.
String get futureMinorVersion => '${UiDocument.supportedSchemaVersion.split('.').first}.99.0';

/// A document around the given children — so a one-prop test does not drag in
/// a whole fixture.
UiDocument docWith(
  List<Map<String, Object?>> children, {
  String schemaVersion = UiDocument.supportedSchemaVersion,
  Map<String, Object?>? background,
}) => UiDocument.fromJson({
  'schemaVersion': schemaVersion,
  'documentId': 'inline',
  'name': 'Інлайн-документ',
  'initialScreenId': 'inline',
  'screens': [screenEntry('inline', children, background: background)],
});

/// A document whose screen has NO STYLE — no background, no padding.
///
/// Separate from [docWith], which writes the usual screen look explicitly: this one
/// checks precisely that the reader has no hidden defaults.
abstract final class UiDocumentBuilder {
  static UiDocument bare(
    List<Map<String, Object?>> children, {
    Map<String, Object?>? style,
    List<Map<String, Object?>>? styleWhen,
    Object? gap = 'none',
  }) =>
      UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'bare',
        'name': 'Екран без стилю',
        'initialScreenId': 'bare',
        'screens': [
          {
            'screenId': 'bare',
            'name': 'bare',
            'root': {
              'id': 'root',
              'type': 'Screen',
              // The gap between root children is a `props` field with default `sm`; here
              // it defaults to `none`, so coordinates count from zero.
              'props': {'gap': ?gap},
              'style': ?style,
              'styleWhen': ?styleWhen,
              'children': children,
            },
          },
        ],
      });
}

/// Background colour in the 7.0.0 union form — the most common field shape in tests.
Map<String, Object?> colorBackground([String token = 'surface']) => {
  'kind': 'color',
  'color': token,
};

/// Background gradient in the 7.0.0 union form.
Map<String, Object?> gradientBackground([String token = 'brandBackdrop']) => {
  'kind': 'gradient',
  'gradient': token,
};

/// One document screen: `{ screenId, name, root }`.
Map<String, Object?> screenEntry(
  String screenId,
  List<Map<String, Object?>> children, {
  String? name,
  Map<String, Object?>? background,
  String? presentation,
  Object? modalPlacement,
  Object? statusBarIcons,
}) => {
  'screenId': screenId,
  'name': name ?? screenId,
  // The presentation mode (8.12.0) is written only when present: "as usual" is
  // the absence of the field, and a document in tests must look the same.
  'presentation': ?presentation,
  // 9.9.0: optional screen-entry fields; written only when named.
  'modalPlacement': ?modalPlacement,
  'statusBarIcons': ?statusBarIcons,
  'root': {
    'id': 'root',
    'type': 'Screen',
    // 9.0.0: the screen's `props` are empty, the look lives in `style`. The usual look
    // (`surface`, `md`) is written EXPLICITLY, as the builder writes it: there are no
    // hidden defaults in the reader.
    // The gap between root children (`Screen.props.gap`) is `none` here: tests
    // measure distances between nodes, and the screen gap is not their subject.
    'props': {'gap': 'none'},
    'style': {'background': background ?? colorBackground(), 'padding': 'md'},
    'children': children,
  },
};

/// A document of several screens — for navigation tests.
UiDocument docWithScreens(
  List<Map<String, Object?>> screens, {
  required String initialScreenId,
  String documentId = 'flow',
}) => UiDocument.fromJson({
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': documentId,
  'name': 'Потік екранів',
  'initialScreenId': initialScreenId,
  'screens': screens,
});

/// A text node with minimally complete props.
///
/// [style] is the node style (9.0.0): the text's colour and font live there, not in
/// `props`. Without it the text is drawn inherited — at the root that is `onSurface`
/// and `bodyM`.
Map<String, Object?> textNode(
  String value, {
  String id = 'txt',
  Map<String, Object?> extra = const {},
  Map<String, Object?>? style,
  Object? visibleIf,
}) {
  // Migration guard: before 9.0.0 colour and font were passed here through `extra`, and
  // such a call silently does nothing after the move — the test stays
  // green and stops checking anything.
  assert(
    !extra.containsKey('color') && !extra.containsKey('typography'),
    'text colour and font live in `style` since 9.0.0, not in props',
  );
  return {
    'id': id,
    'type': 'Text',
    'props': {
      'content': {'kind': 'literal', 'value': value},
      'align': 'start',
      'overflow': 'ellipsis',
      ...extra,
    },
    'style': ?style,
    'visibleIf': ?visibleIf,
  };
}

/// A button with an arbitrary action — navigation in 5.0.0 is expressed by it.
Map<String, Object?> buttonNode(
  String label, {
  required Map<String, Object?> action,
  String id = 'btn',
  String variant = 'primary',
}) => {
  'id': id,
  'type': 'Button',
  'props': {
    'label': {'kind': 'literal', 'value': label},
    'variant': variant,
    'action': action,
    'fullWidth': true,
  },
};

/// Badge: the tone is document semantics, tone colours since 2.0.0 come from the theme.
Map<String, Object?> badgeNode(
  String label, {
  String tone = 'neutral',
  String id = 'bdg',
}) => {
  'id': id,
  'type': 'Badge',
  'props': {
    'label': {'kind': 'literal', 'value': label},
    'tone': tone,
  },
};

/// 6.0.0 list row: both edges are unions, both required in the schema.
Map<String, Object?> listTileNode(
  String title, {
  String id = 'tile',
  Map<String, Object?> leading = const {'kind': 'none'},
  Map<String, Object?> trailing = const {'kind': 'none'},
  String? subtitle,
  Map<String, Object?>? action,
  Object? visibleIf,
}) => {
  'id': id,
  'type': 'ListTile',
  'props': {
    'leading': leading,
    'title': {'kind': 'literal', 'value': title},
    if (subtitle != null) 'subtitle': {'kind': 'literal', 'value': subtitle},
    'trailing': trailing,
    // 6.1.0: the field is optional, so in the document it is either absent or present.
    'action': ?action,
  },
  'visibleIf': ?visibleIf,
};

/// Option row: `trailing.radio` names the option, the choice stays with the group.
Map<String, Object?> optionNode(
  String title, {
  required String optionValue,
  String? id,
  Map<String, Object?> leading = const {'kind': 'none'},
  String? subtitle,
  Map<String, Object?>? action,
}) => listTileNode(
  title,
  id: id ?? 'opt-$optionValue',
  leading: leading,
  subtitle: subtitle,
  action: action,
  trailing: {'kind': 'radio', 'optionValue': optionValue},
);

/// Choice group. `value` is bindable, so we accept a ready-made form.
Map<String, Object?> choiceGroupNode(
  List<Map<String, Object?>> children, {
  String id = 'group',
  Object value = const {'kind': 'literal', 'value': ''},
  String gap = 'none',
  Object? visibleIf,
}) => {
  'id': id,
  'type': 'ChoiceGroup',
  'props': {'value': value, 'gap': gap},
  'children': children,
  'visibleIf': ?visibleIf,
};

/// The screen's top bar.
///
/// [background] is opaque by default, as it is in most documents; `null`
/// is a bar WITHOUT its own background, and then there is no style in the JSON at all. Since 9.0.0
/// the bar background lives in `style`, like any node's.
Map<String, Object?> appBarNode(
  String title, {
  String id = 'bar',
  String? subtitle,
  bool showBack = true,
  Map<String, Object?>? background = const {
    'kind': 'color',
    'color': 'surface',
  },
}) => {
  'id': id,
  'type': 'AppBar',
  'props': {
    'title': {'kind': 'literal', 'value': title},
    if (subtitle != null) 'subtitle': {'kind': 'literal', 'value': subtitle},
    'showBack': showBack,
  },
  if (background != null) 'style': {'background': background},
};

/// Contract type name for an already parsed node.
String contractType(UiNode node) => switch (node) {
  ScreenNode() => 'Screen',
  AppBarNode() => 'AppBar',
  ColumnNode() => 'Column',
  RowNode() => 'Row',
  ContainerNode() => 'Container',
  GridNode() => 'Grid',
  StackNode() => 'Stack',
  TabsNode() => 'Tabs',
  TabNode() => 'Tab',
  AccordionNode() => 'Accordion',
  ChoiceGroupNode() => 'ChoiceGroup',
  RepeaterNode() => 'Repeater',
  SpacerNode() => 'Spacer',
  DividerNode() => 'Divider',
  TextNode() => 'Text',
  ImageNode() => 'Image',
  IconNode() => 'Icon',
  ButtonNode() => 'Button',
  IconButtonNode() => 'IconButton',
  ListTileNode() => 'ListTile',
  ProgressBarNode() => 'ProgressBar',
  CircularProgressNode() => 'CircularProgress',
  BadgeNode() => 'Badge',
  NavBarNode() => 'NavBar',
  NavItemNode() => 'NavItem',
  TextFieldNode() => 'TextField',
  SwitchNode() => 'Switch',
  CheckboxNode() => 'Checkbox',
  UnknownNode(:final type) => 'Unknown:$type',
};

Iterable<UiNode> flatten(UiNode node) sync* {
  yield node;
  for (final child in node.children) {
    yield* flatten(child);
  }
}

/// All document nodes: since 5.0.0 they must be collected from several screens.
Iterable<UiNode> flattenDocument(UiDocument doc) sync* {
  for (final screen in doc.screens) {
    yield* flatten(screen.root);
  }
}

/// The root of the first (start) screen — where the test does not care about navigation.
UiNode rootOf(UiDocument doc) => doc.initialScreen.root;

/// The raw fixture — when the JSON itself must be checked, not the parsed tree.
Map<String, Object?> jsonFixture(String id) =>
    jsonDecode(readFixture(id)) as Map<String, Object?>;

/// All values of the `background` field present in the raw document, at any
/// depth — since 9.0.0 these are `style.background` and the state backgrounds (`styleWhen`).
/// Raw ones are needed because the model reads an unusable background as absent, so
/// a mismatch with the contract is invisible on the parsed tree.
///
/// Width layers (`styleOn`, 9.18.0) are NOT included here: in the parsed tree of a class the layer
/// replaces the base background, so they cannot be counted together with `style` — for them
/// [rawLayerBackgrounds].
Iterable<Object?> rawBackgrounds(Object? node) sync* {
  if (node is Map) {
    if (node.containsKey('background')) yield node['background'];
    for (final entry in node.entries) {
      if (entry.key == 'styleOn') continue;
      yield* rawBackgrounds(entry.value);
    }
  } else if (node is List) {
    for (final item in node) {
      yield* rawBackgrounds(item);
    }
  }
}

/// Backgrounds in the `styleOn` width layers (9.18.0) — raw, at any depth.
Iterable<Object?> rawLayerBackgrounds(Object? node) sync* {
  if (node is Map) {
    for (final entry in node.entries) {
      if (entry.key == 'styleOn') {
        yield* rawBackgrounds(entry.value);
      } else {
        yield* rawLayerBackgrounds(entry.value);
      }
    }
  } else if (node is List) {
    for (final item in node) {
      yield* rawLayerBackgrounds(item);
    }
  }
}

/// The decoration of the root `Screen` — what is actually drawn under the content.
///
/// Since 9.0.0 the screen background lives in `style`, and a screen WITHOUT a background draws nothing: then
/// there is no `DecoratedBox` at all, and the answer is an empty decoration. So
/// we search only BETWEEN the screen scroll and the flow root (`ScreenFlow`): above that
/// lie decorations set by `MaterialApp`, and they are not ours.
BoxDecoration screenDecoration(WidgetTester tester) => _decorationBetween(
  tester.element(find.byType(SingleChildScrollView).first),
  (widget) => widget is ScreenFlow,
);

/// The top bar's decoration — located by its title, since the bar has no other
/// anchor. An empty decoration (both slots `null`) means a transparent bar.
///
/// We search only INSIDE the bar — up to the screen column, which stretches children to the
/// full width: a decoration above it already belongs to the screen.
BoxDecoration appBarDecoration(WidgetTester tester, String title) => _decorationBetween(
  tester.element(find.text(title)),
  (widget) => widget is ScreenZones || (widget is Column && widget.crossAxisAlignment == CrossAxisAlignment.stretch),
);

/// A badge's decoration by its label — what is actually drawn.
///
/// A badge without background and border (the neutral role) draws no decoration at all, and
/// the answer is then empty. We search up to the nearest column: above that is someone else's.
BoxDecoration badgeDecoration(WidgetTester tester, String label) =>
    _decorationBetween(tester.element(find.text(label)), (widget) => widget is Flex || widget is StretchColumn);

/// Decoration of the BOX of the node that drew this label — the nearest one above it.
///
/// Nodes render without keys, so the text inside serves as the anchor. An empty
/// decoration means "the box draws nothing" — the node has no background, border or
/// shadow style.
BoxDecoration nodeDecoration(WidgetTester tester, String label) =>
    _decorationBetween(tester.element(find.text(label)), (widget) => widget is Flex || widget is StretchColumn);

/// Box padding of a node (`style.padding` together with the border width) — the nearest
/// `Padding` above the label; zero if there is none.
EdgeInsetsGeometry nodePadding(WidgetTester tester, String label) {
  EdgeInsetsGeometry? found;
  tester.element(find.text(label)).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Flex || widget is StretchColumn) return false;
    if (widget is Padding) {
      found = widget.padding;
      return false;
    }
    return true;
  });
  return found ?? EdgeInsets.zero;
}

BoxDecoration _decorationBetween(Element from, bool Function(Widget widget) stop) {
  // One surface is two boxes: the border lies in a FOREGROUND box over the content, the rest in a background box.
  // The nearest box is the border one when there is a border; the next one up completes it.
  BoxDecoration? found;
  var foreground = false;
  var merged = false;
  from.visitAncestorElements((element) {
    final widget = element.widget;
    if (stop(widget)) return false;
    if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      final d = widget.decoration as BoxDecoration;
      if (found == null) {
        found = d;
        foreground = widget.position == DecorationPosition.foreground;
      } else if (foreground && !merged && widget.position == DecorationPosition.background) {
        merged = true;
        found = BoxDecoration(
          color: d.color,
          gradient: d.gradient,
          image: d.image,
          border: found!.border,
          borderRadius: d.borderRadius ?? found!.borderRadius,
          boxShadow: d.boxShadow,
        );
      }
    }
    return true;
  });
  return found ?? const BoxDecoration();
}
