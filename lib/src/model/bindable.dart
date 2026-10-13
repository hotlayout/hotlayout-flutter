import '../data/screen_data.dart';
import 'binding_format.dart';
import 'date_parts.dart';
import 'locale_resolve.dart';
import 'localization.dart';
import 'text_template.dart';
import 'tokens.dart';

/// A string of the document: written into it, taken from data, or composed of
/// places (`kind: 'template'`, 9.4.0).
///
/// Told apart strictly by the `kind` field; strings such as `"{{task.title}}"`
/// are never parsed. That is why the union is discriminated. A template does
/// not change this: `{name}` in it is not a data path but the NAME of a value
/// declared next to it as a structure.
sealed class BindableString {
  const BindableString();

  /// [key] is the place of this text in the document
  /// (`<screenId>/<nodeId>/<path>`), if the field is translatable at all and
  /// the document has translations at all. `null` is the common case and
  /// means "draw the text as written".
  ///
  /// [formats] says whether this is TEXT FOR A PERSON: whether to read
  /// `binding.format` (8.20.0) and whether a template may occur here (9.4.0).
  /// It is `false` only where the value is a NAME that gets compared rather
  /// than text that gets read (`ChoiceGroup.value`): a date in place of an
  /// option name would match no string, and the schema allows no template in
  /// strings that have a length limit.
  static BindableString parse(
    Object? raw, {
    String fallback = '',
    String? key,
    bool formats = true,
  }) {
    if (raw is Map) {
      final kind = raw['kind'];
      if (kind == 'literal') {
        return LiteralString('${raw['value'] ?? fallback}', key: key);
      }
      // A binding deliberately has no key. Bound text arrives from DATA at
      // runtime, so there is nothing in the document to translate; the data
      // source itself would have to be translated. This is the localization
      // boundary, and the builder draws it the same way: it collects only
      // literals as translatable and calls a key whose field became a binding
      // orphaned.
      final bound = BoundString.tryParse(raw, fallback: fallback, formats: formats);
      if (bound != null) return bound;
      if (kind == 'template' && formats) return TemplateString.parse(raw, key: key);
    }
    // Unknown kind or a malformed shape: an empty literal, which is the policy
    // row `unknownStringKind: 'render-empty'`. One bad prop does not take the
    // node down, and a literal "{done} / {total}" on the user's screen would be
    // worse than an empty place.
    return LiteralString(fallback);
  }

  /// [strings] are the translations of the CHOSEN language. By default there
  /// are none, and resolving then behaves as if the document had no
  /// localization.
  ///
  /// [locale] is the FORMAT locale: the language the document is SHOWN in;
  /// only a binding with `format` (8.20.0) needs it. It is a separate
  /// parameter rather than `strings.locale`: the latter says "which table we
  /// translate with" and is empty for the default language, yet a date still
  /// has to be formatted.
  ///
  /// [now] is the reader's "now" for `daysUntil` (9.4.0, `readerClock`).
  /// `null` means the device clock at the moment of the call. The renderer
  /// reads the clock once per screen and passes it in, so all strings of one
  /// frame count from the same instant.
  String resolve(
    ScreenData data, [
    LocalizedStrings strings = LocalizedStrings.none,
    String? locale,
    DateTime? now,
  ]);
}

final class LiteralString extends BindableString {
  const LiteralString(this.value, {this.key});

  /// The text in the default language, i.e. what the document itself says.
  final String value;

  /// The place of this text in the document, or `null` if there is nothing to translate.
  final String? key;

  /// **The whole `missingTranslation: 'fall-back-to-default-locale'` policy is
  /// the single `??` below.** No key in the table (partial translation), no
  /// table (default language), no language in the document, no localization
  /// section at all: all four cases give the LITERAL.
  ///
  /// There is deliberately no language chain. If `kk` fell back to `en` and
  /// `en` to the literal, a screen would come out partly Kazakh, partly
  /// English, partly Russian, and no language would be complete. One
  /// substitution for the whole screen is predictable; a chain is not.
  @override
  String resolve(
    ScreenData data, [
    LocalizedStrings strings = LocalizedStrings.none,
    String? locale,
    DateTime? now,
  ]) => strings[key] ?? value;
}

final class BoundString extends BindableString {
  const BoundString(
    this.path,
    this.fallback, {
    this.format,
    this.currency,
    this.forText = true,
    this.look = MoneyLook.none,
    this.dateParts,
  });

  /// The binding from an object `{kind: 'binding', path, fallback, format?,
  /// currency?, currencyDisplay?, currencyPosition?, sign?}`, or `null` if it is not a binding. ONE parser serves both a
  /// standalone string and a template value: the contract says it is the same
  /// binding, and a second copy of the parser would drop a field at the first
  /// minor version.
  static BoundString? tryParse(Map<Object?, Object?> raw, {String fallback = '', bool formats = true}) {
    final path = raw['path'];
    if (raw['kind'] != 'binding' || path is! String) return null;
    final currency = raw['currency'];
    return BoundString(
      path,
      '${raw['fallback'] ?? fallback}',
      // An unknown format gives `null`, not a parse error: policy
      // `unknownBindingFormat: 'render-as-is'`.
      format: formats ? BindingFormat.parse(raw['format']) : null,
      // The shape of the code is not checked here: a code of the wrong shape
      // means "the format did not apply" (`missingCurrencyCode`), and
      // `formatBoundValue` is what says so.
      currency: formats && currency is String ? currency : null,
      forText: formats,
      // 9.19.0: the three money fields, each read only on a format that reads it.
      look: formats ? MoneyLook.read(raw, BindingFormat.parse(raw['format'])) : MoneyLook.none,
      // 9.19.0: the parts of a date, read only beside the `date` format.
      dateParts: formats ? DateParts.readFor(BindingFormat.parse(raw['format']), raw['dateParts']) : null,
    );
  }

  final String path;
  final String fallback;

  /// HOW to show the value (8.20.0), or `null` for "as is". Also `null` for a
  /// format this code does not know.
  final BindingFormat? format;

  /// The currency code: the neighbouring field of the `currency` format
  /// (9.4.0). It means nothing without that format.
  final String? currency;

  /// The currency sign, its place and the number sign (9.19.0, `x-money`); [MoneyLook.none] when no
  /// field is readable on [format].
  final MoneyLook look;

  /// Which parts of a date to show (9.19.0, `x-dateParts`); `null` is the date as before.
  final DateParts? dateParts;

  /// Whether this is TEXT FOR A PERSON. `false` means a name that gets compared
  /// (`ChoiceGroup.value`): the rule "an empty string is no value"
  /// (`emptyBoundString`) is about a string that becomes text and leaves an
  /// option name alone.
  final bool forText;

  /// Whether there is anything at the path to SHOW as text: a string, a number
  /// or a flag. No key, `null`, a map, a list and an EMPTY STRING all mean "no
  /// value", and the fallback text is shown. A string of only spaces is a value.
  ///
  /// The order of data LAYERS is unchanged: `""` in a row record still shadows
  /// the same field in a lower layer ([ScreenData.lookup] does not know this
  /// rule), and yields to the fallback text only here, as text.
  bool _showable(Object? value) =>
      (value is String && (value.isNotEmpty || !forText)) || value is num || value is bool;

  @override
  String resolve(
    ScreenData data, [
    LocalizedStrings strings = LocalizedStrings.none,
    String? locale,
    DateTime? now,
  ]) => pieces(data, strings, locale, now).map((piece) => piece.text).join();

  /// The value as PIECES of one place (9.19.0, `x-money.parts`): a formatted number or amount is up to
  /// five pieces with the part each belongs to; the fallback text, a value shown as it is, a date and
  /// `daysUntil` are one piece without a part. The pieces joined are what [resolve] returns.
  List<AmountPiece> pieces(
    ScreenData data, [
    LocalizedStrings strings = LocalizedStrings.none,
    String? locale,
    DateTime? now,
  ]) {
    final value = data.lookup(path);
    // Contract rule: no data at the path means the document's fallback. The
    // format does NOT touch it: it is already text typed by a person.
    //
    // "No data" also covers a value that is neither a string, a number nor a
    // flag: a map or a list is not text, and `Instance of …` or `{value: 3}`
    // in the middle of a sentence is worse than the fallback text. An empty
    // string is "no value" too.
    if (!_showable(value)) return [(text: fallback, part: null)];

    final format = this.format;
    if (format != null) {
      // `null` means "the format did not apply" (the value is not a date or a
      // number, the language is not in CLDR, the currency code is missing).
      // Policy `unparsableBoundValue: 'render-as-is'`: the value then takes the
      // same path as without a format.
      final shown = formatBoundPieces(
        value,
        format,
        locale: locale,
        currency: currency,
        now: now ?? DateTime.now(),
        look: look,
        dateParts: dateParts,
        // The composed form is isolated in a text written right to left. The direction is the one of
        // the language the text is SHOWN in (`directionFollows`).
        rtl: look.composed && isRtlLanguageTag(strings.shownLanguage(locale)),
      );
      if (shown != null) return shown;
    }
    return [(text: stringify(value!), part: null)];
  }

  /// The number this value is RIGHT NOW: the one a template's plural agrees
  /// with (`x-template.countableFormats`); `null` means there is no number.
  ///
  /// When there is no data and the FALLBACK TEXT is shown, the fallback gives
  /// the number if it looks like a decimal number
  /// (`pluralNumberWithoutData: 'numeric-fallback-else-other'`): "0 points",
  /// not "0 point". The value's format does not matter here: a fallback "3"
  /// under `daysUntil` is 3. If data EXISTS but is not a number ("many"), the
  /// fallback text is not shown and gives no number.
  num? numberIn(ScreenData data, DateTime now) {
    final value = data.lookup(path);
    if (_showable(value)) return numericBoundValue(value, format, now: now);
    if (!_numericFallback.hasMatch(fallback)) return null;
    return numericBoundValue(num.tryParse(fallback), null, now: now);
  }

  /// `x-template.pluralNumber.fallbackPattern`.
  static const String numericFallbackPattern = r'^-?\d+(\.\d+)?$';
  static final RegExp _numericFallback = RegExp(numericFallbackPattern);

  /// The value "as is": a string as a string, a flag as `true` / `false`, a
  /// number as its shortest decimal form without separators, and a whole
  /// number without a fractional part.
  ///
  /// `3.0` from JSON is a `double` in Dart and `toString()` would give "3.0",
  /// while the web writes "3". The tail is cut from the STRING rather than via
  /// `toInt()`: beyond the int64 range that saturates silently, and 1e300 would
  /// become 9223372036854775807.
  static String stringify(Object value) {
    if (value is! double) return value.toString();
    if (value == 0) return '0';
    final text = value.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
}

/// A template string (9.4.0): a translatable string with named places
/// `{name}` and a map of values. The rule is in `text_template.dart`.
final class TemplateString extends BindableString {
  const TemplateString(this.template, this.values, {this.key});

  /// Parses `{kind: 'template', template, values}`. Never throws: the document
  /// comes from the network, and the schema limits (eight values, the name
  /// pattern) are kept by the producer, not by the reader.
  ///
  ///  * `template` is not a string: an empty string;
  ///  * `values` is not a map: no values, all places are literal;
  ///  * a key is not a string: the entry is skipped. A name that does NOT match
  ///    the name pattern stays in the map and means nothing: a place `{name}`
  ///    is looked up with the same pattern, so the string cannot reach such a
  ///    value;
  ///  * a value of an unknown kind is declared but empty
  ///    ([UnknownTemplateValue]).
  static TemplateString parse(Map<Object?, Object?> raw, {String? key}) {
    final template = raw['template'];
    final values = <String, TemplateValue>{};
    if (raw['values'] case final Map<Object?, Object?> table) {
      for (final entry in table.entries) {
        final name = entry.key;
        if (name is String) values[name] = TemplateValue.parse(entry.value);
      }
    }
    return TemplateString(template is String ? template : '', values, key: key);
  }

  /// The string in the source language: what the document says.
  final String template;

  /// Values by name. Read only through `containsKey` / `[]`, i.e. own keys:
  /// `{constructor}` in a string is not a value.
  final Map<String, TemplateValue> values;

  /// The place of this text in the document, or `null` when there are no
  /// translations. The string is translated by `<place>.template`, a plural
  /// form by `<place>.values.<name>.forms.<category>`
  /// (`x-template.translationKeys`).
  final String? key;

  @override
  String resolve(
    ScreenData data, [
    LocalizedStrings strings = LocalizedStrings.none,
    String? locale,
    DateTime? now,
  ]) => runs(data, strings, locale, now).map((run) => run.text).join();

  /// The runs of the string in the current language, in LOGICAL order (9.6.0):
  /// exactly the text [resolve] gives, split by place. There are no empty runs.
  List<TemplateRun> runs(
    ScreenData data, [
    LocalizedStrings strings = LocalizedStrings.none,
    String? locale,
    DateTime? now,
  ]) {
    final place = key;
    // The text: the current language's translation, else the document's string
    // (`missingTranslation`, as for a literal).
    final text = (place == null ? null : strings['$place.template']) ?? template;
    // One instant for the whole string: a number of days and the word "days"
    // next to it must not be counted from different "now" values.
    final moment = now ?? DateTime.now();

    return templateRuns(
      text,
      declared: values.containsKey,
      textOf: (name) => switch (values[name]) {
        // A value from data becomes text EXACTLY like a standalone binding; with
        // no data, this value's fallback text appears and the sentence stays.
        TemplateBinding(:final binding) => binding.resolve(data, strings, locale, moment),
        final TemplatePlural plural => _pluralText(name, plural, data, strings, moment),
        // A word (9.6.0): its translation in the current language by its own
        // key, else the document's text; the rest of the sentence stays translated.
        final TemplateWord word => (place == null ? null : strings['$place.values.$name.text']) ?? word.text,
        UnknownTemplateValue() || null => '',
      },
    );
  }

  /// [runs] where a formatted number or amount comes in its pieces (9.19.0, `x-money.parts`): every
  /// run carries the part of the number it is, so a style that names `fraction` or `currency` can find
  /// it. Runs of one place that differ only in having no part stay separate here; merging is the rule
  /// of the styles (`spanPartRuns`).
  List<PartedRun> partedRuns(
    ScreenData data, [
    LocalizedStrings strings = LocalizedStrings.none,
    String? locale,
    DateTime? now,
  ]) {
    final place = key;
    // The text: the current language's translation, else the document's string
    // (`missingTranslation`, as for a literal).
    final text = (place == null ? null : strings['$place.template']) ?? template;
    // One instant for the whole string: a number of days and the word "days"
    // next to it must not be counted from different "now" values.
    final moment = now ?? DateTime.now();

    return partedTemplateRuns(
      text,
      declared: values.containsKey,
      piecesOf: (name) => switch (values[name]) {
        // A value from data becomes text EXACTLY like a standalone binding; with
        // no data, this value's fallback text appears and the sentence stays.
        TemplateBinding(:final binding) => binding.pieces(data, strings, locale, moment),
        final TemplatePlural plural => [(text: _pluralText(name, plural, data, strings, moment), part: null)],
        // A word (9.6.0): its translation in the current language by its own
        // key, else the document's text; the rest of the sentence stays translated.
        final TemplateWord word => [
          (text: (place == null ? null : strings['$place.values.$name.text']) ?? word.text, part: null),
        ],
        UnknownTemplateValue() || null => const [],
      },
    );
  }

  String _pluralText(
    String name,
    TemplatePlural plural,
    ScreenData data,
    LocalizedStrings strings,
    DateTime now,
  ) {
    // The NUMBER comes from the value named by `of`, and only a binding of THIS
    // SAME template counts. An `of` pointing at itself, at another plural or at
    // nothing gives no number (`pluralWithoutNumber`), so there is no recursion
    // by construction.
    final count = switch (values[plural.of]) {
      TemplateBinding(:final binding) => binding.numberIn(data, now),
      _ => null,
    };

    // The plural LANGUAGE is the language of the SHOWN forms (`pluralLanguage`).
    // If the `other` form is translated into the current language, the forms
    // come from the table with that language's rules. If not, the document's
    // forms are used with the SOURCE language's rules, even when other forms
    // are translated: a Ukrainian rule over English forms would give "21 day".
    // The two must not be mixed.
    final place = key;
    final prefix = place == null ? null : '$place.values.$name.forms.';
    if (prefix != null && strings['$prefix$kPluralOther'] != null) {
      return pluralFormFor(
        count,
        {
          for (final category in kPluralCategories)
            category: ?strings['$prefix$category'],
        },
        strings.locale,
      );
    }
    // A document without localization names no language at all: `sourceLocale`
    // is then `null` and the answer is `other` (`pluralWithoutLanguage`).
    return pluralFormFor(count, plural.forms, strings.sourceLocale);
  }
}

/// A template value: a data binding, a word that agrees with a number, or a
/// word from the document.
sealed class TemplateValue {
  const TemplateValue();

  static TemplateValue parse(Object? raw) {
    if (raw is Map) {
      final bound = BoundString.tryParse(raw);
      if (bound != null) return TemplateBinding(bound);
      // A word (9.6.0): text that is not from data. If `text` is not a string
      // the value is of an unknown kind (an empty place without braces).
      if (raw['kind'] == 'text') {
        final text = raw['text'];
        return text is String ? TemplateWord(text) : const UnknownTemplateValue();
      }
      if (raw['kind'] == 'plural') {
        final of = raw['of'];
        final forms = raw['forms'];
        // A plural without `forms.other` is a known kind of the wrong shape:
        // an empty place (`unknownTemplateValueKind`), not whichever other
        // form happens to exist.
        if (forms is! Map || forms[kPluralOther] is! String) return const UnknownTemplateValue();
        return TemplatePlural(of is String ? of : '', {
          // Only the six categories and only strings: a form key from the
          // network can be anything, and nothing would read it.
          for (final category in kPluralCategories)
              if (forms[category] case final String form) category: form,
        });
      }
    }
    return const UnknownTemplateValue();
  }
}

/// `{kind: 'binding', path, fallback, format?, currency?}`: the same binding as
/// a standalone string.
final class TemplateBinding extends TemplateValue {
  const TemplateBinding(this.binding);

  final BoundString binding;
}

/// `{kind: 'plural', of, forms}`: a word next to the number of the value [of].
final class TemplatePlural extends TemplateValue {
  const TemplatePlural(this.of, this.forms);

  /// The name of a value of the same template whose number the word agrees with.
  final String of;

  /// Forms in the source language by CLDR category. By the schema `other` is
  /// always present; without it the reader shows an empty place.
  final Map<String, String> forms;
}

/// `{kind: 'text', text}` (9.6.0): a word with its own name, so composed text
/// can style it without making it data. Translated by the key
/// `<place>.values.<name>.text`.
final class TemplateWord extends TemplateValue {
  const TemplateWord(this.text);

  final String text;
}

/// A value this code does not read (`unknownTemplateValueKind:
/// 'render-empty'`): a kind from a newer minor version, a non-object, or a
/// known kind of the wrong shape (a binding without `path`, a plural without
/// `forms.other`). The place is DECLARED, so neither braces nor text appear on
/// screen; the sentence stays. A plural whose `of` leads here uses `other`.
final class UnknownTemplateValue extends TemplateValue {
  const UnknownTemplateValue();
}

/// A number that is either written into the document or comes from data.
sealed class BindableNumber {
  const BindableNumber();

  static BindableNumber parse(Object? raw, {double fallback = 0}) {
    if (raw is Map) {
      final kind = raw['kind'];
      if (kind == 'literal' && raw['value'] is num) {
        return LiteralNumber((raw['value'] as num).toDouble());
      }
      if (kind == 'binding' && raw['path'] is String) {
        return BoundNumber(
          raw['path'] as String,
          (raw['fallback'] as num?)?.toDouble() ?? fallback,
        );
      }
    }
    return LiteralNumber(fallback);
  }

  double resolve(ScreenData data);
}

final class LiteralNumber extends BindableNumber {
  const LiteralNumber(this.value);

  final double value;

  @override
  double resolve(ScreenData data) => value;
}

final class BoundNumber extends BindableNumber {
  const BoundNumber(this.path, this.fallback);

  final String path;
  final double fallback;

  @override
  double resolve(ScreenData data) {
    final value = data.lookup(path);
    return switch (value) {
      final num n => n.toDouble(),
      // Backends often send numbers as strings; that is no reason to use the fallback.
      final String s => double.tryParse(s) ?? fallback,
      _ => fallback,
    };
  }
}

/// The source of an image in the DOCUMENT: a built-in asset token, an external
/// URL, or a data binding.
///
/// The third branch (8.1.0) is what lets a screen's data scope give the right
/// title and numbers together with the right photo; otherwise the image URL
/// would stay fixed in the document. `fallback` here is an ASSET token, not a
/// URL: there is no such thing as a fallback URL (no one knows a second server
/// with the same photo), while a placeholder always exists.
sealed class ImageSource {
  const ImageSource();

  static ImageSource parse(Object? raw) {
    if (raw is Map) {
      final kind = raw['kind'];
      if (kind == 'asset') return AssetImageSource(AssetToken.parse(raw['asset']));
      if (kind == 'url' && raw['url'] is String) {
        return UrlImageSource(raw['url'] as String);
      }
      if (kind == 'binding' && raw['path'] is String) {
        return BoundImageSource(raw['path'] as String, AssetToken.parse(raw['fallback']));
      }
    }
    return const AssetImageSource(AssetToken.placeholder);
  }

  /// What to draw RIGHT NOW, given this data.
  ResolvedImage resolve(ScreenData data);
}

final class AssetImageSource extends ImageSource {
  const AssetImageSource(this.asset);

  final AssetToken asset;

  @override
  ResolvedImage resolve(ScreenData data) => ImageAsset(asset);
}

final class UrlImageSource extends ImageSource {
  const UrlImageSource(this.url);

  final String url;

  @override
  ResolvedImage resolve(ScreenData data) => ImageUrl(url);
}

/// `{kind: 'binding', path, fallback: AssetToken}`: the URL comes from data.
final class BoundImageSource extends ImageSource {
  const BoundImageSource(this.path, this.fallback);

  final String path;

  /// The placeholder for "no data". Not an empty place: an empty place reads as
  /// "all is well", while a placeholder makes it visible that the photo did not arrive.
  final AssetToken fallback;

  /// Same rule as [BoundString]: no data at the path means the document's
  /// `fallback`. An empty string is "no data" too: `Image.network('')` is not
  /// an image but a network error.
  @override
  ResolvedImage resolve(ScreenData data) {
    final value = data.lookup(path);
    if (value is String && value.isNotEmpty) return ImageUrl(value);
    return ImageAsset(fallback);
  }
}

/// An image that is ready to draw.
///
/// A separate type rather than [ImageSource], for the compiler's sake: there is
/// no binding here BY CONSTRUCTION, so the renderer cannot grow a branch for
/// "what if the path is empty"; that question has already been answered, once.
sealed class ResolvedImage {
  const ResolvedImage();
}

final class ImageAsset extends ResolvedImage {
  const ImageAsset(this.asset);

  final AssetToken asset;
}

final class ImageUrl extends ResolvedImage {
  const ImageUrl(this.url);

  final String url;
}
