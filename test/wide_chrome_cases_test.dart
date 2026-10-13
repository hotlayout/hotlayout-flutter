/// WIDE PLACE (schema 9.18.0, step 2): navigation bar at the top, sheet as a centered
/// window, content width class of the layer taken from its own box.
///
/// The tests read the table itself (`assets/contract/fixtures/adaptive/adaptive-cases.json`,
/// a copy of `contract/fixtures/adaptive/adaptive-cases.json`, 176 new rows in thirteen groups
/// on top of the 231 rows of step 1) and run it twice: through the reader formula
/// (`wide_chrome_rules.dart`) and through a REAL widget.
///
///  * `chromeCases` (35) - who stands where: formula and real screen (where the item is drawn);
///  * `wideNavItemCases` (7), `wideNavHeightCases` (3) - item width and height;
///  * `wideAppBarCases` (23), `wideNavBarCases` (7) - items in the app bar and in its own strip.
///    The formula follows the table numbers exactly; the widget follows what it measured itself
///    (labels, title, actions), because the test font (Ahem) dictates text width, not the row numbers;
///  * `wideZoneCases` (27) - screen zones: all 24 combinations of app bar x nav bar x pinned x class;
///  * `wideModalCases` (14), `wideModalRadiusCases` (9) - window-sheet layer: formula,
///    real flow (layer rectangle, layer CONTENT class, body scroll), corner radius;
///  * `wideSectionCases` (10) - sections with different `widePlacement`: the reader does not crash and draws
///    each screen by its own field;
///  * `wideRuleCases` (21) - data blocks `x-style.layout.wideNav` / `wideModal`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/wide_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/width_class.dart';
import 'package:hotlayout_flutter/src/render/app_bar_layout.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';
import 'package:hotlayout_flutter/src/render/wide_nav_group.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = (json.decode(File('assets/contract/fixtures/adaptive/adaptive-cases.json').readAsStringSync()) as Map)
    .cast<String, Object?>();
final _Json _schema = (json.decode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
    .cast<String, Object?>();

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();
_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
List<Object?> _list(Object? value) => value! as List<Object?>;
double _num(Object? value) => (value! as num).toDouble();
Matcher _near(num expected) => closeTo(expected.toDouble(), 0.01);
WidthClass _class(Object? wire) => WidthClass.values.firstWhere((v) => v.wire == wire);

/// A screen width at which the class is GUARANTEED to be the one in the row.
double _widthOf(WidthClass widthClass) => switch (widthClass) {
  WidthClass.compact => 393,
  WidthClass.medium => 768,
  WidthClass.expanded => 1280,
};

void _view(WidgetTester tester, double width, [double height = 1000]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

_Json _literal(String text) => {'kind': 'literal', 'value': text};

_Json _text(String id, String text, {List<String>? showOn}) => {
  'id': id,
  'type': 'Text',
  'props': {'content': _literal(text)},
  'showOn': ?showOn,
};

_Json _navItem(String id, String label, {String? section, String icon = 'house', _Json? action, List<String>? showOn}) => {
  'id': id,
  'type': 'NavItem',
  'showOn': ?showOn,
  'props': {
    'icon': icon,
    'label': _literal(label),
    'action': action ?? {'type': 'navigate.section', 'params': {'screenId': section ?? id}},
  },
};

/// A bar with `count` items; labels are "Aaa..." of varying length (Ahem: one glyph = font size).
_Json _navBar({int count = 3, _Json? props, _Json? style, List<String>? showOn, List<String>? labels}) => {
  'id': 'nav',
  'type': 'NavBar',
  'props': props ?? <String, Object?>{},
  'style': ?style,
  'showOn': ?showOn,
  'children': [
    for (var i = 0; i < count; i++) _navItem('item-$i', labels?[i] ?? ('Item ' * (i + 1)).trim(), section: 'item-$i'),
  ],
};

_Json _appBar({_Json? visibleIf, List<String>? showOn, int actions = 0, bool showBack = false, String? titleAlign, double? height}) => {
  'id': 'bar',
  'type': 'AppBar',
  'props': {'title': _literal('Title'), 'showBack': showBack, 'titleAlign': ?titleAlign},
  'style': height == null ? null : {'height': height},
  'visibleIf': ?visibleIf,
  'showOn': ?showOn,
  'children': [
    for (var i = 0; i < actions; i++)
      {
        'id': 'action-$i',
        'type': 'IconButton',
        'props': {'icon': 'bell', 'label': _literal('Action $i'), 'action': {'type': 'none'}},
      },
  ],
};

_Json _screen(String id, List<_Json> children, {_Json? style, Object? gap, String? presentation, Object? placement, _Json? props}) => {
  'screenId': id,
  'name': id,
  'presentation': ?presentation,
  'modalPlacement': ?placement,
  'root': {
    'id': '$id-root',
    'type': 'Screen',
    'props': {'gap': gap ?? 'none', ...?props},
    'style': ?style,
    'children': children,
  },
};

UiDocument _doc(List<_Json> screens, {String? initial}) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'wide-chrome',
  'name': 'wide-chrome',
  'initialScreenId': initial ?? screens.first['screenId'],
  'screens': screens,
});

/// Data for the listed paths: each one holds (`true`).
Map<String, Object?> _metMap(List<Object?> paths) {
  final document = <String, Object?>{};
  for (final path in paths.cast<String>()) {
    final parts = path.split('.');
    var at = document;
    for (final part in parts.take(parts.length - 1)) {
      at = (at[part] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    at[parts.last] = true;
  }
  return document;
}

/// Where on the drawn screen the nav item stands: in the app bar, in its own strip, in the bottom zone or in the body.
String _drawnPlace(WidgetTester tester, String itemId) {
  final item = find.byKey(ValueKey('sdui-nav-item-$itemId'));
  if (item.evaluate().isEmpty) return 'nowhere';
  if (find.ancestor(of: item, matching: find.byType(AppBarLayout)).evaluate().isNotEmpty) return 'appBar';
  bool inZone(String zone) => find.ancestor(of: item, matching: find.byKey(ValueKey('hl-zone-$zone'))).evaluate().isNotEmpty;
  if (inZone('bar')) return 'top';
  if (inZone('low')) return 'bottom';
  return 'body';
}

WideNavMetrics _metricsOf(Object? raw) {
  final m = _obj(raw);
  return WideNavMetrics(
    paddingInline: _num(m['paddingInline']),
    iconWidth: _num(m['iconWidth']),
    gap: _num(m['gap']),
    between: _num(m['between']),
  );
}

final _Json _defaults = _obj(_table['wideDefaults']);

void main() {
  // ───────────────────────────── table structure ─────────────────────────────

  test('table: 176 new rows in thirteen groups', () {
    final counts = {
      'chromeCases': 35,
      'wideNavItemCases': 7,
      'wideNavHeightCases': 3,
      'wideAppBarCases': 23,
      'wideNavBarCases': 7,
      'wideZoneCases': 27,
      'wideModalCases': 14,
      'wideModalRadiusCases': 9,
      'wideSectionCases': 10,
      'wideRuleCases': 21,
      'wideModalContentCases': 10,
      'olderReaderShowOnCases': 10,
    };
    for (final entry in counts.entries) {
      expect(_rows(entry.key), hasLength(entry.value), reason: entry.key);
      expect({for (final row in _rows(entry.key)) row['name']}, hasLength(entry.value), reason: '${entry.key}: names are distinct');
    }
    expect(counts.values.reduce((a, b) => a + b), 176);
  });

  test('shared row numbers are the numbers of the default theme of the reader', () {
    final theme = RenderTheme.fallback();
    final nav = _obj(_defaults['nav']);
    expect(nav['paddingInline'], theme.space(SpacingToken.md));
    expect(nav['iconWidth'], theme.iconBox(IconSizeToken.md).width);
    expect(nav['gap'], theme.space(SpacingToken.xs));
    expect(nav['between'], theme.space(SpacingToken.xs));
    final bar = _obj(_defaults['bar']);
    expect(bar['gap'], theme.space(SpacingToken.sm));
    expect(bar['actionGap'], theme.space(SpacingToken.xs));
    expect(bar['backSide'], theme.space(SpacingToken.xl));
    expect(_defaults['modalMargin'], theme.space(SpacingToken.xl));
  });

  // ───────────────────────────── chromeCases ─────────────────────────────

  group('chromeCases: who stands where', () {
    for (final row in _rows('chromeCases')) {
      final widthClass = _class(row['widthClass']);
      final expected = _obj(row['expect']);
      final specs = _list(row['children']).map(_obj).toList();

      List<ChildNode> parsed() => [
        for (final spec in specs)
          UiNode.parse(
                {'props': <String, Object?>{}, ...spec},
                widthClass: widthClass,
              )
              as ChildNode,
      ];

      test('formula: ${row['name']}', () {
        final children = parsed();
        final data = _metMap(_list(row['met']));
        final dataLayers = ScreenData(data);
        final infos = [
          for (final child in children)
            (
              type: child is AppBarNode ? 'AppBar' : (child is NavBarNode ? kNavBarType : 'other'),
              pin: child.pin,
            ),
        ];
        final zones = screenChildrenByZone(infos);
        final navDeclared = zones.navBar == null ? null : children[zones.navBar!];
        final barDeclared = zones.appBar == null ? null : children[zones.appBar!];
        final chrome = screenChromeIn(
          infos,
          widthClass,
          navPlacement: navDeclared is NavBarNode ? navDeclared.widePlacement : NavWidePlacement.top,
          appBarShown: barDeclared != null && barDeclared.isVisible(dataLayers),
        );
        String? id(int? index) => index == null ? null : children[index].id;
        expect({
          'navPlace': chrome.navPlace?.name,
          'appBar': id(chrome.zones.appBar),
          'pinned': id(chrome.zones.pinned),
          'navBar': id(chrome.zones.navBar),
          'body': [for (var i = chrome.zones.bodyFrom; i < chrome.zones.bodyTo; i++) children[i].id],
        }, {
          'navPlace': expected['navPlace'],
          'appBar': expected['appBar'],
          'pinned': expected['pinned'],
          'navBar': expected['navBar'],
          'body': expected['body'],
        });
        // Zones are exactly those from the document; on `compact` the bar is always at the bottom.
        expect(screenChromeIn(infos, WidthClass.compact).navPlace, zones.navBar == null ? isNull : NavBarPlace.bottom);
        // Is the bar shown? Class and condition are two halves of one visibility.
        if (navDeclared != null && expected.containsKey('navShown')) {
          expect(navDeclared.isVisible(dataLayers), expected['navShown']);
        }
      });

      testWidgets('real screen: ${row['name']}', (tester) async {
        _view(tester, _widthOf(widthClass));
        final children = [
          for (final spec in specs)
            switch (spec['type']) {
              'AppBar' => {..._appBar(visibleIf: _obj(spec['visibleIf'] ?? {})['path'] == null ? null : _obj(spec['visibleIf']), showOn: (spec['showOn'] as List?)?.cast<String>()), 'pin': ?spec['pin']},
              'NavBar' => {
                ..._navBar(props: spec['props'] == null ? null : _obj(spec['props']), showOn: (spec['showOn'] as List?)?.cast<String>()),
              },
              _ => {
                'id': spec['id'],
                'type': 'Container',
                'props': {'direction': 'column'},
                'style': {'height': 40},
                'children': [_text('${spec['id']}-text', '${spec['id']}-label')],
                'pin': ?spec['pin'],
              },
            },
        ];
        await pumpDocument(tester, _doc([_screen('s', children)]), data: _metMap(_list(row['met'])));
        expect(tester.takeException(), isNull);
        final shown = row['expect'] as _Json;
        final navInDocument = specs.any((spec) => spec['type'] == 'NavBar');
        final expectedPlace = shown['navPlace'] as String?;
        final navHidden = shown['navShown'] == false;
        final want = navHidden
            ? 'nowhere'
            : expectedPlace ?? (navInDocument ? 'body' : 'nowhere');
        expect(_drawnPlace(tester, 'item-0'), want);
        // A top bar is not in the bottom zone; a bottom bar is there and nowhere else.
        final inLow = find.byKey(const ValueKey('hl-zone-low'));
        if (expectedPlace != 'bottom') {
          expect(
            find.descendant(of: inLow, matching: find.byKey(const ValueKey('sdui-nav-item-item-0'))),
            findsNothing,
          );
        }
        // Children exactly once: no duplicate item, no loss.
        expect(find.byKey(const ValueKey('sdui-nav-item-item-0')).evaluate().length, want == 'nowhere' ? 0 : 1);
      });
    }
  });

  // ───────────────────────────── item at the top ─────────────────────────────

  group('wideNavItemCases, wideNavHeightCases: item', () {
    final metrics = _metricsOf(_defaults['nav']);
    for (final row in _rows('wideNavItemCases')) {
      test(row['name']! as String, () {
        final mode = WideNavMode.values.byName(row['mode']! as String);
        expect(wideNavItemWidth(_num(row['labelWidth']), metrics, mode), _near(_num(row['expect'])));
      });
    }
    for (final row in _rows('wideNavHeightCases')) {
      test(row['name']! as String, () {
        final expected = _obj(row['expect']);
        expect(
          wideNavItemHeight(paddingBlock: _num(row['paddingBlock']), iconBox: _num(row['iconBox']), labelLine: _num(row['labelLine'])),
          _near(_num(expected['item'])),
        );
        expect(
          wideNavBarHeight(
            paddingBlock: _num(row['paddingBlock']),
            iconBox: _num(row['iconBox']),
            labelLine: _num(row['labelLine']),
            borderBottom: _num(row['borderBottom']),
          ),
          _near(_num(expected['bar'])),
        );
      });
    }

    test('label width is capped: beyond three dots (160) the item does not grow', () {
      final item = wideNavItemWidth(10000, metrics, WideNavMode.labels);
      expect(item, wideNavItemWidth(kWideNavLabelMax, metrics, WideNavMode.labels));
      expect(wideNavGroupWidth(const [], metrics, WideNavMode.labels), 0);
    });
  });

  // ───────────────────────────── app bar with items ─────────────────────────────

  group('wideAppBarCases: items in the app bar', () {
    final metrics = _metricsOf(_defaults['nav']);
    final barDefaults = _obj(_defaults['bar']);
    InlineInset inset(Object? raw) => raw == null ? (start: 0.0, end: 0.0) : (start: _num(_obj(raw)['start']), end: _num(_obj(raw)['end']));
    ({double x, double width}) fromLeft(ScreenInlineRect box, double start, double width, bool rtl) =>
        (x: rtl ? box.x + box.width - start - width : box.x + start, width: width);

    for (final row in _rows('wideAppBarCases')) {
      final rtl = row['rtl'] == true;
      final bar = _obj(row['bar']);
      final labels = _list(row['labels']).map(_num).toList();
      final expected = _obj(row['expect']);
      final contentMax = row['contentMaxWidth'] == null ? null : (row['contentMaxWidth']! as num).toInt();

      test('formula: ${row['name']}', () {
        final box = screenContentRects(width: _num(row['width']), padding: inset(row['padding']), contentMaxWidth: contentMax, rtl: rtl).appBar;
        final zones = wideAppBarZones(
          width: box.width,
          showBack: bar['showBack']! as bool,
          backSide: _num(barDefaults['backSide']),
          leadingNatural: bar['leadingNatural'] == null ? null : _num(bar['leadingNatural']),
          actionSides: _list(bar['actionSides']).map(_num).toList(),
          gap: _num(barDefaults['gap']),
          actionGap: _num(barDefaults['actionGap']),
          titleNatural: _num(bar['titleNatural']),
          titleAlign: bar['titleAlign'],
          navLabels: labels,
          nav: metrics,
        );
        expect(zones.navMode.name, expected['mode']);
        expect(zones.clipped, expected['clipped']);
        expect(zones.zones.truncated, expected['truncated']);
        expect(zones.zones.centered, expected['centered']);
        void same(({double x, double width}) got, Object? want, String what) {
          expect(got.x, _near(_num(_obj(want)['x'])), reason: '$what: x');
          expect(got.width, _near(_num(_obj(want)['width'])), reason: '$what: width');
        }

        if (expected['leading'] == null) {
          expect(zones.zones.leadingShown, AppBarLeadingShown.none);
        } else {
          same(fromLeft(box, 0, zones.zones.leadingWidth, rtl), expected['leading'], 'leading zone');
        }
        same(fromLeft(box, zones.zones.titleStart, zones.zones.titleWidth, rtl), expected['title'], 'title');
        final items = _list(expected['items']);
        expect(zones.navItemStarts, hasLength(items.length));
        for (var i = 0; i < items.length; i++) {
          same(fromLeft(box, zones.navItemStarts[i], zones.navItemWidths[i], rtl), items[i], 'item $i');
        }
        final actions = _list(expected['actions']);
        for (var i = 0; i < actions.length; i++) {
          same(fromLeft(box, zones.actionStarts[i], _num(_list(bar['actionSides'])[i]), rtl), actions[i], 'action $i');
        }
      });

      testWidgets('real app bar computes the same as the formula from measured values: ${row['name']}', (tester) async {
        final width = _num(row['width']);
        _view(tester, width);
        final padding = inset(row['padding']);
        final actionCount = _list(bar['actionSides']).length;
        // Labels come from Ahem (one glyph = font size): length as in the row, since the items view is decided by measurement.
        final texts = [for (var i = 0; i < labels.length; i++) '$i${'L' * (labels[i] / 14).round()}'];
        final document = _doc([
          _screen(
            's',
            [
              {
                ..._appBar(actions: actionCount, showBack: bar['showBack'] == true, titleAlign: bar['titleAlign'] as String?),
                'props': {
                  'title': _literal('T' * (1 + (_num(bar['titleNatural']) / 18).round())),
                  'showBack': bar['showBack'] == true,
                  'titleAlign': ?bar['titleAlign'],
                },
                'children': [
                  for (var i = 0; i < actionCount; i++)
                    {
                      'id': 'action-$i',
                      'type': 'IconButton',
                      'props': {'icon': 'bell', 'label': _literal('Action $i'), 'action': {'type': 'none'}},
                    },
                  if (bar['leadingNatural'] != null)
                    {
                      'id': 'lead',
                      'type': 'Button',
                      'zone': 'leading',
                      'props': {'label': _literal('Lead'), 'variant': 'secondary', 'action': {'type': 'none'}},
                    },
                ],
              },
              {
                'id': 'list',
                'type': 'Container',
                'props': {'direction': 'column'},
                'style': {'height': 40},
              },
              _navBar(count: labels.length, labels: texts),
            ],
            style: {'padding': {'start': padding.start, 'end': padding.end, 'top': 0, 'bottom': 0}},
            props: contentMax == null ? null : {'contentMaxWidth': contentMax},
          ),
        ]);
        await pumpDocument(tester, document, locale: rtl ? 'ar' : null);
        expect(tester.takeException(), isNull);
        expect(_drawnPlace(tester, 'item-0'), 'appBar');

        final layout = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
        final group = tester.renderObject<RenderWideNavGroup>(find.byType(WideNavGroup));
        final box = Rect.fromLTWH(layout.localToGlobal(Offset.zero).dx, 0, layout.size.width, 1);
        // Natural widths of the app bar children are what it measures itself (no width constraints).
        final kids = <RenderBox>[
          for (var child = layout.firstChild; child != null; child = layout.childAfter(child)) child,
        ];
        var k = 0;
        final leadingBox = (bar['showBack'] == true || bar['leadingNatural'] != null) ? kids[k++] : null;
        final titleBox = kids[k++];
        k++; // item group
        final actionBoxes = kids.sublist(k);
        double natural(RenderBox box) => box.getDryLayout(const BoxConstraints()).width;
        final naturals = group.naturalLabelWidths;
        final zones = wideAppBarZones(
          width: box.width,
          showBack: bar['showBack'] == true,
          backSide: _num(barDefaults['backSide']),
          leadingNatural: bar['leadingNatural'] == null ? null : natural(leadingBox!),
          actionSides: [for (final action in actionBoxes) natural(action)],
          gap: _num(barDefaults['gap']),
          actionGap: _num(barDefaults['actionGap']),
          titleNatural: natural(titleBox),
          titleAlign: bar['titleAlign'],
          navLabels: naturals,
          nav: group.metrics,
        );
        expect(layout.navMode, zones.navMode, reason: 'items view = reference verdict from measured values');
        expect(group.drawnMode, zones.navMode);
        // Items stand where the formula says: from the start of the group, each at its own width.
        final start = rtl ? box.right - zones.navStart - zones.navWidth : box.left + zones.navStart;
        final items = [for (var i = 0; i < labels.length; i++) tester.getRect(find.byKey(ValueKey('sdui-nav-item-item-$i')))];
        for (var i = 0; i < items.length; i++) {
          final itemStart = zones.navItemStarts[i] - zones.navStart;
          final left = rtl ? start + zones.navWidth - itemStart - zones.navItemWidths[i] : start + itemStart;
          expect(items[i].left, _near(left), reason: 'item $i: x');
          expect(items[i].width, _near(zones.navItemWidths[i]), reason: 'item $i: width does not shrink');
        }
        // Items come before actions in reading order; nothing overlaps until clipped.
        if (!zones.clipped) {
          // Left to right: in right-to-left writing the first item is the rightmost.
          final ordered = rtl ? items.reversed.toList() : items;
          for (var i = 0; i + 1 < ordered.length; i++) {
            expect(ordered[i].right, lessThanOrEqualTo(ordered[i + 1].left + 0.01), reason: 'items do not overlap');
          }
          expect(items.first.top, items.last.top, reason: 'items in one row');
          for (var i = 0; i < actionCount; i++) {
            final action = actionBoxes[i].localToGlobal(Offset.zero) & actionBoxes[i].size;
            final edge = rtl ? items.map((r) => r.left).reduce((a, b) => a < b ? a : b) : items.map((r) => r.right).reduce((a, b) => a > b ? a : b);
            expect(rtl ? action.right <= edge + 0.01 : action.left >= edge - 0.01, isTrue, reason: 'action $i after the items');
          }
        }
        // A hidden label stays the item name: in markup and in semantics.
        for (var i = 0; i < labels.length; i++) {
          final node = tester.getSemantics(find.bySemanticsLabel(texts[i]));
          expect(node.label, texts[i]);
          expect(node.flagsCollection.isButton, isTrue);
          expect(node.flagsCollection.isSelected, Tristate.isFalse);
        }
      });
    }
  });

  // ───────────────────────────── own top strip ─────────────────────────────

  group('wideNavBarCases: own top strip', () {
    final metrics = _metricsOf(_defaults['nav']);
    for (final row in _rows('wideNavBarCases')) {
      final rtl = row['rtl'] == true;
      final labels = _list(row['labels']).map(_num).toList();
      final expected = _obj(row['expect']);
      final contentMax = row['contentMaxWidth'] == null ? null : (row['contentMaxWidth']! as num).toInt();
      InlineInset inset(Object? raw) => raw == null ? (start: 0.0, end: 0.0) : (start: _num(_obj(raw)['start']), end: _num(_obj(raw)['end']));

      test('formula: ${row['name']}', () {
        final box = screenContentRects(
          width: _num(row['width']),
          padding: (start: 0, end: 0),
          contentMaxWidth: contentMax,
          navBarInset: inset(row['navBarInset']),
          rtl: rtl,
        ).navBar;
        final bar = wideNavBarOf(width: box.width, navLabels: labels, nav: metrics);
        expect(bar.navMode.name, expected['mode']);
        expect(bar.clipped, expected['clipped']);
        final items = _list(expected['items']).map(_obj).toList();
        for (var i = 0; i < items.length; i++) {
          final x = rtl ? box.x + box.width - bar.navItemStarts[i] - bar.navItemWidths[i] : box.x + bar.navItemStarts[i];
          expect(x, _near(_num(items[i]['x'])), reason: 'item $i: x');
          expect(bar.navItemWidths[i], _near(_num(items[i]['width'])), reason: 'item $i: width');
        }
      });

      testWidgets('real strip: ${row['name']}', (tester) async {
        final width = _num(row['width']);
        _view(tester, width);
        final texts = [for (var i = 0; i < labels.length; i++) '$i${'L' * (labels[i] / 14).round()}'];
        // The reader clamps a margin above the schema limit (128): the formula checks the 200 row, and the widget
        // runs the same scenario with the largest legal margin.
        final rowInset = inset(row['navBarInset']);
        final legal = (start: rowInset.start.clamp(0.0, kMaxSpacingPx), end: rowInset.end.clamp(0.0, kMaxSpacingPx));
        final navStyle = row['navBarInset'] == null ? null : {'padding': {'start': legal.start, 'end': legal.end}};
        await pumpDocument(
          tester,
          _doc([
            _screen(
              's',
              [
                {'id': 'list', 'type': 'Container', 'props': {'direction': 'column'}, 'style': {'height': 40}},
                _navBar(count: labels.length, labels: texts, style: navStyle),
              ],
              props: contentMax == null ? null : {'contentMaxWidth': contentMax},
            ),
          ]),
          locale: rtl ? 'ar' : null,
        );
        expect(tester.takeException(), isNull);
        expect(_drawnPlace(tester, 'item-0'), 'top');
        final group = tester.renderObject<RenderWideNavGroup>(find.byType(WideNavGroup));
        final groupRect = tester.getRect(find.byType(WideNavGroup));
        // Group width is the strip content column; the view is decided by natural widths.
        final box = screenContentRects(
          width: width,
          padding: (start: 0, end: 0),
          contentMaxWidth: contentMax,
          navBarInset: legal,
          rtl: rtl,
        ).navBar;
        expect(groupRect.left, _near(box.x));
        expect(groupRect.width, _near(box.width));
        final formula = wideNavBarOf(width: box.width, navLabels: group.naturalLabelWidths, nav: group.metrics);
        expect(group.drawnMode, formula.navMode);
        for (var i = 0; i < labels.length; i++) {
          final item = tester.getRect(find.byKey(ValueKey('sdui-nav-item-item-$i')));
          final left = rtl ? box.x + box.width - formula.navItemStarts[i] - formula.navItemWidths[i] : box.x + formula.navItemStarts[i];
          expect(item.left, _near(left), reason: 'item $i');
          expect(item.width, _near(formula.navItemWidths[i]));
        }
      });
    }
  });

  // ───────────────────────────── screen zones ─────────────────────────────

  group('wideZoneCases: screen zones', () {
    final z = _obj(_defaults['zone']);
    final pad = _obj(z['padding']);

    for (final row in _rows('wideZoneCases')) {
      final widthClass = _class(row['widthClass']);
      final has = _obj(row['has']);
      final expected = _obj(row['expect']);
      final placement = row['widePlacement'] as String?;
      final bodyHeight = row.containsKey('bodyContentHeight') ? (row['bodyContentHeight'] as num?)?.toDouble() : _num(z['bodyContentHeight']);
      final scrollTop = _num(row['scrollTop'] ?? 0);

      NavBarPlace? placeOf() {
        final infos = <RootChildInfo>[
          if (has['appBar'] == true) (type: 'AppBar', pin: false),
          (type: 'other', pin: false),
          if (has['pinned'] == true) (type: 'other', pin: true),
          if (has['navBar'] == true) (type: kNavBarType, pin: false),
        ];
        return screenChromeIn(infos, widthClass, navPlacement: navWidePlacementOf(placement)).navPlace;
      }

      test('formula: ${row['name']}', () {
        final place = placeOf();
        final wide = wideScreenZoneBoxes(
          navPlace: place,
          navBarHeight: place == NavBarPlace.bottom ? _num(z['navBarBottomHeight']) : (place == NavBarPlace.top ? _num(z['navBarTopHeight']) : null),
          height: _num(z['height']),
          appBarHeight: has['appBar'] == true ? _num(z['appBarHeight']) : null,
          paddingTop: _num(pad['top']),
          paddingBottom: _num(pad['bottom']),
          gap: _num(z['gap']),
          bodyContentHeight: bodyHeight,
          scrollTop: scrollTop,
          pinnedHeight: has['pinned'] == true ? _num(z['pinnedHeight']) : null,
          safeBottom: _num(z['safeBottom']),
        );
        final zones = wide.zones;
        expect(place?.name, expected['navPlace']);
        expect(zones.height, _near(_num(z['height'])));
        if (expected['appBar'] == null) {
          expect(zones.appBarTop, isNull);
        } else {
          expect(zones.appBarTop, _near(_num(_obj(expected['appBar'])['top'])));
          expect(zones.appBarHeight, _near(_num(_obj(expected['appBar'])['height'])));
        }
        if (expected['topNav'] == null) {
          expect(wide.topNavTop, isNull);
        } else {
          expect(wide.topNavTop, _near(_num(_obj(expected['topNav'])['top'])));
          expect(wide.topNavHeight, _near(_num(_obj(expected['topNav'])['height'])));
        }
        expect(zones.bodyTop, _near(_num(_obj(expected['body'])['top'])));
        expect(zones.bodyHeight, _near(_num(_obj(expected['body'])['height'])));
        expect(zones.contentTop, _near(_num(expected['contentTop'])));
        expect(zones.contentHeight, _near(_num(expected['contentHeight'])));
        expect(zones.maxScroll, _near(_num(expected['maxScroll'])));
        final bottom = expected['bottom'];
        if (bottom == null) {
          expect(zones.bottom, isNull, reason: 'no bottom zone - no safe inset either');
          return;
        }
        final want = _obj(bottom);
        final got = zones.bottom!;
        expect(got.top, _near(_num(want['top'])));
        expect(got.height, _near(_num(want['height'])));
        expect(got.safeBottom, _near(_num(want['safeBottom'])));
        if (want['pinned'] == null) {
          expect(got.pinnedTop, isNull);
        } else {
          expect(got.pinnedTop, _near(_num(_obj(want['pinned'])['top'])));
          expect(got.pinnedHeight, _near(_num(_obj(want['pinned'])['height'])));
        }
        if (want['navBar'] == null) {
          expect(got.navTop, isNull);
        } else {
          expect(got.navTop, _near(_num(_obj(want['navBar'])['top'])));
          expect(got.navHeight, _near(_num(_obj(want['navBar'])['height'])));
          expect(got.navContentHeight, _near(_num(_obj(want['navBar'])['contentHeight'])));
        }
      });

      testWidgets('real screen: ${row['name']}', (tester) async {
        final width = _widthOf(widthClass);
        _view(tester, width, _num(z['height']));
        final place = expected['navPlace'] as String?;
        final content = <_Json>[
          if (has['appBar'] == true) _appBar(height: _num(z['appBarHeight'])),
          if (bodyHeight != null)
            {
              'id': 'content',
              'type': 'Container',
              'props': {'direction': 'column'},
              'style': {'height': bodyHeight},
              'children': [_text('mark', 'Початок')],
            },
          if (has['pinned'] == true)
            {
              'id': 'cta',
              'type': 'Container',
              'props': {'direction': 'column'},
              'style': {'height': _num(z['pinnedHeight'])},
              'children': [_text('cta-text', 'Прибитий')],
              'pin': 'bottom',
            },
          if (has['navBar'] == true) _navBar(count: 2, labels: const ['Ab', 'Cd'], props: placement == null ? null : {'widePlacement': placement}),
        ];
        await pumpDocument(
          tester,
          _doc([_screen('s', content, style: {'padding': pad}, gap: _num(z['gap']))]),
          safeBottom: _num(z['safeBottom']),
        );
        expect(tester.takeException(), isNull);

        final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
        final frame = zones.localToGlobal(Offset.zero) & zones.size;
        Rect rectOf(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;
        final children = <RenderBox>[
          for (var child = zones.firstChild; child != null; child = zones.childAfter(child)) child,
        ];
        final hasBarZone = has['appBar'] == true || place == 'top';
        var index = 0;
        final barZone = hasBarZone ? children[index++] : null;
        final body = children[index++];
        final lower = children.sublist(index);

        // What the bar stands with: the place says where its items are drawn.
        expect(_drawnPlace(tester, 'item-0'), has['navBar'] == true ? (place ?? 'bottom') : 'nowhere');
        if (expected['topNav'] != null) {
          final bar = rectOf(barZone!);
          expect(bar.top - frame.top, _near(_num(_obj(expected['topNav'])['top'])));
          expect(bar.height, _near(_num(_obj(expected['topNav'])['height'])), reason: 'strip = item + line');
        }
        if (expected['appBar'] != null) {
          final bar = tester.getRect(find.byType(AppBarLayout));
          expect(bar.top - frame.top, _near(_num(_obj(expected['appBar'])['top'])));
          expect(bar.height, _near(_num(_obj(expected['appBar'])['height'])));
        }
        final bodyRect = rectOf(body);
        expect(bodyRect.top - frame.top, _near(_num(_obj(expected['body'])['top'])), reason: 'body top');
        expect(bodyRect.height, _near(_num(_obj(expected['body'])['height'])), reason: 'body height');
        final bottom = expected['bottom'];
        if (bottom == null) {
          expect(lower, isEmpty, reason: 'no bottom zone');
          expect(bodyRect.bottom - frame.top, _near(_num(z['height'])), reason: 'body reaches the very bottom: no safe inset');
        } else {
          final want = _obj(bottom);
          expect(lower, isNotEmpty);
          final union = lower.map(rectOf).reduce((a, b) => a.expandToInclude(b));
          expect(union.top - frame.top, _near(_num(want['top'])), reason: 'bottom zone top');
          expect(union.height, _near(_num(want['height'])), reason: 'bottom zone height');
          if (want['pinned'] != null) {
            expect(tester.getTopLeft(find.text('Прибитий')).dy - frame.top, _near(_num(_obj(want['pinned'])['top'])));
          }
          final nav = want['navBar'];
          if (nav != null) {
            final item = tester.getRect(find.byKey(const ValueKey('sdui-nav-item-item-0')));
            expect(item.top - frame.top, _near(_num(_obj(nav)['top'])));
            expect(item.height, _near(_num(_obj(nav)['contentHeight'])));
          }
        }
      });
    }
  });

  // ───────────────────────────── modal layer ─────────────────────────────

  group('wideModalCases: sheet or window', () {
    final margin = _num(_defaults['modalMargin']);

    for (final row in _rows('wideModalCases')) {
      final viewport = _obj(row['viewport']);
      final expected = _obj(row['expect']);
      final contentHeight = _num(row['contentHeight']);

      test('formula: ${row['name']}', () {
        final box = modalLayerBoxOf(
          placement: row['placement'],
          viewportWidth: _num(viewport['width']),
          viewportHeight: _num(viewport['height']),
          contentHeight: contentHeight,
          margin: margin,
        );
        expect(box.shape.name, expected['shape']);
        expect(box.x, _near(_num(expected['x'])));
        expect(box.y, _near(_num(expected['y'])));
        expect(box.width, _near(_num(expected['width'])));
        expect(box.height, _near(_num(expected['height'])));
        expect(box.scrolls, expected['scrolls']);
        expect(box.contentWidthClass.wire, expected['contentWidthClass']);
        expect(modalShapeOf(row['placement'], _num(viewport['width'])).name, expected['shape']);
        expect(modalLayerWidthOf(row['placement'], _num(viewport['width']), margin), _near(_num(expected['width'])));
      });

      testWidgets('real flow: ${row['name']}', (tester) async {
        _view(tester, _num(viewport['width']), _num(viewport['height']));
        await pumpDocument(
          tester,
          _doc([
            _screen('page', [
              {
                'id': 'open',
                'type': 'Button',
                'props': {'label': _literal('Відкрити'), 'variant': 'primary', 'action': {'type': 'navigate', 'params': {'screenId': 'layer'}}},
              },
            ]),
            _screen(
              'layer',
              [
                {
                  'id': 'content',
                  'type': 'Container',
                  'props': {'direction': 'column'},
                  'style': {'height': contentHeight},
                  'children': [
                    // Layer CONTENT class comes from its own box: only one of the three is shown.
                    _text('c', 'class-compact', showOn: ['compact']),
                    _text('m', 'class-medium', showOn: ['medium']),
                    _text('e', 'class-expanded', showOn: ['expanded']),
                  ],
                },
              ],
              presentation: 'modal',
              placement: row['placement'],
            ),
          ]),
        );
        await tester.tap(find.text('Відкрити'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final rect = tester.getRect(find.byKey(kModalLayerKey));
        expect(rect.left, _near(_num(expected['x'])), reason: 'x');
        expect(rect.top, _near(_num(expected['y'])), reason: 'y');
        expect(rect.width, _near(_num(expected['width'])), reason: 'width');
        expect(rect.height, _near(_num(expected['height'])), reason: 'height');
        final scrollable = find.descendant(of: find.byKey(kModalLayerKey), matching: find.byType(Scrollable));
        final extent = tester.state<ScrollableState>(scrollable.first).position.maxScrollExtent;
        expect(extent > 0.01, expected['scrolls'], reason: 'taller content scrolls inside the layer, the app bar stays');
        final visible = [
          for (final name in ['compact', 'medium', 'expanded'])
            if (find.text('class-$name').evaluate().isNotEmpty) name,
        ];
        expect(visible, [expected['contentWidthClass']], reason: 'content class comes from the layer box');
      });
    }
  });

  group('wideModalRadiusCases: window-sheet radius', () {
    for (final row in _rows('wideModalRadiusCases')) {
      test('formula: ${row['name']}', () {
        final radius = BoxRadius.tryParse(row['radius']);
        expect(sheetWindowRadius(radius), BoxRadius.tryParse(row['expect']));
        // Nothing changed: the same value, not a copy.
        if (jsonEncode(row['radius']) == jsonEncode(row['expect'])) expect(sheetWindowRadius(radius), same(radius));
      });

      testWidgets('real layer: ${row['name']}', (tester) async {
        // The sheet root in a window is drawn EXACTLY like a root whose radius is already written, completed.
        Future<BorderRadiusGeometry?> radiusOf(Object? radius, double width) async {
          // New flow: the same document under the same tree would have kept the layer open.
          await tester.pumpWidget(const SizedBox());
          _view(tester, width, 900);
          await pumpDocument(
            tester,
            _doc([
              _screen('page', [
                {
                  'id': 'open',
                  'type': 'Button',
                  'props': {'label': _literal('Відкрити'), 'variant': 'primary', 'action': {'type': 'navigate', 'params': {'screenId': 'layer'}}},
                },
              ]),
              {
                ..._screen(
                  'layer',
                  [
                    {'id': 'content', 'type': 'Container', 'props': {'direction': 'column'}, 'style': {'height': 100}},
                  ],
                  presentation: 'modal',
                  style: {
                    'background': {'kind': 'color', 'color': {'value': '#112233'}},
                    'radius': ?radius,
                  },
                ),
              },
            ]),
          );
          await tester.tap(find.text('Відкрити'));
          await tester.pumpAndSettle();
          final layer = find.byKey(kModalLayerKey);
          final boxes = find.descendant(
            of: layer,
            matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == const Color(0xFF112233)),
          );
          final decoration = tester.widget<DecoratedBox>(boxes.first).decoration as BoxDecoration;
          return decoration.borderRadius;
        }

        final onWide = await radiusOf(row['radius'], 1280);
        final fixedOnPhone = await radiusOf(row['expect'], 393);
        expect(onWide, fixedOnPhone);
        // On a phone (bottom sheet) the radius stays as in the document.
        final sheet = await radiusOf(row['radius'], 393);
        final plain = await radiusOf(row['radius'], 393);
        expect(sheet, plain);
      });
    }
  });

  // ───────────────────────────── sections ─────────────────────────────

  group('wideSectionCases: sections with different `widePlacement`', () {
    UiDocument sections(List<Object?> bars, String initial) => _doc([
      for (final raw in bars)
        () {
          final bar = _obj(raw);
          final id = bar['screenId']! as String;
          return _screen(id, [
            _text('$id-title', id),
            {
              ..._navBar(
                count: 2,
                props: bar['props'] == null ? null : _obj(bar['props']),
                showOn: (bar['showOn'] as List?)?.cast<String>(),
              ),
              'children': [
                for (final target in bars)
                  _navItem(
                    '$id-to-${_obj(target)['screenId']}',
                    'Go ${_obj(target)['screenId']}',
                    section: _obj(target)['screenId']! as String,
                    showOn: ((bar['itemsShowOn'] as Map?)?[_obj(target)['screenId']] as List?)?.cast<String>(),
                  ),
              ],
            },
          ]);
        }(),
    ], initial: initial);

    for (final row in _rows('wideSectionCases')) {
      testWidgets(row['name']! as String, (tester) async {
        _view(tester, 1280);
        final bars = _list(row['bars']);
        for (final raw in bars) {
          final bar = _obj(raw);
          final id = bar['screenId']! as String;
          // The reader draws each screen by its own field, even if the validator would reject the document.
          await tester.pumpWidget(const SizedBox());
          await pumpDocument(tester, sections(bars, id));
          expect(tester.takeException(), isNull);
          final field = bar['props'] == null ? null : _obj(bar['props'])['widePlacement'];
          // The bar and the item are drawn only at the classes of their `showOn` (at 1280 - `expanded`).
          bool shownWide(Object? showOn) => showOn == null || (showOn as List).contains('expanded');
          final itemShowOn = (bar['itemsShowOn'] as Map?)?[id];
          final drawn = shownWide(bar['showOn']) && shownWide(itemShowOn);
          expect(
            _drawnPlace(tester, '$id-to-$id'),
            drawn ? (field == 'bottom' ? 'bottom' : 'top') : 'nowhere',
            reason: 'section $id',
          );
        }
      });
    }
  });

  // ───────────────────── 9.18.0 clarifications: sheet content, older reader ─────────────────────

  group('wideModalContentCases: layer content width class', () {
    for (final row in _rows('wideModalContentCases')) {
      test(row['name']! as String, () {
        final presentation = row['presentation'] == 'none' ? null : row['presentation'];
        final expected = _obj(row['expect']);
        expect(modalContentAlwaysCompact(presentation), expected['alwaysCompact']);
        expect(screenContentWidthClassIn(presentation, _class(row['areaClass'])).wire, expected['contentWidthClass']);
        // The row area class is indeed the class of its width.
        expect(widthClassOf(_num(row['areaWidth'])), _class(row['areaClass']));
      });
    }

    test('predicate matches the layer box on EVERY wideModalCases row: sheet content is always compact', () {
      for (final row in _rows('wideModalCases')) {
        final viewport = _obj(row['viewport']);
        expect(modalContentAlwaysCompact('modal'), isTrue, reason: row['name']! as String);
        expect(
          _obj(row['expect'])['contentWidthClass'],
          screenContentWidthClassIn('modal', widthClassOf(_num(viewport['width']))).wire,
          reason: row['name']! as String,
        );
      }
    });
  });

  group('olderReaderShowOnCases: `showOn` against a reader older than 9.18', () {
    for (final row in _rows('olderReaderShowOnCases')) {
      test(row['name']! as String, () {
        final node = _obj(row['node']);
        final expected = _obj(row['expect']);
        expect(showOnAffectsOlderReaderOnCompact(node['showOn']), expected['affectsOlderReaderOnCompact']);
        expect(
          showOnReplacesBackArrowForOlderReader(rawShowOn: node['showOn'], rawZone: node['zone'], parentType: row['parent']),
          expected['replacesBackArrow'],
        );
      });
    }

    test('a leading-zone node outside the app bar does not replace the arrow', () {
      expect(showOnReplacesBackArrowForOlderReader(rawShowOn: ['medium'], rawZone: 'leading', parentType: 'Column'), isFalse);
      expect(showOnReplacesBackArrowForOlderReader(rawShowOn: ['medium'], rawZone: 'leading', parentType: null), isFalse);
    });

    test('the older-reader entry is in the artifact and in the mirror', () {
      final block = _obj(_obj(_obj(_schema['x-style'])['layout'])['widthClass'])['olderReader'] as Map;
      expect(block['showOnLeadingZone'], contains('back-arrow'));
      expect(block['showOn'], 'node-shown-on-every-width');
    });
  });

  // ───────────────────────────── artifact data ─────────────────────────────

  group('wideRuleCases: data blocks', () {
    final layout = _obj(_obj(_schema['x-style'])['layout']);
    for (final row in _rows('wideRuleCases')) {
      test(row['name']! as String, () {
        Object? at = layout;
        for (final part in (row['rule']! as String).split('.')) {
          at = at is List ? at[int.parse(part)] : (at! as Map)[part];
        }
        expect(at, row['expect']);
      });
    }

    test('reader mirrors are exactly the artifact blocks without the table address', () {
      final nav = {..._obj(layout['wideNav'])}..remove('cases');
      final modal = {..._obj(layout['wideModal'])}..remove('cases');
      expect(jsonDecode(jsonEncode(kWideNavLayout)), nav);
      expect(jsonDecode(jsonEncode(kWideModalRules)), modal);
      expect(_obj(layout['wideNav'])['cases'], 'contract/fixtures/adaptive/adaptive-cases.json');
      expect(_obj(layout['wideModal'])['cases'], 'contract/fixtures/adaptive/adaptive-cases.json');
    });

    test('reader numbers come from data, not from knowledge', () {
      final nav = _obj(layout['wideNav']);
      expect(kWideNavLabelMax, _obj(nav['item'])['labelMaxWidth']);
      expect(kWideNavTitleKeeps, _obj(nav['overflow'])['titleKeeps']);
      final window = _obj(_obj(layout['wideModal'])['window']);
      expect(kWideModalMaxWidth, window['maxWidth']);
      expect(kWideModalMaxHeightShare, window['maxHeightShare']);
      expect(kWideModalMaxWidth, lessThan(kWidthClassFrom[WidthClass.medium]!), reason: 'window is narrower than the medium boundary: its content is always compact');
      expect([for (final c in kWideNavLayout['classes']! as List) c], ['medium', 'expanded']);
    });

    test('blocks the reader mirrors by equality were not extended by the minor', () {
      for (final block in ['appBar', 'appBarLeading', 'appBarTitle', 'navBar', 'bottomZone', 'screen', 'modalLayer']) {
        final written = jsonEncode(layout[block]);
        for (final word in ['widePlacement', 'wideNav', 'wideModal', 'sheetWindow', '560']) {
          expect(written, isNot(contains(word)), reason: '$block: $word');
        }
      }
    });

    test('capabilities are named with version 9.18.0, no policy rows added', () {
      final compatibility = _obj(_schema['x-compatibility']);
      final features = _obj(compatibility['features']);
      for (final key in ['navBarOnWide', 'modalSheetOnWide']) {
        expect(features[key], '9.18.0', reason: key);
        expect(kFeatureCatalog[key], '9.18.0', reason: key);
      }
      final policy = _obj(compatibility['policy']);
      expect(policy.keys.where((key) => RegExp('wide|sheetWindow', caseSensitive: false).hasMatch(key)), isEmpty);
    });

    test('`widePlacement` field in the artifact: two words, optional, no default', () {
      final props = _obj(_obj(_schema[r'$defs'])['NavBarProps']);
      final field = _obj(_obj(props['properties'])['widePlacement']);
      expect(field['enum'], ['top', 'bottom']);
      expect((props['required'] as List?) ?? const [], isNot(contains('widePlacement')));
      expect(field.containsKey('default'), isFalse);
    });
  });

  // ───────────────────────────── untrusted input ─────────────────────────────

  group('widePlacement of the wrong shape means "no field" (top)', () {
    for (final (name, value) in <(String, Object?)>[
      ('number', 1),
      ('object', <String, Object?>{'a': 1}),
      ('null', null),
      ('empty string', ''),
      ('other case', 'Bottom'),
      ('array', ['bottom']),
      ('unknown word', 'side'),
    ]) {
      test('$name is read as `top`', () {
        expect(navWidePlacementOf(value), NavWidePlacement.top);
        final node = UiNode.parse({
          'id': 'nav',
          'type': 'NavBar',
          'props': {'widePlacement': value},
          'children': <Object?>[],
        }) as NavBarNode;
        expect(node.widePlacement, NavWidePlacement.top);
      });
    }

    test('exactly the word `bottom` keeps the bar at the bottom', () {
      expect(navWidePlacementOf('bottom'), NavWidePlacement.bottom);
    });
  });
}

