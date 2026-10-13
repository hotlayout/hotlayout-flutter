/// Test helper for input fields (9.13.0): a screen with one field driven by the test.
///
/// The screen is drawn with `renderScreen`, not through a flow: a flow would write what
/// is typed into the session and thereby change the "layer values" itself, while the
/// case table treats layers as a separate event (`{ "type": "data" }` — the host or a
/// write supplied another value). Here the layers are the `session`, which the test
/// changes by hand; a write that reached the host lands in [InputHarness.writes].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

typedef Json = Map<String, Object?>;

Json literal(String text) => {'kind': 'literal', 'value': text};

Json binding(String path) => {'kind': 'binding', 'path': path};

Json textFieldNode({
  String id = 'field',
  String label = 'Email',
  Object? value = defaultValue,
  Json? placeholder,
  Json? helper,
  Json? error,
  Object? keyboard,
  Object? maxLength,
  Object? lines,
  Object? disabledIf,
  Json? style,
  Json? visibleIf,
  String path = 'form.field',
  Object? valueType,
  Object? required,
}) => {
  'id': id,
  'type': 'TextField',
  'props': {
    'label': literal(label),
    if (value == defaultValue) 'value': binding(path) else if (value != _absent) 'value': value,
    'placeholder': ?placeholder,
    'helper': ?helper,
    'error': ?error,
    'keyboard': ?keyboard,
    'maxLength': ?maxLength,
    'lines': ?lines,
    'disabledIf': ?disabledIf,
    'valueType': ?valueType,
    'required': ?required,
  },
  'style': ?style,
  'visibleIf': ?visibleIf,
};

Json toggleNode(
  String type, {
  String id = 'toggle',
  String label = 'Push',
  Object? value = defaultValue,
  Object? disabledIf,
  Json? style,
  String path = 'form.flag',
  Object? required,
}) => {
  'id': id,
  'type': type,
  'props': {
    'label': literal(label),
    if (value == defaultValue) 'value': binding(path) else if (value != _absent) 'value': value,
    'disabledIf': ?disabledIf,
    'required': ?required,
  },
  'style': ?style,
};

/// "There is no `value` field" (as opposed to `null`).
const Object absentValue = _absent;
const Object _absent = _Marker('absent');

/// "The helper's default value" — a binding to the default path.
const Object defaultValue = _Marker('default');

/// A separate class: all `const Object()` are one and the same constant.
class _Marker {
  const _Marker(this.name);

  final String name;
}

Json plainText(String id, String text) => {
  'id': id,
  'type': 'Text',
  'props': {'content': literal(text)},
};

UiDocument inputDoc(
  List<Json> children, {
  String? schemaVersion,
  Json? rootStyle,
  String gap = 'none',
}) => UiDocument.fromJson({
  'schemaVersion': schemaVersion ?? kSupportedSchemaVersion,
  'documentId': 'inputs',
  'name': 'inputs',
  'initialScreenId': 'main',
  'screens': [
    {
      'screenId': 'main',
      'name': 'main',
      'root': {
        'id': 'root',
        'type': 'Screen',
        'props': {'gap': gap},
        'style': ?rootStyle,
        'children': children,
      },
    },
  ],
});

/// A screen with fields DRIVEN BY the test: data layers and host replies.
class InputHarness {
  InputHarness(
    this.children, {
    this.session = const {},
    this.data = const {},
    this.autofill = true,
    this.theme,
    this.rootStyle,
    this.onAction,
  });

  final List<Json> children;
  final RenderTheme? theme;
  final Json? rootStyle;
  final SduiActionCallback? onAction;
  Map<String, Object?> session;
  Map<String, Object?> data;
  bool autofill;
  final List<(String, Object?)> writes = [];

  final ValueNotifier<int> _version = ValueNotifier(0);

  /// The host supplied another layer value.
  Future<void> setSession(WidgetTester tester, Map<String, Object?> next) async {
    session = next;
    _version.value += 1;
    await tester.pump();
  }

  Future<void> pump(
    WidgetTester tester, {
    double keyboard = 0,
    double safeBottom = 0,
    double width = 320,
    double height = 568,
    TextDirection? direction,
    bool settle = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
    final doc = inputDoc(children, rootStyle: rootStyle);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            viewInsets: EdgeInsets.only(bottom: keyboard),
            viewPadding: EdgeInsets.only(bottom: safeBottom),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Directionality(
              textDirection: direction ?? TextDirection.ltr,
              child: ValueListenableBuilder<int>(
                valueListenable: _version,
                builder: (context, _, _) => renderScreen(
                  doc.initialScreen,
                  theme: theme ?? RenderTheme.fallback(),
                  data: data,
                  onAction: onAction,
                  session: session,
                  autofill: autofill,
                  onWrite: (path, value) => writes.add((path, value)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await (settle ? tester.pumpAndSettle() : tester.pump());
  }
}
