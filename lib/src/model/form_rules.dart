import '../data/screen_data.dart';
import 'input_rules.dart';
import 'layout_rules.dart';
import 'node.dart';
import 'visibility.dart';

/// THE FORM OF A SCREEN (schema 9.14.0): a "required" field, whether the form
/// is filled, and a button that is disabled until the form is filled or while a
/// condition holds.
///
/// Mirror of the builder's reference implementation (`form-rules.ts`) and of the
/// `x-style.layout.form` block of the artifact. Three statements that readers
/// execute identically:
///
///  1. "FILLED" ([isFilledValue]) is a question about the value UNDER the
///     field's path, read through the data layers (screen record, session,
///     host scope, data), not about widget state: the field writes on every
///     change, so the session and the field say the same thing, and the answer
///     stays a function of the DOCUMENT and the layers. It can be computed
///     without the widget tree and checked with a table;
///  2. WHETHER THE FORM IS FILLED ([isFormFilled]): every required field of the
///     SCREEN that a person can fill (shown and not disabled) is filled;
///  3. WHETHER A BUTTON IS DISABLED ([isPressDisabled]): `requiresFilled` on an
///     unfilled form OR a `disabledIf` that holds.
///
/// `form_cases_test.dart` runs the case table (`input-cases.json`, the twelve
/// 9.14.0 groups) both through the formulas here and through the real widget.

/// What "filled" asks about: text, a number, a flag or a choice in a group.
/// There is deliberately no switch here: it always has a value ("off" is an
/// answer too), so a "required switch" would require nothing.
enum FilledKind { text, number, flag, choice }

/// The character that marks a required field (`form.required.mark.text`).
const String kRequiredMarkText = '*';

/// WHETHER A FIELD IS FILLED, judged by the value under its path:
///
///  * text and choice: a string that can be HEARD (spaces and invisible `Cf`
///    characters are not an answer; it is the same "empty" rule as for the
///    accessible name);
///  * number: the path holds a number ([readInputNumber]); `""` and `"12"` do not;
///  * flag: exactly `true`.
bool isFilledValue(FilledKind kind, Object? value) => switch (kind) {
  FilledKind.text || FilledKind.choice => !isSilentAccessibleName(readInputText(value)),
  FilledKind.number => readInputNumber(value) != null,
  FilledKind.flag => readInputFlag(value),
};

/// A required field of a screen: just enough to answer "is it filled and does it
/// count".
class RequiredField {
  const RequiredField({
    required this.nodeId,
    required this.kind,
    required this.path,
    required this.visibleIf,
    required this.disabledIf,
    this.fallback,
    this.hiddenByClass = false,
  });

  final String nodeId;
  final FilledKind kind;

  /// The path where the value lives; `null` is a field without a path, which is
  /// never filled (`requiredWithoutPath`).
  final String? path;

  /// The `visibleIf` of the node itself and of all its ancestors: if any one
  /// fails, the field is not on the screen.
  final List<VisibilityCondition> visibleIf;

  /// The node itself or one of its ancestors is HIDDEN BY THE WIDTH CLASS (9.18.0,
  /// `showOn`): the field is not there at this width and does not count, exactly
  /// like one hidden by a condition (`requiredHiddenOrDisabled`). The tree is
  /// resolved for one class.
  final bool hiddenByClass;
  final VisibilityCondition? disabledIf;

  /// The fallback text of a CHOICE GROUP's binding: with no data the group shows
  /// the option of that name as selected, so "filled" has to see it too.
  final String? fallback;
}

/// THE REQUIRED FIELDS OF A SCREEN, in document order (`requiredFieldsOf`).
///
/// A SCREEN is the root of one `screens[]` entry: app bar, body, pinned block
/// and navigation bar together; a modal layer is a separate entry, so its form
/// is its own. The subtree of a data-driven list is NOT included. A field in a
/// tab that is not currently open IS included: a person can open it and fill it.
List<RequiredField> requiredFieldsOf(UiNode root) {
  final found = <RequiredField>[];
  void walk(UiNode node, List<VisibilityCondition> inherited, bool hiddenAbove) {
    final own = node is ChildNode && node.visibleIf != null ? [...inherited, node.visibleIf!] : inherited;
    final hidden = hiddenAbove || (node is ChildNode && node.hiddenByClass);
    switch (node) {
      case TextFieldNode(required: true):
        found.add(
          RequiredField(
            nodeId: node.id,
            kind: node.numeric ? FilledKind.number : FilledKind.text,
            path: node.valuePath,
            visibleIf: own,
            hiddenByClass: hidden,
            disabledIf: node.disabledIf,
          ),
        );
      case CheckboxNode(required: true):
        found.add(
          RequiredField(
            nodeId: node.id,
            kind: FilledKind.flag,
            path: node.valuePath,
            visibleIf: own,
            hiddenByClass: hidden,
            disabledIf: node.disabledIf,
          ),
        );
      case ChoiceGroupNode(required: true):
        found.add(
          RequiredField(
            nodeId: node.id,
            kind: FilledKind.choice,
            path: node.valuePath,
            visibleIf: own,
            hiddenByClass: hidden,
            disabledIf: null,
            fallback: node.valueFallback,
          ),
        );
      default:
        break;
    }
    if (node is RepeaterNode) return;
    for (final child in node.children) {
      walk(child, own, hidden);
    }
  }

  walk(root, const [], false);
  return found;
}

/// The value "filled" asks about. For a choice group an empty string and an
/// absent value give the binding's fallback text (`emptyBoundString`), which is
/// exactly the option the group shows as selected.
Object? _shownValueOf(RequiredField field, Object? value) {
  final fallback = field.fallback;
  if (field.kind != FilledKind.choice || fallback == null) return value;
  return readInputText(value).isEmpty ? fallback : value;
}

/// WHETHER THE SCREEN'S FORM IS FILLED.
///
/// [data] is the data layers of THIS screen (the record it was opened with,
/// then session, host scope, data) without a list instance's record: a value
/// from the host's data "fills" too. Conditions are read by the same evaluator
/// as `visibleIf`; a form the reader does not understand means "no question":
/// the node is shown and the field is not disabled. With no required fields
/// at all the form is filled.
bool isFormFilled(UiNode root, ScreenData data) {
  for (final field in requiredFieldsOf(root)) {
    final shown = !field.hiddenByClass && field.visibleIf.every((condition) => condition.evaluate(data));
    if (!shown || isInputDisabled(field.disabledIf, data)) continue;
    final path = field.path;
    if (path == null) return false;
    if (!isFilledValue(field.kind, _shownValueOf(field, data.lookup(path)))) return false;
  }
  return true;
}

/// WHETHER A BUTTON IS DISABLED: AT LEAST ONE of two holds, `disabledIf` or
/// `requiresFilled` on an unfilled form. [formFilled] is a function, not a
/// value: the form is computed only for a button that asks about it.
bool isPressDisabled({
  required bool requiresFilled,
  required VisibilityCondition? disabledIf,
  required ScreenData data,
  required bool Function() formFilled,
}) {
  if (isInputDisabled(disabledIf, data)) return true;
  return requiresFilled && !formFilled();
}

/// WHAT A CHOICE IN A GROUP WRITES (`choiceWriteOf`): the value at the binding's
/// path, to the reader's session and to the host at the same moment. If the
/// group's value is not a binding (a literal, an empty path), the choice stays
/// the group's own state and is written nowhere; an option already SHOWN as
/// selected is not written a second time.
({String path, String value})? choiceWriteOf(String? path, String picked, String? shown) =>
    path == null || picked == shown ? null : (path: path, value: picked);
