/// The inputs of one screen: the registry of fields and the scope that gives it
/// to the subtree.
library;

import 'package:flutter/material.dart';

import '../../model/input_rules.dart';

// ───────────────────────────── screen scope ─────────────────────────────

/// The registry of the text fields of ONE screen, needed by the keyboard "next" key: the
/// traversal order is the document order of the shown screen, and "shown and not disabled" means
/// what is actually built right now. So the registry is not built from the document in advance:
/// it is collected from live fields and ordered by walking the element tree.
class InputRegistry extends ChangeNotifier {
  final Set<InputFieldHandle> _fields = {};
  BuildContext? _root;
  // Walking the tree is expensive and every field asks, so the answer lives until the next
  // notification. It is computed only AFTER a frame: in the middle of a build the tree is
  // incomplete.
  List<InputFieldHandle>? _cache;
  bool _notifyScheduled = false;
  bool _disposed = false;

  void _attachRoot(BuildContext? root) => _root = root;

  /// A field appeared or changed its reachability: its neighbors recompute their key action.
  void register(InputFieldHandle field) {
    _fields.add(field);
    changed();
  }

  void unregister(InputFieldHandle field) {
    _fields.remove(field);
    changed();
  }

  /// Notifies after the frame: a field changes during `build`/`initState`, and the listeners
  /// (neighboring fields) rebuild themselves.
  void changed() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      _cache = null;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Fields in DOCUMENT order: a walk of the tree from the screen root, not the order of
  /// appearance or the visual order (in RTL a row goes right to left, the document does not).
  List<InputFieldHandle> ordered() => _cache ??= _collect();

  List<InputFieldHandle> _collect() {
    final root = _root;
    if (root is! Element || !root.mounted) return const [];
    final found = <InputFieldHandle>[];
    void visit(Element element) {
      if (element is StatefulElement) {
        final state = element.state;
        if (state is InputFieldHandle) {
          final handle = state as InputFieldHandle;
          if (_fields.contains(handle)) found.add(handle);
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }

  /// What the keyboard action key of this field does (`inputKeyActionOf`).
  InputKeyAction keyActionOf(InputFieldHandle field) {
    final all = ordered();
    final index = all.indexOf(field);
    if (index < 0) return field.multiline ? InputKeyAction.newline : InputKeyAction.done;
    return inputKeyActionOf([for (final f in all) (multiline: f.multiline, reachable: f.reachable)], index);
  }

  /// "Next": focus the next reachable field; if there is none, "done": focus is released.
  /// The key NEVER runs an action (`inputKeyAction`).
  void submit(InputFieldHandle field) {
    _cache = null;
    final all = ordered();
    final index = all.indexOf(field);
    final target = index < 0
        ? null
        : nextInputIndexOf([for (final f in all) (multiline: f.multiline, reachable: f.reachable)], index);
    if (target == null) {
      field.focusNode.unfocus();
    } else {
      all[target].focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A field for the registry: its `State` implements this.
abstract interface class InputFieldHandle {
  FocusNode get focusNode;
  bool get multiline;

  /// Shown (built) and not disabled.
  bool get reachable;
}

/// The screen root for fields: the registry and the host's `autofill` parameter.
class InputScope extends StatefulWidget {
  const InputScope({required this.autofill, required this.child, super.key});

  /// The host may turn off ALL autofill hints.
  final bool autofill;
  final Widget child;

  static InputScopeData? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<InputScopeData>();

  @override
  State<InputScope> createState() => _InputScopeState();
}

class _InputScopeState extends State<InputScope> {
  final InputRegistry _registry = InputRegistry();

  @override
  void dispose() {
    _registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _registry
      .._attachRoot(context)
      // The screen was rebuilt (data, document): order and reachability may have changed.
      ..changed();
    return InputScopeData(registry: _registry, autofill: widget.autofill, child: widget.child);
  }
}

class InputScopeData extends InheritedWidget {
  const InputScopeData({required this.registry, required this.autofill, required super.child, super.key});

  final InputRegistry registry;
  final bool autofill;

  @override
  bool updateShouldNotify(InputScopeData oldWidget) => oldWidget.autofill != autofill || oldWidget.registry != registry;
}

/// How much of the body's end lies under its last child: the screen gap when a pinned block follows the
/// body, otherwise the root's bottom padding. A focused field is revealed together with it (`rules.focus.visible`),
/// so it does not stand flush against the pinned block or the keyboard.
class BodyTail extends InheritedWidget {
  const BodyTail({required this.extent, required super.child, super.key});

  final double extent;

  static double of(BuildContext context) => context.getInheritedWidgetOfExactType<BodyTail>()?.extent ?? 0;

  @override
  bool updateShouldNotify(BodyTail oldWidget) => oldWidget.extent != extent;
}
