/// Limits on what a press can do.
///
///  * The package opens nothing itself: no `url_launcher`, no process, no platform channel of its
///    own; `runStandardAction` is the only executor and acts only on `action.standard`.
///  * An address from the document or the data that fails the contract's `https` form is
///    `invalid` and is never opened by the helper.
///  * A parameter is read from data only where the catalog says `bindable: true`
///    (`navigate.screenId` is not).
///  * One gesture is one action: a held key is one press, a long press is not also a tap.
///  * A write goes only to a safe data path, only after a user gesture, and — the contract's
///    `writablePaths` — only to paths the host allows.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

import '../support/fixtures.dart';

Map<String, Object?> _lit(Object? value) => {'kind': 'literal', 'value': value};

Map<String, Object?> _button(String id, Map<String, Object?> action) => {
  'id': id,
  'type': 'Button',
  'props': {'label': _lit(id), 'variant': 'primary', 'action': action},
};

const List<String> hostileUrls = [
  'http://bank.example.com/',
  'https://127.0.0.1/',
  'https://2130706433/',
  'https://0x7f000001/',
  'https://127.1/',
  'https://169.254.169.254/latest/meta-data/',
  'https://[::1]/',
  'https://localhost/',
  'https://bank.example.com@evil.example/',
  'https:\\\\evil.example/',
  'javascript:alert(1)',
  'data:text/html,<script>alert(1)</script>',
  'file:///etc/hosts',
  ' https://bank.example.com/',
  'https://bank.example.com/\u202e',
];

Iterable<File> _libFiles() =>
    Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

/// [source] without `//` comments, so that a sentence ABOUT `url_launcher` does not count.
String _code(String source) => source.split('\n').map((l) => l.replaceFirst(RegExp(r'//.*'), '')).join('\n');

void main() {
  group('the package opens nothing itself', () {
    test('no url_launcher, no process, no method channel in lib/ or in the dependencies', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('url_launcher')));
      for (final file in _libFiles()) {
        final code = _code(file.readAsStringSync());
        expect(code, isNot(contains('url_launcher')), reason: file.path);
        expect(code, isNot(contains('launchUrl')), reason: file.path);
        expect(code, isNot(contains('Process.')), reason: file.path);
        expect(code, isNot(contains('MethodChannel')), reason: file.path);
        expect(code, isNot(contains('SystemNavigator')), reason: file.path);
      }
    });

    test('network requests are made only by the document and placement transports and the picture loader', () {
      final fetchers = <String>{};
      for (final file in _libFiles()) {
        final code = _code(file.readAsStringSync());
        if (code.contains('package:http/') || code.contains('HttpClient(') || code.contains('Image.network')) {
          fetchers.add(file.path.replaceAll(r'\', '/'));
        }
      }
      expect(fetchers, {
        'lib/src/data/document_source.dart',
        'lib/src/placements/placement_source.dart',
        'lib/src/render/picture_fetch_io.dart',
        'lib/src/render/picture_fetch_web.dart',
      });
    });
  });

  group('openUrl: a hostile address is invalid and is not opened', () {
    for (final url in hostileUrls) {
      testWidgets('literal ${Uri.encodeFull(url)}', (tester) async {
        final handed = <ButtonAction>[];
        await pumpDocument(
          tester,
          docWith([_button('go', {'type': 'openUrl', 'params': {'url': url}})]),
          onAction: (action, nodeId) => handed.add(action),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        expect(handed, hasLength(1));
        expect(handed.single.standard, isNull);
        final opened = <String>[];
        expect(runStandardAction(handed.single, openUrl: opened.add), isFalse);
        expect(opened, isEmpty);
      });

      testWidgets('from data ${Uri.encodeFull(url)}', (tester) async {
        final handed = <ButtonAction>[];
        await pumpDocument(
          tester,
          docWith([
            _button('go', {
              'type': 'openUrl',
              'params': {'url': 'https://bank.example.com/'},
              'paramBindings': {'url': 'offer.link'},
            }),
          ]),
          data: {'offer.link': url},
          onAction: (action, nodeId) => handed.add(action),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        expect(handed.single.standard, isNull, reason: 'a value from data that fails the form is not replaced by the literal');
        final opened = <String>[];
        expect(runStandardAction(handed.single, openUrl: opened.add), isFalse);
        expect(opened, isEmpty);
      });
    }

    testWidgets('control: a good address from data is standard and is opened by the helper only', (tester) async {
      final handed = <ButtonAction>[];
      await pumpDocument(
        tester,
        docWith([
          _button('go', {'type': 'openUrl', 'params': {'url': 'https://bank.example.com/'}, 'paramBindings': {'url': 'offer.link'}}),
        ]),
        data: {'offer.link': 'https://offers.example.com/a'},
        onAction: (action, nodeId) => handed.add(action),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      final opened = <String>[];
      expect(runStandardAction(handed.single, openUrl: opened.add), isTrue);
      expect(opened, ['https://offers.example.com/a']);
    });

    testWidgets('a deeplink is never opened without the host scheme list', (tester) async {
      final handed = <ButtonAction>[];
      await pumpDocument(
        tester,
        docWith([_button('go', {'type': 'deeplink', 'params': {'url': 'myapp://pay?to=evil'}})]),
        onAction: (action, nodeId) => handed.add(action),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      final opened = <String>[];
      expect(runStandardAction(handed.single, openDeeplink: opened.add), isFalse);
      expect(runStandardAction(handed.single, openDeeplink: opened.add, deeplinkSchemes: const ['otherapp']), isFalse);
      expect(opened, isEmpty);
    });
  });

  testWidgets('navigate.screenId is not bindable: the data cannot pick the screen', (tester) async {
    final shown = <String>[];
    await pumpDocument(
      tester,
      docWithScreens([
        screenEntry('home', [
          _button('go', {'type': 'navigate', 'params': {'screenId': 'safe'}, 'paramBindings': {'screenId': 'attack.target'}}),
        ]),
        screenEntry('safe', [textNode('safe screen')]),
        screenEntry('admin', [textNode('admin screen')]),
      ], initialScreenId: 'home'),
      data: {'attack.target': 'admin'},
      onScreenShown: (s) => shown.add(s.screenId),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(shown.last, 'safe');
    expect(find.text('admin screen'), findsNothing);
  });

  group('one gesture is one action', () {
    Map<String, Object?> card() => {
      'id': 'card',
      'type': 'Container',
      'props': {
        'action': {'type': 'pay'},
        'label': _lit('Pay'),
        'longPress': {'type': 'peek'},
        'longPressLabel': _lit('Peek'),
      },
      'children': [textNode('Pay now')],
    };

    testWidgets('a long press is not also a tap', (tester) async {
      final calls = <String>[];
      await pumpDocument(tester, docWith([card()]), onAction: (action, _) => calls.add(action.type));
      final gesture = await tester.startGesture(tester.getCenter(find.text('Pay now')));
      await tester.pump(const Duration(milliseconds: 900));
      await gesture.up();
      await tester.pump();
      expect(calls, ['peek']);
    });

    testWidgets('a held Enter is one press', (tester) async {
      final calls = <String>[];
      await pumpDocument(tester, docWith([_button('pay', {'type': 'pay'})]), onAction: (action, _) => calls.add(action.type));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      for (var i = 0; i < 10; i += 1) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, ['pay']);
    });

    testWidgets('a double tap is two actions (documented: idempotency is the host job)', (tester) async {
      final calls = <String>[];
      await pumpDocument(tester, docWith([_button('pay', {'type': 'pay'})]), onAction: (action, _) => calls.add(action.type));
      await tester.tap(find.text('pay'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('pay'));
      await tester.pump();
      expect(calls, ['pay', 'pay']);
    });
  });

  group('writes', () {
    Map<String, Object?> writer(String id, String path) => _button(id, {'type': 'setValue', 'params': {'path': path, 'value': 'x'}});

    testWidgets('nothing is written without a gesture', (tester) async {
      final writes = <String>[];
      await pumpDocument(
        tester,
        docWith([
          writer('w', 'account.period'),
          {
            'id': 'name',
            'type': 'TextField',
            'props': {'label': _lit('Name'), 'value': {'kind': 'binding', 'path': 'user.name', 'fallback': ''}},
          },
          {
            'id': 'ok',
            'type': 'Switch',
            'props': {'label': _lit('Ok'), 'value': {'kind': 'binding', 'path': 'user.ok', 'fallback': false}},
          },
        ]),
        data: {'user.name': 'Ann', 'user.ok': true},
        onWrite: (path, value) => writes.add(path),
      );
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
    });

    testWidgets('control: a safe path is written on a tap', (tester) async {
      final writes = <String>[];
      await pumpDocument(tester, docWith([writer('w', 'account.period')]), onWrite: (p, v) => writes.add(p));
      await tester.tap(find.text('w'));
      await tester.pump();
      expect(writes, ['account.period']);
    });

    for (final path in ['__proto__.x', 'constructor', 'user.__proto__', 'a..b', '', 'x' * 200, 'user name']) {
      testWidgets('an unsafe path is never written: "${path.length > 20 ? '${path.substring(0, 20)}…' : path}"', (tester) async {
        final writes = <String>[];
        await pumpDocument(tester, docWith([writer('w', path)]), onWrite: (p, v) => writes.add(p));
        await tester.tap(find.text('w'));
        await tester.pump();
        expect(writes, isEmpty);
      });
    }

    testWidgets('writablePaths: the host can limit the paths a document writes', (tester) async {
      // Called dynamically so that the file compiles while the parameter does not exist.
      final writes = <String>[];
      final doc = docWith([writer('w', 'user.balance')]);
      late Widget screen;
      try {
        screen = Function.apply(renderDocument, [doc], {
          #theme: RenderTheme.fallback(),
          #data: const <String, Object?>{},
          #onWrite: (String p, Object v) => writes.add(p),
          #writablePaths: (String path) => path.startsWith('form.'),
        }) as Widget;
      } on NoSuchMethodError {
        fail('renderDocument has no writablePaths parameter: any document can write any safe path to onWrite');
      }
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
      await tester.tap(find.text('w'));
      await tester.pump();
      expect(writes, isEmpty);
    });
  });
}
