// GUARD OF THE PUBLIC ENTRY. Imports ONLY `hotlayout_flutter.dart` and the example from
// `example/`, the way an integrator would.
//
// What is caught here, and why this way:
//
//  * the example stopped compiling against the public entry: this file
//    imports `example/lib/*.dart`, so it will not build either. The README used
//    to be just text: `DocumentLocalization` was named in it but not visible
//    from the package, and the first outside integrator found out;
//  * an import through `src/` crept into the example: then the first point proves
//    nothing, since it compiles, but not against what the consumer sees;
//  * code appeared in the README that is not in the example. Every ```dart block there
//    must be a verbatim fragment of a file from `example/`: text nobody
//    compiles lies silently (the quick start once had a stale package name
//    in pubspec and seven imports the analyzer rejected);
//  * the public entry changed unnoticed: the export list is recorded here, and
//    a new name in it must be a decision, not a side effect of an edit.
// A relative import into another `lib/` is the point of the test here: the example is a separate package,
// and it can be built together with this file only that way.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

import '../example/lib/backend.dart';
import '../example/lib/main.dart' as example;
import '../example/lib/recipes.dart' as recipes;

/// The EXAMPLE's assets from disk: they are not in this package's bundle, and the example reads
/// exactly those.
class _ExampleBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File('example/$key').readAsBytesSync();
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File('example/$key').readAsStringSync();
}

/// Code lines without indentation and blank lines: a method fragment in the README
/// sits at a different indent than in the file, and that is not a divergence.
List<String> _code(String source) => [
  for (final line in const LineSplitter().convert(source))
    if (line.trim().isNotEmpty) line.trim(),
];

bool _contains(List<String> haystack, List<String> needle) {
  for (var start = 0; start + needle.length <= haystack.length; start += 1) {
    var same = true;
    for (var i = 0; i < needle.length && same; i += 1) {
      same = haystack[start + i] == needle[i];
    }
    if (same) return true;
  }
  return false;
}

Iterable<String> _dartBlocks(String markdown) =>
    RegExp(r'```dart\n(.*?)```', dotAll: true).allMatches(markdown).map((m) => m.group(1)!);

List<File> _exampleSources() => [
  for (final dir in ['example/lib', 'example/test'])
    ...Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')),
];

void main() {
  final bundle = _ExampleBundle();

  testWidgets('the example draws a document via the public entry: data, host action, transition', (tester) async {
    tester.view.physicalSize = const Size(430, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final themeLoad = await ThemeLoad.fromBundle(bundle: bundle, assetPath: example.themeAsset);
    expect(themeLoad.status, ThemeLoadStatus.ok, reason: themeLoad.detail);

    await tester.pumpWidget(
      MaterialApp(
        home: example.HotLayoutScreen(
          source: BundledDocumentSource(
            title: 'Bundled copy',
            assetPath: example.documentAsset,
            bundle: bundle,
          ),
          themeLoad: themeLoad,
          data: backendData,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ScreenFlow), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget, reason: 'value from the host map');
    expect(find.text('Top up 500'), findsOneWidget, reason: 'collection record');

    await tester.tap(find.text('Invite a friend'));
    await tester.pump();
    expect(find.text('Your share sheet opens here'), findsOneWidget, reason: 'the host executes the `share` action');

    await tester.tap(find.text('Missions').first);
    await tester.pumpAndSettle();
    expect(find.text('Claim reward'), findsOneWidget, reason: 'the renderer executes the transition');
    expect(
      find.bySemanticsLabel(const RendererLabels().back),
      findsOneWidget,
      reason: 'the screen reader names the panel arrow with a word from RendererLabels, not a hardcoded string',
    );
  });

  testWidgets('the "back" recipes from the example work: the host own arrow and interception', (tester) async {
    final theme = ThemeLoad.parse(
      File('example/${example.themeAsset}').readAsStringSync(),
    ).contract.defaultTheme;
    final document = UiDocument.fromJsonString(File('example/${example.documentAsset}').readAsStringSync());

    // The host own arrow walks the DOCUMENT stack through the controller.
    await tester.pumpWidget(
      MaterialApp(home: recipes.FlowWithOwnBack(document: document, theme: theme, data: backendData)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rewards'), findsOneWidget);
    await tester.tap(find.text('Missions').first);
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget, reason: 'the controller listener repainted the host title');
    expect(find.text('Claim reward'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Rewards'), findsOneWidget);
    expect(find.text('Claim reward'), findsNothing);

    // Interception: the host said "handled", so system "back" does not move the stack.
    var unsaved = true;
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: recipes.drawWithBackGuard(
            document,
            theme,
            backendData,
            hasUnsavedInput: () => unsaved,
            askToDiscard: () => asked += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Missions').first);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(find.text('Claim reward'), findsOneWidget);
    unsaved = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Claim reward'), findsNothing);
  });

  testWidgets('the recipes from the example work, not only compile', (tester) async {
    final theme = ThemeLoad.parse(
      File('example/${example.themeAsset}').readAsStringSync(),
    ).contract.defaultTheme;
    final json = File('example/${example.documentAsset}').readAsStringSync();

    // A document of a newer major: the host shows ITS OWN message.
    final future = json.replaceFirst(RegExp(r'"schemaVersion":\s*"[^"]+"'), '"schemaVersion": "99.0.0"');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: recipes.drawChecked(future, theme, const {}))),
    );
    expect(find.text('Update the app to see this screen.'), findsOneWidget);

    // The same document handed to the renderer as is: the built-in banner uses
    // the host words if it gave them, and English if not.
    final document = UiDocument.fromJsonString(future);
    expect(document.versionVerdict, VersionVerdict.newerMajor);
    await tester.pumpWidget(
      MaterialApp(home: renderDocument(document, theme: theme, data: const {})),
    );
    expect(find.text(const RendererLabels().updateRequired), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: renderDocument(document, theme: theme, data: const {}, labels: recipes.germanLabels),
      ),
    );
    expect(find.text(recipes.germanLabels.updateRequired), findsOneWidget);
    expect(find.byType(ScreenFlow), findsNothing);

    // A document of an OLDER major: updating will not help, so both the recipe and
    // the built-in banner say something neutral, in the host words if it gave them.
    final past = json.replaceFirst(RegExp(r'"schemaVersion":\s*"[^"]+"'), '"schemaVersion": "1.0.0"');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: recipes.drawChecked(past, theme, const {}))),
    );
    expect(find.text('This screen is not available right now.'), findsOneWidget);
    final old = UiDocument.fromJsonString(past);
    expect(old.versionVerdict, VersionVerdict.olderMajor);
    expect(old.versionVerdict.isMajorMismatch, isTrue);
    await tester.pumpWidget(
      MaterialApp(home: renderDocument(old, theme: theme, data: const {})),
    );
    expect(find.text(const RendererLabels().screenUnavailable), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: renderDocument(old, theme: theme, data: const {}, labels: recipes.germanLabels),
      ),
    );
    expect(find.text(recipes.germanLabels.screenUnavailable), findsOneWidget);
    expect(find.text(recipes.germanLabels.updateRequired), findsNothing);

    // Updating with the same document keeps the object already on screen.
    final source = BundledDocumentSource(
      title: 'Bundled copy',
      assetPath: example.documentAsset,
      bundle: bundle,
    );
    final first = await source.load();
    final second = recipes.apply(first, await source.load());
    expect(identical(second.document, first.document), isTrue);

    final contract = ThemeLoad.parse(File('assets/contract/theme.json').readAsStringSync()).contract;
    expect(recipes.pickTheme(contract, Brightness.dark).brightness, Brightness.dark);
    expect(recipes.pickTheme(contract, Brightness.dark, userChoice: 'light').id, 'light');
  });

  test('device locale: ar-EG finds ar, does not guess in reverse', () {
    const table = DocumentLocalization(
      defaultLocale: 'en',
      locales: ['en', 'ar'],
      strings: {
        'ar': {'home/title/content': 'مرحبا'},
      },
    );
    // What the host passes to `renderDocument`: the REQUESTED tag, used to
    // format dates. The translation key comes from `shownLocale`.
    expect(table.localeFor(const [Locale('ar', 'EG')]), 'ar-EG');
    expect(table.shownLocale('ar-EG'), 'ar');
    expect(table.resolve('ar-EG').matched, isTrue);
    expect(directionOfLocale(table.resolve('ar-EG').directionLocale), TextDirection.rtl);
    expect(isRtlLocale('ar-EG'), isTrue);

    const regional = DocumentLocalization(defaultLocale: 'en', locales: ['en', 'ar-EG'], strings: {});
    expect(regional.shownLocale('ar'), 'en');
    expect(regional.resolve('ar').matched, isFalse);
  });

  test('the example does not import from `src/`', () {
    for (final file in _exampleSources()) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:hotlayout_flutter/src/')),
        reason: '${file.path}: the example must see the package the way a consumer sees it',
      );
    }
  });

  test('every ```dart block in the README is a verbatim fragment of a file from example/', () {
    final sources = {
      for (final file in _exampleSources()) file.path: _code(file.readAsStringSync()),
    };
    // The same guard for documentation pages that live outside the repository:
    // HOTLAYOUT_DOCS=/path/a.md:/path/b.md flutter test test/public_api_test.dart
    final extra = Platform.environment['HOTLAYOUT_DOCS'];
    final pages = ['README.md', 'example/README.md', if (extra != null && extra.isNotEmpty) ...extra.split(':')];

    for (final page in pages) {
      final blocks = _dartBlocks(File(page).readAsStringSync()).toList();
      if (page == 'README.md') expect(blocks, isNotEmpty, reason: 'a README without code shows nothing');
      for (final block in blocks) {
        final needle = _code(block);
        expect(
          sources.values.any((source) => _contains(source, needle)),
          isTrue,
          reason:
              '$page: this code is not in example/, move it there or nobody compiles it:\n$block',
        );
      }
    }
  });

  test('the list of public names changes deliberately', () {
    final entry = File('lib/hotlayout_flutter.dart').readAsStringSync();
    final exported = <String>{
      for (final match in RegExp(r"export '[^']+'\s+show\s+([^;]+);").allMatches(entry))
        ...match.group(1)!.split(',').map((name) => name.trim()).where((name) => name.isNotEmpty),
    };
    expect(
      RegExp(r"export '[^']+';").hasMatch(entry),
      isFalse,
      reason: 'an export without `show` opens the whole file from `src/`',
    );
    expect(exported, {
      // document
      'UiDocument', 'ScreenEntry', 'ButtonAction', 'UiNode', 'ScreenPresentationToken',
      // action catalog (9.8.0): what the host receives, the analytics event, the show event and
      // the helper that executes ONLY a verified standard action
      'runStandardAction', 'StandardAction', 'OpenUrlAction', 'DeeplinkAction', 'CloseAction',
      'InvalidActionParam', 'ActionParamProblem', 'TrackEvent', 'ScreenShown', 'ScreenShownCause',
      'SduiTrackCallback', 'SduiScreenShownCallback',
      // versions
      'VersionVerdict', 'kSupportedSchemaVersion', 'kSupportedThemeContractVersion', 'kIconSetVersion',
      // locales
      'DocumentLocalization', 'LocalizedStrings', 'LocaleResolution', 'directionOfLocale', 'isRtlLocale',
      // drawing
      'renderDocument', 'renderScreen', 'ScreenFlow', 'RendererLabels',
      // system "back" and the document stack
      'ScreenFlowController', 'ScreenFlowBackCallback',
      'SduiActionCallback', 'SduiRecordActionCallback', 'SduiValueWrite', 'ScreenScopeRequest', 'ScreenScopeResolver',
      // the host's own actions, routed by type
      'HostActions', 'HostActionCall', 'HostActionHandler', 'HostActionMiss',
      // theme
      'RenderTheme', 'ThemeContract', 'ThemeLoad', 'ThemeLoadStatus', 'kThemeFetchTimeout',
      // document source
      'DocumentSource', 'BundledDocumentSource', 'PublishedDocumentSource', 'DocumentLoad',
      'DocumentLoadStatus', 'DocumentTransport', 'DocumentResponse', 'HttpDocumentTransport',
      'kDocumentFetchTimeout',
    });
  });
}
