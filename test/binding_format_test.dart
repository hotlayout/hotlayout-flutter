import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'support/demo_data.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

/// Format of a bound value (8.20.0) -- a mirror of the builder's `binding-format.test.ts`:
/// the word `date` must mean here the same as there.
///
/// ABOUT THE TIME ZONE. On the web the tests SET the zone; Dart has no such parameter --
/// `toLocal()` takes the machine zone and nothing can replace it. So there are two kinds of
/// instants here, and they must not be confused:
///  * [_wallClock] -- an instant that shows 21:59:59 on 31 October in the MACHINE zone
///    (`localIso`: a string with this zone's offset), so the text on screen
///    is the same in any zone and can be compared literally. Before
///    the 9.4.0 clarification this was a string without a zone -- by the contract it is no longer a date;
///  * [_instant] -- a real instant with `Z`, as a backend sends it. Its text
///    depends on the machine, so it is compared with what `DateFormat` gives over
///    `toLocal()` -- i.e. it checks the "device zone" RULE itself.
final String _wallClock = localIso(DateTime(2026, 10, 31, 21, 59, 59));
const _instant = '2026-10-31T21:59:59.000Z';

/// The [_instant] moment in the machine zone -- what a person sees on their own clock.
final DateTime _instantHere = DateTime.utc(2026, 10, 31, 21, 59, 59).toLocal();

BindableString _bound({String? format, String path = 'offer.endsAt', String fallback = '—'}) =>
    BindableString.parse({'kind': 'binding', 'path': path, 'fallback': fallback, 'format': ?format});

Map<String, Object?> _boundText(String format, {String path = 'offer.endsAt'}) => textNode(
  '',
  extra: {
    'content': {'kind': 'binding', 'path': path, 'fallback': '—', 'format': format},
  },
);

/// A document with two languages: without a localization section the document names no language,
/// and then a different rule is checked -- "device language".
UiDocument _localized(List<Map<String, Object?>> children) => UiDocument.fromJson({
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': 'inline',
  'name': 'Інлайн-документ',
  'initialScreenId': 'inline',
  'screens': [screenEntry('inline', children)],
  'localization': {
    'defaultLocale': 'en',
    'locales': ['en', 'uk'],
    // The document language is the one that has at least one string (9.2.0 clarifies 9.1.0):
    // an empty table would make `uk` only a label in the list.
    'strings': {
      'uk': {'inline/placeholder/content': 'x'},
    },
  },
});

void main() {
  group('format of a bound value -- the rule', () {
    test('date -- year, short month and day; time is not part of it', () {
      expect(formatBoundValue(_wallClock, BindingFormat.date, locale: 'en'), 'Oct 31, 2026');
    });

    test('time -- hours and minutes by the language convention', () {
      // The space before "PM" in CLDR is a narrow no-break one, and which exactly is
      // a matter of the data release, not ours: we compare the composition, not the character.
      expect(
        formatBoundValue(_wallClock, BindingFormat.time, locale: 'en'),
        matches(RegExp(r'^9:59\sPM$')),
      );
      // Ukrainian counts the day in twenty-four hours -- and CLDR knows that, not
      // us. This is also a test of date data: nobody initialised it explicitly, and
      // we ask synchronously.
      expect(formatBoundValue(_wallClock, BindingFormat.time, locale: 'uk'), '21:59');
    });

    test('date and time -- both together', () {
      final shown = formatBoundValue(_wallClock, BindingFormat.dateTime, locale: 'en') ?? '';

      expect(shown, contains('Oct 31, 2026'));
      expect(shown, matches(RegExp(r'9:59\sPM')));
    });

    // The look comes from the LANGUAGE, not the screen: the same format, another month order and name.
    test('the language changes the look without changing the format in the document', () {
      final uk = formatBoundValue(_wallClock, BindingFormat.date, locale: 'uk') ?? '';

      expect(uk, contains('31'));
      expect(uk, contains('2026'));
      expect(uk, isNot(formatBoundValue(_wallClock, BindingFormat.date, locale: 'en')));
    });

    test('a language tag with a region reduces to the language and does not break the format', () {
      // A document names languages freely (`uk-UA`, `pt-BR`), while the CLDR tables in
      // `intl` lie under shorter keys.
      expect(
        formatBoundValue(_wallClock, BindingFormat.time, locale: 'uk-UA'),
        formatBoundValue(_wallClock, BindingFormat.time, locale: 'uk'),
      );
    });

    /*
     * The zone is the DEVICE's: an instant is shown as the person will live it, not as
     * the server recorded it. We compare with `toLocal()` because the test does not
     * choose the machine zone; on a UTC machine this test cannot tell "forgot toLocal" from
     * correct code -- that is a platform limit, and it is named, not hidden.
     */
    test('an instant with a zone is shown in the device zone, not in UTC', () {
      expect(
        formatBoundValue(_instant, BindingFormat.time, locale: 'en'),
        DateFormat.jm('en').format(_instantHere),
      );
      expect(
        formatBoundValue(_instant, BindingFormat.date, locale: 'en'),
        DateFormat.yMMMd('en').format(_instantHere),
      );
      expect(
        formatBoundValue(_instant, BindingFormat.dateTime, locale: 'en'),
        '${DateFormat.yMMMd('en').format(_instantHere)}, ${DateFormat.jm('en').format(_instantHere)}',
      );
    });

    // Policy `unparsableBoundValue: 'render-as-is'`: the format is not applied.
    for (final (name, value) in <(String, Object?)>[
      ('not a date', 'скоро'),
      ('empty string', ''),
      ('number', 1250),
      ('flag', true),
      ('nothing', null),
    ]) {
      test('a value that does not parse ($name) is not subject to the format', () {
        for (final format in BindingFormat.values) {
          // 9.4.0 FLIPPED one row of this table, and only that one: a number under
          // the `number` format is exactly what the format exists for. The other
          // assertions stand as they stood, and new formats fall under them:
          // a number is not a date (`daysUntil`), and an amount without a currency code is not an amount.
          if (value is num && format == BindingFormat.number) {
            expect(formatBoundValue(value, format, locale: 'en'), '1,250');
            continue;
          }
          expect(formatBoundValue(value, format, locale: 'en'), isNull, reason: format.wire);
        }
      });
    }

    test('a language CLDR does not know does not break the format -- the value is shown as is', () {
      expect(formatBoundValue(_wallClock, BindingFormat.date, locale: 'це не тег мови'), isNull);
    });

    test('the format list is closed: an arbitrary template is not a format', () {
      expect(BindingFormat.parse('date'), BindingFormat.date);
      expect(BindingFormat.parse('dateTime'), BindingFormat.dateTime);
      expect(BindingFormat.parse('time'), BindingFormat.time);
      expect(BindingFormat.parse('dd.MM.yyyy'), isNull);
      expect(BindingFormat.parse(null), isNull);
      // A document arrives from the network: anything may stand in place of the word.
      expect(BindingFormat.parse(42), isNull);
    });
  });

  group('format in a binding', () {
    final data = ScreenData({'offer.endsAt': _wallClock});

    test('a binding with a format shows a date, not an ISO string', () {
      expect(_bound(format: 'date').resolve(data, LocalizedStrings.none, 'en'), 'Oct 31, 2026');
    });

    // The main promise of the minor: no existing document changed its look.
    // A "smart" reader that recognises ISO itself would redraw already built screens.
    test('a binding WITHOUT a format shows the string as is', () {
      expect(_bound().resolve(data, LocalizedStrings.none, 'en'), _wallClock);
    });

    // Policy `unknownBindingFormat: 'render-as-is'`: a format from a newer
    // minor does not break parsing and does not hide the value -- and the path with a fallback
    // stay read.
    test('an unknown format does not break parsing: the value is shown as is', () {
      final bound = _bound(format: 'relative');

      expect(bound, isA<BoundString>());
      expect((bound as BoundString).format, isNull);
      expect(bound.resolve(data, LocalizedStrings.none, 'en'), _wallClock);
      expect(bound.resolve(ScreenData.empty, LocalizedStrings.none, 'en'), '—');
    });

    // Policy `unparsableBoundValue: 'render-as-is'`: the backend sent a word ("soon")
    // instead of a date. Neither an empty place nor a fallback -- the value is there.
    test('a value that does not parse as a date is shown as is', () {
      const soon = ScreenData({'offer.endsAt': 'скоро'});

      for (final format in BindingFormat.values) {
        expect(_bound(format: format.wire).resolve(soon, LocalizedStrings.none, 'en'), 'скоро');
      }
    });

    test('a number under a date format stays a number', () {
      // The builder's validator will not let this through, but the document may have been built
      // by something else. `1250` is points, not the year 1250.
      const points = ScreenData({'offer.endsAt': 1250});

      expect(_bound(format: 'date').resolve(points, LocalizedStrings.none, 'en'), '1250');
    });

    // `fallback` is already text typed by a person. Even if it itself looks like a
    // date, it must not be formatted: the manager saw it exactly this way.
    test('fallback is not formatted when there is no data', () {
      final bound = _bound(format: 'date', fallback: '2026-01-01T00:00:00');

      expect(bound.resolve(ScreenData.empty, LocalizedStrings.none, 'en'), '2026-01-01T00:00:00');
    });

    test('a language CLDR does not know leaves the value on screen', () {
      expect(_bound(format: 'date').resolve(data, LocalizedStrings.none, 'це не тег мови'), _wallClock);
    });

    // A choice group value is the option NAME that is compared with rows, not text for
    // a person. A date in its place would match no option.
    test('a choice group option name takes no format', () {
      final doc = docWith([
        choiceGroupNode(
          [optionNode('Варіант', optionValue: 'a')],
          value: const {'kind': 'binding', 'path': 'offer.endsAt', 'fallback': '', 'format': 'date'},
        ),
      ]);
      final group = flattenDocument(doc).whereType<ChoiceGroupNode>().single;

      expect(group.value.resolve(data, LocalizedStrings.none, 'en'), _wallClock);
    });
  });

  group('format on screen', () {
    final data = {'offer.endsAt': _wallClock};

    /// The DEVICE language for the duration of one test.
    void deviceLocale(WidgetTester tester, Locale locale) {
      tester.platformDispatcher.localeTestValue = locale;
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    }

    testWidgets('three formats give three different labels', (tester) async {
      await pumpDocument(
        tester,
        _localized([
          {..._boundText('date'), 'id': 'd'},
          {..._boundText('time'), 'id': 't'},
          {..._boundText('dateTime'), 'id': 'dt'},
        ]),
        data: data,
        locale: 'en',
      );

      expect(find.text('Oct 31, 2026'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^9:59\sPM$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Oct 31, 2026.*9:59\sPM$')), findsOneWidget);
      expect(find.text(_wallClock), findsNothing);
    });

    // The language is the same one that selects translations: a date in a language that appears nowhere else
    // on screen would look like a data error.
    testWidgets('the date language is the one the document is shown in, not the device language', (tester) async {
      deviceLocale(tester, const Locale('en'));
      final doc = _localized([_boundText('time')]);

      await pumpDocument(tester, doc, data: data, locale: 'uk');
      expect(find.text('21:59'), findsOneWidget);

      // No language was requested -- the document is shown in the default language.
      deviceLocale(tester, const Locale('uk'));
      await pumpDocument(tester, doc, data: data);
      expect(find.textContaining(RegExp(r'^9:59\sPM$')), findsOneWidget);

      // The document has no language -- texts fell back to the default language
      // (`missingTranslation`), and the date must follow them, not the request.
      await pumpDocument(tester, doc, data: data, locale: 'de');
      expect(find.textContaining(RegExp(r'^9:59\sPM$')), findsOneWidget);
    });

    testWidgets('a document without localization names no language -- then the device language', (tester) async {
      deviceLocale(tester, const Locale('uk', 'UA'));
      await pumpDocument(tester, docWith([_boundText('time')]), data: data);
      expect(find.text('21:59'), findsOneWidget);

      deviceLocale(tester, const Locale('en', 'US'));
      await pumpDocument(tester, docWith([_boundText('time')]), data: data);
      expect(find.textContaining(RegExp(r'^9:59\sPM$')), findsOneWidget);
    });

    // The format lives in the BINDING, not in the `Text` widget: it must work
    // everywhere a binding can be, including nested slots.
    testWidgets('a nested binding is formatted too: ListTile.trailing and AppBar.subtitle', (
      tester,
    ) async {
      await pumpDocument(
        tester,
        _localized([
          {
            ...appBarNode('Offer'),
            'props': {
              ...appBarNode('Offer')['props']! as Map<String, Object?>,
              'subtitle': {
                'kind': 'binding',
                'path': 'offer.endsAt',
                'fallback': '—',
                'format': 'date',
              },
            },
          },
          listTileNode(
            'Ends at',
            trailing: {
              'kind': 'text',
              'text': {
                'kind': 'binding',
                'path': 'offer.endsAt',
                'fallback': '—',
                'format': 'time',
              },
            },
          ),
        ]),
        data: data,
        locale: 'uk',
      );

      expect(find.text('21:59'), findsOneWidget);
      expect(find.text(formatBoundValue(_wallClock, BindingFormat.date, locale: 'uk')!), findsOneWidget);
      expect(find.text(_wallClock), findsNothing);
    });

    testWidgets('without data the screen shows the fallback, not a formatted void', (tester) async {
      await pumpDocument(tester, _localized([_boundText('dateTime')]), locale: 'en');

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('an unknown format and an unparsable value leave the value on screen', (
      tester,
    ) async {
      await pumpDocument(
        tester,
        _localized([
          {..._boundText('relative'), 'id': 'future'},
          {..._boundText('date', path: 'offer.title'), 'id': 'broken'},
        ]),
        data: {...data, 'offer.title': 'скоро'},
        locale: 'en',
      );

      expect(find.text(_wallClock), findsOneWidget);
      expect(find.text('скоро'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    /*
     * Contract fixture: on the details screen the node `task-completed-at` carries
     * `format: "dateTime"` and is visible only for a completed task. We compare with
     * `DateFormat` over `toLocal()`: the sample in the data is a real instant with a zone.
     */
    testWidgets('fixture tasks-flow: the completion date is shown as a date', (tester) async {
      deviceLocale(tester, const Locale('en', 'US'));
      final doc = loadFixture('tasks-flow-screens');
      final completedAt = sampleScreenData['task.completedAt']! as String;
      final at = DateTime.parse(completedAt).toLocal();
      final expected = '${DateFormat.yMMMd('en-US').format(at)}, ${DateFormat.jm('en-US').format(at)}';

      // The details read the ROW record (9.2.0), so we tap the row of the completed task:
      // `task.completed` is `true` in its record, and the completion date is visible. This used to be
      // provided by overriding the sample in the document data -- the record is stronger.
      await pumpDocument(tester, doc, data: sampleScreenData);
      await tester.ensureVisible(find.text('Set up a recurring payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up a recurring payment'));
      await tester.pumpAndSettle();

      expect(find.text(expected), findsOneWidget);
      expect(find.text(completedAt), findsNothing);
    });
  });

  test('dateTime in English -- "Oct 31, 2026, 2:00 PM": a comma between date and time (CLDR, as React)', () {
    final at = DateTime(2026, 10, 31, 14, 0);
    final shown = formatBoundValue(localIso(at), BindingFormat.dateTime, locale: 'en') ?? '';
    // Before AM/PM the newer CLDR data has a narrow no-break space, hence `\s`.
    expect(shown, matches(RegExp(r'^Oct 31, 2026, 2:00\sPM$')));
  });
}
