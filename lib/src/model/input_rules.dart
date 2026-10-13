import '../data/screen_data.dart';
import 'layout_rules.dart';
import 'shown_text.dart';
import 'visibility.dart';

/// INPUT FIELDS (schema 9.13.0): `TextField`, `Switch`, `Checkbox`.
///
/// Mirror of the builder's reference implementation (`input-rules.ts`) and of
/// the `x-style.layout.inputs` block of the artifact. Everything the three
/// readers must do IDENTICALLY and that could be read two ways is here: the
/// shape of a value read from data, what is written and when, the length limit,
/// the keyboard action button, keyboard-kind mappings, geometry. The case table
/// (`input-cases.json`) is run by `input_cases_test.dart`, through the formulas
/// here and through the real widget.
///
/// There is no second write mechanism: a field's value is a data dictionary
/// path, reading goes through the data layers (record, session, host scope,
/// data), and writing goes to the reader's session and to the host (`onWrite`),
/// exactly like a choice in a `ChoiceGroup`.

// ───────────────────────────── field value ─────────────────────────────

/// The path of a field (`inputPathOf`, `pathCases`): an object with
/// `kind: 'binding'` and a non-empty string `path`. Extra keys do NOT matter: a
/// minor version that adds a field to the value must not turn writing off.
/// Anything else means "no path" (`inputWithoutValue`, `unreadableInputValue`):
/// the field works locally.
String? inputPathOf(Object? value) {
  if (value is! Map || value['kind'] != 'binding') return null;
  final path = value['path'];
  return path is String && path.isNotEmpty ? path : null;
}

/// The field text from a layer value: a string as is, EVERYTHING else (absent,
/// number, flag, object) is an empty field (`inputValueOfOtherType`). An empty
/// string is an empty field too: a field has no fallback text (`inputEmptyString`).
String readInputText(Object? value) => value is String ? value : '';

/// The flag from a layer value: on only for `true` (`"true"` and `1` are off).
bool readInputFlag(Object? value) => value == true;

/// Whether a document's `required` / `requiresFilled` is honoured: only the
/// literal `true`. Anything else (`false`, a string, a number from a document of
/// a newer minor version) means "no" (`unreadableRequired`,
/// `unreadableRequiresFilled`).
bool isRequiredProp(Object? value) => value == true;

/// The fallback text of a binding: the binding's own `fallback` string, if any.
String? fallbackOfBinding(Object? value) {
  if (value is! Map || value['kind'] != 'binding') return null;
  final fallback = value['fallback'];
  return fallback is String ? fallback : null;
}

// ───────────────────────────── limits ─────────────────────────────

/// The upper bound of `maxLength` in the schema; the schema rejects a larger
/// value, the reader does not (a larger limit simply cuts nothing).
const int kTextFieldMaxLengthLimit = 10000;
const int kTextFieldMinLines = 1;
const int kTextFieldMaxLines = 8;
const int kTextFieldDefaultLines = 1;

/// A whole number (`2.0` in JSON is whole too, like `Number.isInteger` in the
/// reference implementation); NaN, infinity and a fraction are not.
bool _isWhole(num value) => !value.isNaN && !value.isInfinite && value == value.truncateToDouble();

/// Cuts typed text to the limit in Unicode CODE POINTS (`runes`).
///
/// Flutter's platform `maxLength` counts graphemes and the web counts UTF-16
/// units; the code point is the only unit all three readers count the same way.
/// Cutting never splits a surrogate pair (`runes` yields it as one number). A
/// limit that is not a whole number above zero means no limit (`inputMaxLength`).
String clampInputText(String text, Object? maxLength) {
  if (maxLength is! num || !_isWhole(maxLength)) return text;
  final limit = maxLength.toInt();
  if (limit < 1) return text;
  final runes = text.runes;
  if (runes.length <= limit) return text;
  return String.fromCharCodes(runes.take(limit));
}

/// How many lines the field has: a whole number within bounds is itself;
/// otherwise ONE, not the nearest bound (`unreadableInputLines`).
int inputLinesOf(Object? lines) {
  if (lines is! num || !_isWhole(lines)) return kTextFieldDefaultLines;
  final count = lines.toInt();
  return count < kTextFieldMinLines || count > kTextFieldMaxLines ? kTextFieldDefaultLines : count;
}

// ───────────────────────────── keyboard kind ─────────────────────────────

/// The keyboard kind: a closed list of INTENTS. There is deliberately no
/// password: the value goes to the host in the open and the document arrives
/// over the network, so a password field in it would be a phishing form.
enum InputKeyboard {
  text('text'),
  email('email'),
  number('number'),
  phone('phone'),
  url('url');

  const InputKeyboard(this.wire);

  final String wire;
}

const InputKeyboard kDefaultInputKeyboard = InputKeyboard.text;

/// The intent for a document word. If the field is absent or the word unknown
/// (`password`, `search` from a newer minor version) the result is `text`
/// (`unknownInputKeyboard`); the field does not become hidden because of it.
InputKeyboard inputKeyboardOf(Object? keyboard) {
  if (keyboard is! String) return kDefaultInputKeyboard;
  for (final candidate in InputKeyboard.values) {
    if (candidate.wire == keyboard) return candidate;
  }
  return kDefaultInputKeyboard;
}

/// The effective keyboard: a multi-line field does not read the intent
/// (`multilineKeyboard`), and a NUMERIC one (9.14.0, `valueType: 'number'`) is
/// always single-line with a numeric keyboard and reads neither `keyboard` nor
/// `lines` (`numberInputOptions`). `null` means multi-line.
InputKeyboard? effectiveInputKeyboardOf(Object? keyboard, Object? lines, {bool numeric = false}) {
  if (numeric) return kNumberInputKeyboard;
  return inputLinesOf(lines) > 1 ? null : inputKeyboardOf(keyboard);
}

/// How many lines the field really has: a numeric one has one, whatever `lines` says.
int effectiveInputLinesOf(Object? lines, {bool numeric = false}) =>
    numeric ? kTextFieldDefaultLines : inputLinesOf(lines);

/// Whether the document's `valueType` says "number": only the word `number`. An
/// absent field, another word (`date` from a newer minor version) or a
/// non-string means a string field (`unknownInputValueType`).
bool isNumberValueType(Object? valueType) => valueType == 'number';

/// The numeric field's keyboard (9.14.0): a single one; it does not read the document's intent.
const InputKeyboard kNumberInputKeyboard = InputKeyboard.number;

/// Flutter counterparts (`textField.keyboards.<intent>.flutter`): artifact
/// WORDS, not types. `render/inputs.dart` translates them into `TextInputType`.
typedef InputKeyboardFlutter = ({
  String keyboardType,
  List<String> autofillHints,
  String textCapitalization,
  bool autocorrect,
});

const Map<InputKeyboard, InputKeyboardFlutter> kInputKeyboardFlutter = {
  InputKeyboard.text: (keyboardType: 'text', autofillHints: [], textCapitalization: 'sentences', autocorrect: true),
  InputKeyboard.email: (
    keyboardType: 'emailAddress',
    autofillHints: ['email'],
    textCapitalization: 'none',
    autocorrect: false,
  ),
  InputKeyboard.number: (
    keyboardType: 'numberWithOptions(decimal: true)',
    autofillHints: [],
    textCapitalization: 'none',
    autocorrect: false,
  ),
  InputKeyboard.phone: (
    keyboardType: 'phone',
    autofillHints: ['telephoneNumber'],
    textCapitalization: 'none',
    autocorrect: false,
  ),
  InputKeyboard.url: (keyboardType: 'url', autofillHints: ['url'], textCapitalization: 'none', autocorrect: false),
};

/// The direction of the CONTENT (`box.contentDirection`, `directionCases`):
/// email, phone, URL and number are always left to right; text and multi-line
/// follow the screen. ALIGNMENT, meanwhile, is always from the start of the SCREEN.
bool inputContentIsLeftToRight(Object? keyboard, Object? lines, {bool numeric = false}) {
  final effective = effectiveInputKeyboardOf(keyboard, lines, numeric: numeric);
  return effective != null && effective != InputKeyboard.text;
}

// ───────────────────────────── keyboard action button ─────────────────────────────

/// What the keyboard button does (`keyActionCases`): multi-line gets a new line;
/// if a reachable text field follows, "next"; otherwise "done". It NEVER runs
/// an action (`inputKeyAction`).
enum InputKeyAction { newline, next, done }

/// A field for the traversal order: whether it is multi-line and whether it is
/// reachable (shown and not disabled).
typedef FocusableInput = ({bool multiline, bool reachable});

InputKeyAction inputKeyActionOf(List<FocusableInput> fields, int index) {
  if (index < 0 || index >= fields.length) return InputKeyAction.done;
  if (fields[index].multiline) return InputKeyAction.newline;
  for (var later = index + 1; later < fields.length; later += 1) {
    if (fields[later].reachable) return InputKeyAction.next;
  }
  return InputKeyAction.done;
}

/// The next reachable field after this one; `null` if there is nowhere further.
/// The search never goes backwards.
int? nextInputIndexOf(List<FocusableInput> fields, int index) {
  for (var later = index + 1; later < fields.length; later += 1) {
    if (fields[later].reachable) return later;
  }
  return null;
}

// ───────────────────────────── error ─────────────────────────────

/// The error state: text that can be HEARD (not empty, not only spaces, not
/// invisible characters); the character class is the same as for an "empty"
/// accessible name (`x-accessibleName`). `null` means no error; otherwise the
/// SHOWN text is returned (9.18.0), with whitespace collapsed by the shown-text rule.
String? inputErrorOf(String? errorText) =>
    errorText == null || isSilentAccessibleName(errorText) ? null : collapseShownWhitespace(errorText);

// ───────────────────────────── what the field shows and writes ─────────────────────────────

/// The reader's text field state: just enough to answer "what is in the field"
/// and "what to write" (`TextInputState` of the reference implementation).
class TextInputState {
  const TextInputState({this.focused = false, this.touched = false, this.composing = false, this.held});

  final bool focused;

  /// A person touched the field (focus or typing). Before that the field writes nothing.
  final bool touched;

  /// A character is being composed (IME): intermediate text is not written.
  final bool composing;

  /// What the person typed and what the layer value was at that moment; `null`
  /// means the field shows the layers.
  final HeldText? held;

  TextInputState copyWith({bool? focused, bool? touched, bool? composing, Object? held = _keep}) => TextInputState(
    focused: focused ?? this.focused,
    touched: touched ?? this.touched,
    composing: composing ?? this.composing,
    held: identical(held, _keep) ? this.held : held as HeldText?,
  );
}

const Object _keep = Object();

/// Text typed by a person. [released] means the layer value has CHANGED since:
/// the typed text is still shown while focused, but there is no reason to keep
/// holding it afterwards.
class HeldText {
  const HeldText({required this.text, required this.from, this.released = false});

  final String text;
  final String from;
  final bool released;
}

const TextInputState kInitialTextInput = TextInputState();

sealed class TextInputEvent {
  const TextInputEvent();
}

final class FocusEvent extends TextInputEvent {
  const FocusEvent();
}

final class BlurEvent extends TextInputEvent {
  const BlurEvent();
}

/// The person changed the text (typing, paste, erasing, choosing a suggestion);
/// [text] is the whole content of the field.
final class InputEvent extends TextInputEvent {
  const InputEvent(this.text);

  final String text;
}

final class CompositionStartEvent extends TextInputEvent {
  const CompositionStartEvent();
}

/// Composition ended; [text] is the whole content of the field after it.
final class CompositionEndEvent extends TextInputEvent {
  const CompositionEndEvent(this.text);

  final String text;
}

/// The platform filled in a value WITHOUT the person (autofill before the first touch).
final class PlatformFillEvent extends TextInputEvent {
  const PlatformFillEvent(this.text);

  final String text;
}

/// The result of a step: the new state and (maybe) a write, to the field's path,
/// into the reader's session and to the host at the same moment.
typedef TextInputStep = ({TextInputState state, String? write});

/// ONE STEP OF A TEXT FIELD: an event gives the new state and (maybe) a write
/// (`stepTextInput`).
///
/// A write happens on EVERY text change by the person, immediately (no delay
/// and no "on blur"). Nothing is written for: the same text a second time, a
/// disabled field, intermediate composition text, a value the platform filled
/// in before the first touch, or a field without a path.
TextInputStep stepTextInput(
  TextInputState state,
  TextInputEvent event,
  String bound, {
  Object? maxLength,
  bool disabled = false,
  bool hasPath = true,
}) {
  if (disabled) {
    return (state: kInitialTextInput.copyWith(touched: state.touched), write: null);
  }
  final shown = shownInputText(state, bound);

  TextInputStep accept(String raw) {
    final text = clampInputText(raw, maxLength);
    final next = state.copyWith(
      touched: true,
      composing: false,
      held: HeldText(text: text, from: bound),
    );
    return (state: next, write: text == shown || !hasPath ? null : text);
  }

  switch (event) {
    case FocusEvent():
      // A focused field is the source of truth: it holds what it showed at the moment of focus.
      return (
        state: state.copyWith(
          focused: true,
          touched: true,
          held: state.held ?? HeldText(text: shown, from: bound),
        ),
        write: null,
      );
    case BlurEvent():
      // The layer value changed while the field was focused, so the typed text need not be held any more.
      return (
        state: state.copyWith(focused: false, composing: false, held: state.held?.released == true ? null : state.held),
        write: null,
      );
    case CompositionStartEvent():
      return (state: state.copyWith(composing: true), write: null);
    case InputEvent(:final text):
      if (state.composing) {
        return (
          state: state.copyWith(
            touched: true,
            held: HeldText(text: text, from: bound),
          ),
          write: null,
        );
      }
      return accept(text);
    case CompositionEndEvent(:final text):
      return accept(text);
    case PlatformFillEvent(:final text):
      return state.touched ? accept(text) : (state: state, write: null);
  }
}

/// What the field shows: while focused, the typed text (data does not change
/// text under the cursor); without focus, the typed text UNTIL the layer value
/// changes, then the layers.
String shownInputText(TextInputState state, String bound) {
  final held = state.held;
  if (held == null) return bound;
  if (state.focused) return held.text;
  return held.released || held.from != bound ? bound : held.text;
}

/// The layer value CHANGED. The reader calls this each time the value under the
/// field's path becomes different, as an event and not as a comparison at paint
/// time: such a comparison could not tell "A, B, A" from "unchanged".
TextInputState syncTextInput(TextInputState state, String bound) {
  final held = state.held;
  if (held == null || held.released || held.from == bound) return state;
  return state.focused
      ? state.copyWith(
          held: HeldText(text: held.text, from: held.from, released: true),
        )
      : state.copyWith(held: null);
}

/// The state of a switch and a checkbox: what the person set, and at which layer value.
class ToggleState {
  const ToggleState({this.heldOn, this.heldFrom});

  final bool? heldOn;
  final bool? heldFrom;

  bool get isHeld => heldOn != null;
}

const ToggleState kInitialToggle = ToggleState();

/// What the switch shows: what the person set, until the layer value changes.
bool shownToggle(ToggleState state, bool bound) =>
    !state.isHeld ? bound : (state.heldFrom == bound ? state.heldOn! : bound);

/// The layer value changed: what the person set is no longer held.
ToggleState syncToggle(ToggleState state, bool bound) =>
    !state.isHeld || state.heldFrom == bound ? state : kInitialToggle;

/// A press: the value flips relative to the SHOWN one and is written at once. A
/// disabled control neither changes nor writes; without a path it changes but
/// does not write.
({ToggleState state, bool? write}) pressToggle(
  ToggleState state,
  bool bound, {
  bool disabled = false,
  bool hasPath = true,
}) {
  if (disabled) return (state: state, write: null);
  final on = !shownToggle(state, bound);
  final next = ToggleState(heldOn: on, heldFrom: bound);
  return (state: next, write: hasPath ? on : null);
}

// ───────────────────────────── numeric field (9.14.0) ─────────────────────────────

/// The digits a numeric field accepts: ASCII, Arabic-Indic (U+0660-U+0669) and
/// Extended Arabic-Indic (Persian, Urdu: U+06F0-U+06F9). Each entry is the zero
/// of a run; a digit's value is its distance from it (`number.parse.digitZeros`).
const List<int> kNumberInputDigitZeros = [0x30, 0x660, 0x6f0];

/// Decimal separators: the full stop, the comma and the Arabic U+066B
/// (`number.parse.separators`).
const List<int> kNumberInputSeparators = [46, 44, 1643];

/// Minus: the keyboard hyphen-minus and the typographic U+2212 (`number.parse.minus`).
const List<int> kNumberInputMinus = [45, 8722];

/// What is trimmed from the edges of typed text: space, no-break space, narrow
/// no-break space and tab (`number.parse.trimmed`).
const List<int> kNumberInputTrimmed = [32, 160, 8239, 9];

/// The most digits a number may have, all of them including zeros (`maxDigits`).
const int kNumberInputMaxDigits = 15;

/// The largest safe integer (2^53 - 1): the reader does not treat a number
/// beyond it as a number (`number.read.number`).
const int kMaxSafeInteger = 9007199254740991;

int? _digitOf(int code) {
  for (final zero in kNumberInputDigitZeros) {
    if (code >= zero && code <= zero + 9) return code - zero;
  }
  return null;
}

/// A whole value is an `int`, a fractional one a `double`: the number goes into
/// the record (JSON) without `.0`, and `-0.0` becomes zero.
num _canonicalNumber(double value) {
  if (value == value.truncateToDouble() && value.abs() <= kMaxSafeInteger) return value.toInt();
  return value;
}

/// TYPED TEXT to a NUMBER, or `null` for "not a number" (`parseInputNumber`,
/// `numberParseCases`).
///
/// A RULE OF ITS OWN, not `num.tryParse` / `double.tryParse`: they accept
/// `"1e5"`, `"NaN"` and hexadecimal, and do not know `"1,5"` or Arabic digits,
/// so two readers would disagree at the first comma. The form: edges trimmed;
/// an optional minus; digits; an optional SINGLE separator and digits; at least
/// one digit; no more than fifteen digits in all. There are no digit groups
/// (`"1,200"` is one and two tenths) and no exponent. Minus zero is zero. A
/// single pass, with no backtracking regular expression.
num? parseInputNumber(String text) {
  final chars = text.runes.toList(growable: false);
  var start = 0;
  var end = chars.length;
  while (start < end && kNumberInputTrimmed.contains(chars[start])) {
    start += 1;
  }
  while (end > start && kNumberInputTrimmed.contains(chars[end - 1])) {
    end -= 1;
  }

  var negative = false;
  if (start < end && kNumberInputMinus.contains(chars[start])) {
    negative = true;
    start += 1;
  }

  final whole = StringBuffer();
  final fraction = StringBuffer();
  var separated = false;
  for (var index = start; index < end; index += 1) {
    final code = chars[index];
    final digit = _digitOf(code);
    if (digit != null) {
      (separated ? fraction : whole).write(digit);
      continue;
    }
    if (!separated && kNumberInputSeparators.contains(code)) {
      separated = true;
      continue;
    }
    return null;
  }

  final digits = whole.length + fraction.length;
  if (digits == 0 || digits > kNumberInputMaxDigits) return null;
  // The canonical decimal form, which both platforms read the same way.
  final canonical = '${whole.isEmpty ? '0' : whole}${fraction.isEmpty ? '' : '.$fraction'}';
  final value = double.parse(canonical);
  if (value == 0) return 0;
  return _canonicalNumber(negative ? -value : value);
}

/// A NUMBER FROM A DATA LAYER VALUE (`readInputNumber`, `numberReadCases`). A
/// finite number within the safe-integer range is itself (a whole number written
/// as a fraction, `12.0`, is `12`); everything else (absent, `null`, a string,
/// even `"12"`, a flag) means "no number". The field does NOT turn a string
/// into a number.
num? readInputNumber(Object? value) {
  if (value is! num || value.isNaN || value.isInfinite) return null;
  if (value > kMaxSafeInteger || value < -kMaxSafeInteger) return null;
  return value is int ? value : _canonicalNumber(value as double);
}

final RegExp _plainDecimal = RegExp(r'^-?\d+(\.\d+)?$');

/// What a numeric field shows for a number from data (`numberInputText`): ASCII
/// digits, a full stop, no groups and no language; a whole number has no `.0`.
/// A value that would need an exponent (magnitude below 10^-6) and "no number"
/// both give an empty field.
///
/// Dart's `double.toString()` writes an exponent already from 10^-5 (`1e-5`),
/// while the reference implementation does so from 10^-7: the text is built
/// from the shortest digits of `toString` itself, but without an exponent where
/// there must not be one.
String numberInputText(Object? value) {
  final number = readInputNumber(value);
  if (number == null) return '';
  if (number is int) return number.toString();
  var text = number.toString();
  final e = text.indexOf('e');
  if (e >= 0) {
    final exponent = int.parse(text.substring(e + 1));
    if (exponent >= 0 || exponent < -6) return '';
    var mantissa = text.substring(0, e);
    final negative = mantissa.startsWith('-');
    if (negative) mantissa = mantissa.substring(1);
    final digits = mantissa.replaceAll('.', '');
    text = '${negative ? '-' : ''}0.${'0' * (-exponent - 1)}$digits';
  }
  return _plainDecimal.hasMatch(text) ? text : '';
}

/// The number of the typed text, or `''`, as it goes into the record.
Object _writtenNumberOf(String text) => parseInputNumber(text) ?? '';

/// WHAT A NUMERIC FIELD SHOWS (`shownNumberInput`). While focused, the typed
/// text. Without focus, the typed text UNTIL ITS NUMBER equals the layers'
/// number ("36,6" stays while the layers hold 36.6; "12a" stays while there is
/// no number under the path); otherwise the layers' number. NUMBERS are
/// compared, not texts, so a numeric field needs no `sync...` events.
String shownNumberInput(TextInputState state, Object? bound) {
  final held = state.held;
  if (held == null) return numberInputText(bound);
  if (state.focused) return held.text;
  return _writtenNumberOf(held.text) == (readInputNumber(bound) ?? '') ? held.text : numberInputText(bound);
}

/// A NUMERIC FIELD HOLDING A NON-NUMBER (`numberInputInvalid`,
/// `form.numberInvalid`). The field is in the ERROR STATE when it is not
/// focused and the shown text is non-empty and is not a number by
/// [parseInputNumber]. While focused there is no such state (it does not flash
/// on "-" or "1,"); the SHOWN text is judged, not the typed one: a number from
/// data has no error. Text made only of the parser's edge characters
/// ([kNumberInputTrimmed]) counts as empty. The reader adds no text; what to
/// type is told by `helper`.
bool numberInputInvalid(TextInputState state, Object? bound) {
  if (state.focused) return false;
  final shown = shownNumberInput(state, bound);
  if (shown.codeUnits.every(kNumberInputTrimmed.contains)) return false;
  return parseInputNumber(shown) == null;
}

/// The result of a numeric field step: the new state and (maybe) a write, a `num` or `''`.
typedef NumberInputStep = ({TextInputState state, Object? write});

/// ONE STEP OF A NUMERIC FIELD (`stepNumberInput`), a mirror of
/// [stepTextInput]: the same events, focus, character composition, first touch
/// and length limit (which concerns the TYPED text).
///
/// A number is written when the typed text is a number, and the empty string
/// `''` when the field was erased OR the typed text is not a number ("12a",
/// "-"). Not `null` (in a layer that means "read the next layer", so an erased
/// number would come back from the host's data) and not silence (an action
/// after typing would carry a number the person no longer sees). The field
/// keeps the typed text meanwhile. The same value is not written twice:
/// "5", "5.", "5.0" is one write.
NumberInputStep stepNumberInput(
  TextInputState state,
  TextInputEvent event,
  Object? bound, {
  Object? maxLength,
  bool disabled = false,
  bool hasPath = true,
}) {
  if (disabled) {
    return (state: kInitialTextInput.copyWith(touched: state.touched), write: null);
  }
  final shown = shownNumberInput(state, bound);

  NumberInputStep accept(String raw) {
    final text = clampInputText(raw, maxLength);
    final next = state.copyWith(
      touched: true,
      composing: false,
      held: HeldText(text: text, from: shown),
    );
    final value = _writtenNumberOf(text);
    return (state: next, write: value == _writtenNumberOf(shown) || !hasPath ? null : value);
  }

  switch (event) {
    case FocusEvent():
      return (
        state: state.copyWith(
          focused: true,
          touched: true,
          held: state.held ?? HeldText(text: shown, from: shown),
        ),
        write: null,
      );
    case BlurEvent():
      // What to show without focus is decided by comparing numbers; the typed text stays in the state.
      return (state: state.copyWith(focused: false, composing: false), write: null);
    case CompositionStartEvent():
      return (state: state.copyWith(composing: true), write: null);
    case InputEvent(:final text):
      if (state.composing) {
        return (
          state: state.copyWith(
            touched: true,
            held: HeldText(text: text, from: shown),
          ),
          write: null,
        );
      }
      return accept(text);
    case CompositionEndEvent(:final text):
      return accept(text);
    case PlatformFillEvent(:final text):
      return state.touched ? accept(text) : (state: state, write: null);
  }
}

// ───────────────────────────── disabled state ─────────────────────────────

/// Opacity of a disabled field: one value for the three widgets, applied to the
/// WHOLE widget (`rules.disabled.look.opacity`).
const double kInputDisabledOpacity = 0.5;

/// Whether a field is disabled (`disabledIf`): the same shape and the same
/// function as `visibleIf`. No field means enabled; an unknown operator (the
/// condition did not parse and stayed an `AlwaysVisibleCondition`) means enabled
/// (`unknownDisabledOp`); a missing value follows the `missingConditionValue`
/// rule (which is exactly what `UnaryCondition` implements).
bool isInputDisabled(VisibilityCondition? condition, ScreenData data) {
  if (condition == null || condition is AlwaysVisibleCondition) return false;
  return condition.evaluate(data);
}

// ───────────────────────────── geometry ─────────────────────────────

/// The numbers of the data block (`x-style.layout.inputs`). The reader takes
/// them from its OWN mirror, not from the document: the document does not have them.
const double kTextFieldBorderWidth = 1;
const double kTextFieldRingWidth = 1;

const double kSwitchTrackWidth = 52;
const double kSwitchTrackHeight = 32;
const double kSwitchThumbSize = 24;
const double kSwitchThumbInset = 4;

const double kCheckboxBoxSize = 20;
const double kCheckboxBoxRadius = 4;
const double kCheckboxBorderWidth = 2;
const double kCheckboxMarkSize = 16;

/// Text field metrics: line heights of the label (`bodyS`), the entered text
/// (`bodyM`) and the line under the field (`bodyS`), the gap, the padding and the border.
typedef TextFieldMetrics = ({
  double labelLine,
  double textLine,
  double noteLine,
  double gap,
  double paddingBlock,
  double border,
});

/// Height of the field box: border + padding + lines.
double textFieldBoxHeightOf(TextFieldMetrics metrics, Object? lines) =>
    2 * metrics.border + 2 * metrics.paddingBlock + inputLinesOf(lines) * metrics.textLine;

/// Height of the field block: label lines, the box and (if present) the error
/// or helper lines, separated by the gap.
double textFieldHeightOf(TextFieldMetrics metrics, {Object? lines, required int labelLines, required int noteLines}) {
  final label = labelLines * metrics.labelLine;
  final note = noteLines == 0 ? 0.0 : metrics.gap + noteLines * metrics.noteLine;
  return label + metrics.gap + textFieldBoxHeightOf(metrics, lines) + note;
}

/// Height of the switch row: the taller of the track and the label lines.
double switchHeightOf(double labelLine, int labelLines) =>
    kSwitchTrackHeight > labelLine * labelLines ? kSwitchTrackHeight : labelLine * labelLines;

/// Width of the switch label: the row minus the track and the gap.
double switchLabelWidthOf(double rowWidth, double gap) {
  final width = rowWidth - kSwitchTrackWidth - gap;
  return width < 0 ? 0 : width;
}

double checkboxHeightOf(double labelLine, int labelLines) =>
    kCheckboxBoxSize > labelLine * labelLines ? kCheckboxBoxSize : labelLine * labelLines;

double checkboxLabelWidthOf(double rowWidth, double gap) {
  final width = rowWidth - kCheckboxBoxSize - gap;
  return width < 0 ? 0 : width;
}

/// Offset of the checkbox square from the top of the row: the square's centre
/// sits on the centre of the FIRST label line. If the line is shorter than the
/// square, the square starts at the top.
double checkboxBoxOffsetOf(double labelLine) {
  final offset = (labelLine - kCheckboxBoxSize) / 2;
  return offset < 0 ? 0 : offset;
}

/// Where the thumb is: the distance from the START of the track in the writing direction.
double switchThumbOffsetOf(bool on) =>
    on ? kSwitchTrackWidth - kSwitchThumbInset - kSwitchThumbSize : kSwitchThumbInset;

/// The twenty policy rows of 9.13.0 (`x-compatibility.policy`, starting at
/// `inputWithoutValue`). A mirror for comparison with the artifact; the
/// behaviour of each row is held by its own test in `input_cases_test.dart`.
const Map<String, String> kInputsPolicy = {
  'inputWithoutValue': 'local-only-writes-nothing',
  'unreadableInputValue': 'local-only-writes-nothing',
  'inputValueOfOtherType': 'empty-field-or-off',
  'inputEmptyString': 'empty-field',
  'inputWrite': 'on-every-change-to-session-and-host',
  'inputWriteWhileComposing': 'after-the-composition',
  'inputHeldValue': 'while-focused-or-until-bound-value-changes',
  'inputBeforeFirstTouch': 'not-kept-not-written',
  'inputDisabled': 'not-focusable-writes-nothing',
  'unknownDisabledOp': 'enabled',
  'missingDisabledValue': 'as-missingConditionValue',
  'unknownInputKeyboard': 'text',
  'inputMaxLength': 'cut-to-code-points',
  'unreadableInputLines': 'one-line',
  'inputError': 'heard-text-is-the-error-state',
  'inputKeyAction': 'next-or-done-never-an-action',
  'inputInsideRepeater': 'drawn-writes-by-its-path',
  'inputFocusOnScreenChange': 'removed',
  'inputAutofill': 'from-keyboard-intent-host-can-turn-off',
  'inputValueInActionParam': 'whole-value-no-composition',
};

/// The fourteen policy rows of 9.14.0 (`x-compatibility.policy`, starting at
/// `unreadableRequired`). A mirror for comparison with the artifact; the
/// behaviour of each row is held by its own test in `form_cases_test.dart`.
const Map<String, String> kFormPolicy = {
  'unreadableRequired': 'not-required',
  'requiredHiddenOrDisabled': 'not-counted',
  'requiredWithoutPath': 'never-filled',
  'requiredInInactiveTab': 'counted',
  'requiredMessage': 'none',
  'unreadableRequiresFilled': 'not-read',
  'requiresFilledWithoutRequired': 'enabled',
  'disabledPress': 'no-action-no-track-stays-focusable',
  'unknownInputValueType': 'string',
  'numberInputText': 'number-else-empty-string-typed-text-kept',
  'numberInputValueOfOtherType': 'empty-field',
  'numberInputOptions': 'keyboard-and-lines-not-read',
  'choiceWrite': 'to-session-and-host-like-inputs',
  'nonStringActionParam': 'literal-from-params',
};
