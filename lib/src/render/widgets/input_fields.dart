/// Inputs: text field, switch, checkbox and the choice group.
library;

import '../../report/report_hub.dart';
import 'package:flutter/material.dart';

import '../../model/bindable.dart';
import '../../model/input_rules.dart';
import '../../model/node.dart';
import '../../model/tokens.dart';
import '../../model/visibility.dart';
import '../choice_scope.dart';
import '../inputs.dart';
import '../node_renderer.dart';
import 'column.dart';

extension InputWidgets on NodeRenderer {
  /// The state key of an input: the node `id` plus the chain of template instance numbers it is
  /// drawn in. Without a key, the field's state would jump to its neighbor when a condition hides
  /// the field above it (`visibleNodes` drops the node from the list), and a bare `id` without
  /// the instance number would be duplicated in a list from data (`inputInsideRepeater`: the
  /// field is drawn in every instance).
  Key _inputKey(String id) => ValueKey('sdui-input-$id@${instance.join('.')}');

  /// The text field (schema 9.13.0). The value comes from the data layers (`data.lookup`) through
  /// `readInputText`; the write goes to the session and the host by the field's path, through the
  /// same function as a choice group's selection.
  Widget buildTextField(TextFieldNode node) {
    final path = node.valuePath;
    final helper = node.helper;
    final error = node.error;
    return InputTextField(
      key: _inputKey(node.id),
      theme: theme,
      label: text(node.label),
      // The raw layer value: a text field reads a string from it, a numeric one a number.
      bound: path == null ? null : data.lookup(path),
      path: path,
      disabled: isInputDisabled(node.disabledIf, data),
      onWrite: path == null ? null : (value) => onWrite?.call(path, value),
      numeric: node.numeric,
      mandatory: node.required,
      placeholder: node.placeholder == null ? null : text(node.placeholder!),
      helper: helper == null ? null : text(helper),
      error: error == null ? null : inputErrorOf(text(error)),
      keyboard: node.keyboard,
      maxLength: node.maxLength,
      lines: node.lines,
      parts: node.parts,
      prefix: shownAffixOf(node.parts.prefix, (mark) => text(mark.text)),
      suffix: shownAffixOf(node.parts.suffix, (mark) => text(mark.text)),
    );
  }

  /// A switch or a checkbox (schema 9.13.0).
  Widget buildToggle(
    ChildNode node,
    InputToggleKind kind,
    BindableString label,
    String? path,
    VisibilityCondition? disabledIf, {
    bool mandatory = false,
  }) => InputToggle(
    key: _inputKey(node.id),
    mandatory: mandatory,
    kind: kind,
    theme: theme,
    label: text(label),
    bound: path == null ? false : readInputFlag(data.lookup(path)),
    path: path,
    disabled: isInputDisabled(disabledIf, data),
    onWrite: path == null ? null : (value) => onWrite?.call(path, value),
  );

  /// The choice group: the only contract node that has its OWN state.
  ///
  /// The state lives in [ChoiceGroupScope], that is, in the very node the selection belongs to
  /// under the contract. This is not an implementation detail: if the selection were addressed
  /// by the group's `id`, two groups with the same `id` on different screens would silently
  /// share one mark.
  ///
  /// **A bound `value` (schema 8.1.0) is also WRITTEN.** If the document says
  /// `{kind: 'binding', path: 'item.selectedId'}`, the group reads that path and writes the
  /// selected name to it: the natural meaning of a bound input, not a new contract capability.
  /// The write address is named by the document itself, so the reader invents nothing. With a
  /// literal `value` there is nowhere to write, and a tap stays local.
  ///
  /// The document does not change and nothing goes to storage: the write lives in the session of
  /// the screen stack (`ScreenFlow._session`).
  Widget buildChoiceGroup(ChoiceGroupNode node) {
    // Deliberately not translated: this is an option name compared with a row's `optionValue`,
    // not text for a person (see `node.dart`).
    final documentValue = node.value.resolve(data);
    if (documentValue.isNotEmpty && !node.optionValues.contains(documentValue)) {
      // The builder catches this at publication, but a document may arrive from the network.
      // Mark nothing and do not "fix" the selection to the first option: an invented selection
      // is worse than none, because it cannot be told from a real one.
      // The value comes from the host's data and is not reported: the node id names the place.
      ReportHub.ignored('node "${node.id}"', 'the ChoiceGroup value is one no row carries as an option: nothing is selected');
    }

    // Only a binding has a write path. A literal `value` has no address, and none may be
    // invented: a write "somewhere" can be neither read back nor predicted.
    final String? writePath = node.valuePath;

    final group = ChoiceGroupScope(
      // Keyed by node: rebuilding the tree with the same document must not reset a selection
      // made by the user.
      key: ValueKey('sdui-choice-${node.id}'),
      documentValue: documentValue,
      onWrite: writePath == null ? null : (value) => onWrite?.call(writePath, value),
      builder: (selected, select) => withChoice(ChoiceScope(selected: selected, select: select)).buildChildColumn(
        node.children,
        gap: theme.fieldSpacing(node.gap),
        align: AlignToken.start,
      ),
    );
    // "Required" (schema 9.14.0): a group has no label, so there is no asterisk either, only the
    // state for the screen reader.
    return node.required ? Semantics(container: true, isRequired: true, child: group) : group;
  }
}
