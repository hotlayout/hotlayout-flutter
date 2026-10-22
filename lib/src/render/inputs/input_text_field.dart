/// The text field: reads its value from the data layers, writes on every change
/// and keeps what the user is typing.
library;

import '../press_feedback.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../model/input_parts.dart';
import '../../model/input_rules.dart';
import '../../model/tokens.dart';
import '../../theme/render_theme.dart';
import 'input_label.dart';
import 'input_parts_view.dart';
import 'input_scope.dart';

// ───────────────────────────── text field ─────────────────────────────

/// Truncates the input to the limit in CODE POINTS (`inputMaxLength`). A formatter of our own, not
/// the widget's `maxLength`: that counts graphemes while the web counts UTF-16 units, and readers
/// would diverge on every emoji.
class CodePointLimit extends TextInputFormatter {
  const CodePointLimit(this.maxLength);

  final Object? maxLength;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final clamped = clampInputText(newValue.text, maxLength);
    if (clamped == newValue.text) return newValue;
    if (clamped == oldValue.text) return oldValue;
    return TextEditingValue(
      text: clamped,
      selection: TextSelection.collapsed(
        offset: math.min(newValue.selection.extentOffset, clamped.length).clamp(0, clamped.length),
      ),
    );
  }
}

/// Maps the artifact's words (`textField.keyboards.*.flutter`) to Flutter types.
TextInputType textInputTypeOf(String word) => switch (word) {
  'emailAddress' => TextInputType.emailAddress,
  'numberWithOptions(decimal: true)' => const TextInputType.numberWithOptions(decimal: true),
  'phone' => TextInputType.phone,
  'url' => TextInputType.url,
  _ => TextInputType.text,
};

TextCapitalization textCapitalizationOf(String word) =>
    word == 'sentences' ? TextCapitalization.sentences : TextCapitalization.none;

/// The text field: a label above the box, the box with the field, a note line below.
class InputTextField extends StatefulWidget {
  const InputTextField({
    required this.theme,
    required this.label,
    required this.bound,
    required this.path,
    required this.disabled,
    required this.onWrite,
    this.placeholder,
    this.helper,
    this.error,
    this.keyboard,
    this.maxLength,
    this.lines,
    this.numeric = false,
    this.mandatory = false,
    this.parts = FieldParts.none,
    this.prefix,
    this.suffix,
    super.key,
  });

  /// The look of the box and the counter (9.19.0). The marks are in [prefix] and [suffix], already shown.
  final FieldParts parts;
  final ShownAffix? prefix;
  final ShownAffix? suffix;

  final RenderTheme theme;

  /// The label is visible and is the accessible name.
  final String label;

  /// What the data layers currently give, the RAW value: a text field reads a string from it
  /// (`readInputText`), a numeric one reads a number (`readInputNumber`).
  final Object? bound;

  /// The write path; `null` means the field is local and writes nowhere.
  final String? path;
  final bool disabled;

  /// Writes a string (text field) or a number or `''` (numeric, schema 9.14.0).
  final ValueChanged<Object>? onWrite;

  /// A numeric field (schema 9.14.0, `valueType: 'number'`): parsed by the contract's own rule,
  /// `number` keyboard, one line, content left to right.
  final bool numeric;

  /// Required (schema 9.14.0): an asterisk after the label and a state for the screen reader. The
  /// field shows no error text for emptiness (`requiredMessage: none`).
  final bool mandatory;
  final String? placeholder;
  final String? helper;

  /// An error text that can be HEARD (`inputErrorOf`); `null` means no error.
  final String? error;
  final Object? keyboard;
  final Object? maxLength;
  final Object? lines;

  @override
  State<InputTextField> createState() => _InputTextFieldState();
}

class _InputTextFieldState extends State<InputTextField> implements InputFieldHandle {
  late final TextEditingController _controller = TextEditingController(text: _shown);
  @override
  late final FocusNode focusNode = FocusNode(debugLabel: 'sdui-input');
  final GlobalKey _block = GlobalKey();

  TextInputState _state = kInitialTextInput;
  // What the controller showed when we last reconciled it. A change of selection alone is not an
  // event.
  String _seenText = '';
  bool _seenComposing = false;
  // The controller change was made by US (reconciling with the state), not by the user or the platform.
  bool _internal = false;
  InputRegistry? _registry;
  double _seenInset = 0;
  // Which key is on the keyboard: "next" or "done" (a multiline field gets a new line). Computed
  // after the frame, when the tree is complete, not in `build`.
  InputKeyAction _action = InputKeyAction.done;

  @override
  bool get multiline => effectiveInputLinesOf(widget.lines, numeric: widget.numeric) > 1;

  /// The layers' text for a text field (a numeric field does not read it).
  String get _boundText => widget.numeric ? '' : readInputText(widget.bound);

  /// What the field shows now: the decision of the pure rules, not of widget state.
  String get _shown => widget.numeric ? shownNumberInput(_state, widget.bound) : shownInputText(_state, _boundText);

  @override
  bool get reachable => !widget.disabled && focusNode.canRequestFocus;

  @override
  void initState() {
    super.initState();
    _seenText = _controller.text;
    _controller.addListener(_onController);
    focusNode.addListener(_onFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = InputScope.maybeOf(context)?.registry;
    if (!identical(registry, _registry)) {
      _registry?.removeListener(_onRegistry);
      _registry?.unregister(this);
      _registry = registry;
      _registry?.addListener(_onRegistry);
      _registry?.register(this);
    }
    // The keyboard appeared or changed height while the field is focused: the field together with
    // the note line under it must stay in the body area above it (`rules.focus.visible`).
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset != _seenInset) {
      _seenInset = inset;
      if (focusNode.hasFocus) _revealBlock();
    }
  }

  @override
  void didUpdateWidget(InputTextField old) {
    super.didUpdateWidget(old);
    // The EVENT "the layers' value changed" is not a comparison at paint time. A numeric field
    // does not need the "layers changed" event: it compares NUMBERS.
    if (!widget.numeric && readInputText(old.bound) != _boundText) _state = syncTextInput(_state, _boundText);
    if (widget.disabled && !old.disabled) {
      // The field lost focus because it was disabled: the held value is dropped.
      _state = stepTextInput(_state, const BlurEvent(), _boundText, disabled: true).state;
      if (focusNode.hasFocus) focusNode.unfocus();
    }
    if (old.disabled != widget.disabled) _registry?.changed();
    _reconcile();
  }

  void _onRegistry() {
    if (!mounted) return;
    final next = _registry?.keyActionOf(this) ?? InputKeyAction.done;
    if (next != _action) setState(() => _action = next);
  }

  @override
  void dispose() {
    _registry?.removeListener(_onRegistry);
    _registry?.unregister(this);
    _controller.removeListener(_onController);
    focusNode.removeListener(_onFocus);
    _controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  bool get _hasPath => widget.path != null;

  void _apply(TextInputEvent event) {
    final Object? write;
    if (widget.numeric) {
      final step = stepNumberInput(
        _state,
        event,
        widget.bound,
        maxLength: widget.maxLength,
        disabled: widget.disabled,
        hasPath: _hasPath,
      );
      _state = step.state;
      write = step.write;
    } else {
      final step = stepTextInput(
        _state,
        event,
        _boundText,
        maxLength: widget.maxLength,
        disabled: widget.disabled,
        hasPath: _hasPath,
      );
      _state = step.state;
      write = step.write;
    }
    if (write != null) widget.onWrite?.call(write);
  }

  /// The field shows what the rules say; the controller takes the difference SILENTLY (without an
  /// event), otherwise reconciling would itself count as a "user change".
  void _reconcile() {
    final shown = _shown;
    final value = _controller.value;
    final composingNow = value.composing.isValid && !value.composing.isCollapsed;
    final clearComposing = composingNow && !_state.composing;
    if (value.text == shown && !clearComposing) return;
    _internal = true;
    try {
      _controller.value = value.text == shown
          ? value.copyWith(composing: TextRange.empty)
          : TextEditingValue(
              text: shown,
              selection: TextSelection.collapsed(offset: shown.length),
            );
    } finally {
      _internal = false;
    }
    _seenText = shown;
    _seenComposing = false;
  }

  void _onController() {
    if (_internal) return;
    final value = _controller.value;
    final composingNow = value.composing.isValid && !value.composing.isCollapsed;
    // A change of selection alone is not an event.
    if (value.text == _seenText && composingNow == _seenComposing) return;
    _seenText = value.text;
    _seenComposing = composingNow;

    if (composingNow) {
      if (!_state.composing) _apply(const CompositionStartEvent());
      _apply(InputEvent(value.text));
    } else if (_state.composing) {
      _apply(CompositionEndEvent(value.text));
    } else if (!_state.touched && !focusNode.hasFocus) {
      // The platform filled in a value before the user's first touch.
      _apply(PlatformFillEvent(value.text));
    } else {
      _apply(InputEvent(value.text));
    }
    _reconcile();
    // The counter counts what is shown, so it follows every change the person makes.
    if (widget.parts.counter && mounted) setState(() {});
  }

  void _onFocus() {
    if (focusNode.hasFocus) {
      _apply(const FocusEvent());
      _revealBlock();
    } else {
      _apply(const BlurEvent());
      _reconcile();
    }
    if (mounted) setState(() {});
  }

  /// Brings the field with its label and the note line under it into the visible part of the body
  /// (above the keyboard: the body area ends above it, which the screen layout does).
  void _revealBlock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _block.currentContext;
      if (!mounted || context == null || !focusNode.hasFocus) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      // The block is revealed together with the tail of the body (the screen gap above a pinned block, the
      // root's bottom padding otherwise): the same space that lies under the last child at the end of the
      // scroll. A block already visible with its tail does not move; a taller one is put at the top.
      final tail = BodyTail.of(context);
      box.showOnScreen(
        rect: Rect.fromLTWH(0, 0, box.size.width, box.size.height + tail),
        duration: Duration.zero,
      );
    });
  }

  void _onEditingComplete() {
    final registry = _registry;
    if (registry == null) {
      focusNode.unfocus();
    } else {
      registry.submit(this);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final lines = effectiveInputLinesOf(widget.lines, numeric: widget.numeric);
    final multi = lines > 1;
    final keyboard = effectiveInputKeyboardOf(widget.keyboard, widget.lines, numeric: widget.numeric);
    final platform = keyboard == null ? null : kInputKeyboardFlutter[keyboard];
    final autofill = InputScope.maybeOf(context)?.autofill ?? true;
    final leftToRight = inputContentIsLeftToRight(widget.keyboard, widget.lines, numeric: widget.numeric);

    final screenRtl = Directionality.of(context) == TextDirection.rtl;
    final error = widget.error;
    final hasError = error != null;
    // A non-number in a numeric field outside focus is the same error state as a non-empty
    // `error`, but without text (the helper stays in place).
    final invalidNumber = widget.numeric && !widget.disabled && numberInputInvalid(_state, widget.bound);
    final errorState = hasError || invalidNumber;
    final focused = focusNode.hasFocus && !widget.disabled;

    final primary = theme.color(ColorToken.primary);
    final danger = theme.color(ColorToken.danger);
    final muted = theme.color(ColorToken.muted);
    // The look of the box itself (9.19.0). Each prop is the built-in value when it is not named, is not of its form
    // or names a token the theme does not know.
    final parts = widget.parts;
    final radius = (parts.radius == null ? null : theme.resolveRadius(parts.radius!)) ?? theme.radius(kFieldRadiusToken);
    final background =
        (parts.background == null ? null : theme.resolveColor(parts.background!)) ?? theme.color(kFieldBackgroundToken);
    final restBorder =
        (parts.borderColor == null ? null : theme.resolveColor(parts.borderColor!)) ?? theme.color(kFieldBorderToken);
    final borderWidth = fieldBorderWidthOf(parts.borderWidth).toDouble();
    final namedHeight = fieldHeightOf(parts.height, lines);
    final gap = theme.space(SpacingToken.xs);
    final markGap = theme.space(kFieldAffixGap);
    final pad = theme.space(SpacingToken.md);

    final labelStyle = theme.text(TypographyToken.bodyS).copyWith(color: muted);
    final noteStyle = theme.text(TypographyToken.bodyS);
    final textStyle = theme.text(TypographyToken.bodyM).copyWith(color: theme.color(ColorToken.onSurface));
    final strut = StrutStyle(
      fontFamily: textStyle.fontFamily,
      fontSize: textStyle.fontSize,
      height: textStyle.height,
      forceStrutHeight: true,
    );

    // Border: an error beats focus; when focused with an error the ring is `danger`.
    final borderColor = errorState ? danger : (focused ? primary : restBorder);
    final ringColor = errorState ? danger : primary;
    final note = hasError ? error : (widget.helper != null && widget.helper!.isNotEmpty ? widget.helper : null);

    // The placeholder is drawn by us, not as `hintText`: that ends up in the field's accessible
    // name, while a placeholder must not become a name. Visible while the field is empty.
    final decoration = const InputDecoration.collapsed(hintText: null);
    final placeholder = widget.placeholder;

    final input = PressFeedback(kind: null, child: Material(
      type: MaterialType.transparency,
      child: TextField(
        controller: _controller,
        focusNode: focusNode,
        enabled: !widget.disabled,
        decoration: decoration,
        style: textStyle,
        strutStyle: strut,
        cursorColor: primary,
        minLines: lines,
        maxLines: lines,
        keyboardType: multi ? TextInputType.multiline : textInputTypeOf(platform!.keyboardType),
        textInputAction: multi
            ? TextInputAction.newline
            : (_action == InputKeyAction.next ? TextInputAction.next : TextInputAction.done),
        textCapitalization: multi ? TextCapitalization.sentences : textCapitalizationOf(platform!.textCapitalization),
        autocorrect: multi ? true : platform!.autocorrect,
        enableSuggestions: multi ? true : platform!.autocorrect,
        autofillHints: !autofill || multi ? const <String>[] : platform!.autofillHints,
        inputFormatters: [CodePointLimit(widget.maxLength)],
        // ALIGNMENT is always from the start of the SCREEN; the content DIRECTION follows intent.
        textAlign: screenRtl ? TextAlign.right : TextAlign.left,
        textDirection: leftToRight ? TextDirection.ltr : null,
        onEditingComplete: multi ? null : _onEditingComplete,
        onTapOutside: (_) => focusNode.unfocus(),
        scrollPadding: EdgeInsets.fromLTRB(20, 20, 20, 20 + gap + noteStyle.fontSize! * (noteStyle.height ?? 1.2)),
        // There is no counter (`maxLength.counter: none`).
        buildCounter: null,
      ),
    ));

    final textField = placeholder == null || placeholder.isEmpty
        ? input
        : Stack(
            children: [
              input,
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) => _controller.text.isNotEmpty
                          ? const SizedBox.shrink()
                          : Text(
                              placeholder,
                              style: textStyle.copyWith(color: muted),
                              strutStyle: strut,
                              maxLines: lines,
                              overflow: TextOverflow.ellipsis,
                              textAlign: screenRtl ? TextAlign.right : TextAlign.left,
                              textDirection: leftToRight ? TextDirection.ltr : null,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );

    // The marks (9.19.0): inside the box, between its padding and the text. They are no part of the value and
    // are never written; a press on one focuses the field.
    Widget? mark(ShownAffix? affix) => affix == null
        ? null
        : FieldMark(affix: affix, style: textStyle, strut: strut, color: muted, onPress: focusNode.requestFocus);
    final field = fieldRowWithMarks(
      field: textField,
      prefix: mark(widget.prefix),
      suffix: mark(widget.suffix),
      gap: markGap,
      multiline: multi,
    );

    // A named height is the exact height of the box with its border; the content stands in the centre and the
    // vertical padding does not apply.
    final box = Container(
      height: namedHeight?.toDouble(),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        // The width is the same in every state; focus and error replace only the colour.
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Container(
        // The ring is INSIDE the border: the box size does not change on focus.
        foregroundDecoration: focused
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(math.max(0, radius - borderWidth)),
                border: Border.all(color: ringColor, width: kTextFieldRingWidth),
              )
            : null,
        padding: namedHeight == null ? EdgeInsets.all(pad) : EdgeInsets.symmetric(horizontal: pad),
        child: namedHeight == null ? field : Center(child: field),
      ),
    );

    final noteWidget = note == null
        ? null
        : Semantics(
            liveRegion: hasError,
            container: hasError,
            // The helper is read as the field's description, not as a separate node.
            excludeSemantics: !hasError,
            child: Text(
              note,
              style: noteStyle.copyWith(color: hasError ? danger : muted),
              strutStyle: StrutStyle(
                fontFamily: noteStyle.fontFamily,
                fontSize: noteStyle.fontSize,
                height: noteStyle.height,
                forceStrutHeight: true,
              ),
            ),
          );

    // The counter (9.19.0): `{count} / {max}` in code points of what is shown; part of the description read with the
    // field, not a live region.
    final counterText = inputCounterText(counter: parts.counter, maxLength: widget.maxLength, shown: _controller.text);
    final markTexts = [heardAffixText(widget.prefix), heardAffixText(widget.suffix)];
    final description = [...markTexts, note, counterText].whereType<String>().where((part) => part.isNotEmpty).join(', ');
    final noteStrut = StrutStyle(
      fontFamily: noteStyle.fontFamily,
      fontSize: noteStyle.fontSize,
      height: noteStyle.height,
      forceStrutHeight: true,
    );
    final counterWidget = counterText == null
        ? null
        : ExcludeSemantics(
            child: Text(
              counterText,
              style: noteStyle.copyWith(color: muted),
              strutStyle: noteStrut,
              maxLines: 1,
              softWrap: false,
            ),
          );

    Widget result = Column(
      key: _block,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: requiredLabel(
            widget.label,
            style: labelStyle,
            strut: StrutStyle(
              fontFamily: labelStyle.fontFamily,
              fontSize: labelStyle.fontSize,
              height: labelStyle.height,
              forceStrutHeight: true,
            ),
            mark: widget.mandatory ? RequiredMark(color: danger, gap: gap) : null,
          ),
        ),
        SizedBox(height: gap),
        Semantics(
          label: widget.label,
          isRequired: widget.mandatory ? true : null,
          hint: description.isEmpty ? null : description,
          validationResult: errorState ? SemanticsValidationResult.invalid : SemanticsValidationResult.none,
          child: box,
        ),
        if (counterWidget != null) ...[
          SizedBox(height: gap),
          noteRowWithCounter(note: noteWidget, counter: counterWidget, gap: markGap),
        ] else if (noteWidget != null) ...[
          SizedBox(height: gap),
          noteWidget,
        ],
      ],
    );
    if (widget.disabled) result = Opacity(opacity: kInputDisabledOpacity, child: result);
    return result;
  }
}
