/// Input fields (schema 9.13.0): `TextField`, `Switch`, `Checkbox`.
///
/// Why custom painting rather than stock Material widgets: sizes, colours and insets are
/// contract DATA (`x-style.layout.inputs`), identical in every reader. `Switch.adaptive` and
/// the Material `Checkbox` have their own look and sizes, and a Material field has a floating
/// label and underline. What stays Material is what is not worth writing by hand: text
/// editing, caret, selection, menu and autofill (`TextField` with a bare decoration).
///
/// What a field knows about data: only two things, what the data layers show right now
/// ([InputTextField.bound]) and where to write ([InputTextField.onWrite]). Everything else,
/// such as what to show while the user types and what to write, is decided by the pure rules
/// in `input_rules.dart` (`stepTextInput`, `syncTextInput`), which the case table exercises
/// without any widget.
library;

export 'inputs/input_label.dart' show RequiredMark, requiredLabel;
export 'inputs/input_parts_view.dart' show ShownAffix, shownAffixOf;
export 'inputs/input_scope.dart' show InputFieldHandle, InputRegistry, InputScope, InputScopeData;
export 'inputs/input_text_field.dart'
    show CodePointLimit, InputTextField, textCapitalizationOf, textInputTypeOf;
export 'inputs/input_toggle.dart' show InputToggle, InputToggleKind;
