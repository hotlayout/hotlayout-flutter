/// The three showcase apps (Obsidian, Sunny, Orbit): documents, themes and the data a host would
/// answer with, bundled with the demo. They are the same documents the web package draws on the
/// product site, so the two readers can be compared screen by screen.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// One showcase app: where its document, theme and data live in the demo's assets.
class ShowcaseApp {
  const ShowcaseApp({
    required this.id,
    required this.title,
    required this.dataAsset,
  });

  /// The value of `--dart-define=fixture=…`.
  final String id;
  final String title;

  /// Data answers: `{now, en|uk|ar: {data, collections}}`, or for Orbit `{now, scenarios: {…}}`.
  final String dataAsset;

  String get documentAsset => 'assets/showcase/$id/document.json';
  String get themeAsset => 'assets/showcase/$id/theme.json';
}

const List<ShowcaseApp> kShowcaseApps = [
  ShowcaseApp(
    id: 'obsidian',
    title: 'Obsidian',
    dataAsset: 'assets/showcase/obsidian/data.json',
  ),
  ShowcaseApp(
    id: 'sunny',
    title: 'Sunny',
    dataAsset: 'assets/showcase/sunny/data.json',
  ),
  ShowcaseApp(
    id: 'orbit',
    title: 'Orbit',
    dataAsset: 'assets/showcase/orbit/sample-data.json',
  ),
];

/// The showcase app that owns an asset path, or `null`.
ShowcaseApp? showcaseByDocumentAsset(String? assetPath) {
  for (final app in kShowcaseApps) {
    if (app.documentAsset == assetPath) return app;
  }
  return null;
}

ShowcaseApp? showcaseById(String id) {
  for (final app in kShowcaseApps) {
    if (app.id == id) return app;
  }
  return null;
}

/// The host's answers for one app: data (and the lists of records) per language, and the moment
/// the samples are imagined at.
class ShowcaseData {
  const ShowcaseData({required this.now, required this.answers});

  final DateTime now;

  /// Language (or Orbit scenario) -> data scope, lists of records already merged in: the reader
  /// reads a list from the data map by the path of its collection.
  final Map<String, Map<String, Object?>> answers;

  /// The answer for a device locale (`ar-EG` -> `ar`); an unknown language gets the first answer.
  Map<String, Object?> forLocale(
    String? locale, {
    String scenario = 'default',
  }) {
    if (answers.containsKey(scenario)) return answers[scenario]!;
    final language = (locale ?? 'en').split(RegExp('[-_]')).first;
    return answers[language] ?? answers['en'] ?? answers.values.first;
  }

  static Future<ShowcaseData> load(
    ShowcaseApp app, {
    AssetBundle? bundle,
  }) async {
    final raw =
        jsonDecode(await (bundle ?? rootBundle).loadString(app.dataAsset))
            as Map<String, Object?>;
    final now = DateTime.parse(raw['now']! as String);
    Map<String, Object?> merge(Map<String, Object?> answer) => {
      ...(answer['data']! as Map<String, Object?>),
      ...(answer['collections']! as Map<String, Object?>),
    };
    final scenarios = raw['scenarios'];
    final answers = <String, Map<String, Object?>>{};
    if (scenarios is Map<String, Object?>) {
      for (final entry in scenarios.entries) {
        answers[entry.key] = merge(entry.value! as Map<String, Object?>);
      }
    } else {
      for (final entry in raw.entries) {
        if (entry.key != 'now') {
          answers[entry.key] = merge(entry.value! as Map<String, Object?>);
        }
      }
    }
    return ShowcaseData(now: now, answers: answers);
  }
}

/// The site the showcase pictures live on. Picture addresses in the documents are either absolute
/// on it or relative to it.
const String kShowcaseSite = 'https://hotlayout.com';

/// The host's decision about picture addresses (`resolveImageUrl`): only the product site's own
/// pictures are fetched; a site-relative address is resolved against it. The package's default
/// rule stays untouched for every other app.
String? showcaseImageUrl(String url) {
  if (url.startsWith('data:image/')) return url;
  if (url.startsWith('/') && !url.startsWith('//')) return '$kShowcaseSite$url';
  if (url.startsWith('$kShowcaseSite/')) return url;
  return null;
}
