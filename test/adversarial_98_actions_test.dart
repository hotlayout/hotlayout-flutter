/// HOSTILE-INPUT TESTS FOR THE 9.8.0 ACTIONS -- `hotlayout_flutter`.
///
/// Expectations are what is DECLARED (the 9.8.0 action catalog of the contract).
/// "HOLE" fails because the claim does not hold; "GUARD" is an attempt the defence repelled.
/// The package code was not changed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';

Object? _noData(String path) => null;

ButtonAction _handed(Map<String, Object?> raw, [Map<String, Object?> data = const {}]) =>
    ButtonAction.parse(raw).handOver((path) => data[path]);

void main() {
  group('HOLE 1: the verdict on an app link depends on Uri.tryParse, not only on the expression', () {
    // The form of a parameter is paramFormProblem(form, value), and only that. Do NOT call Uri.parse as a check.
    // React gives `standard` on these SAME strings -- two readers, two verdicts.
    for (final url in ['myapp://[x', 'myapp://]', 'myapp://h:abc/', 'myapp://a@b@c', 'myapp://[zz]/', 'myapp://a:b@[1]/']) {
      test('$url: the form passed -- action is `standard`', () {
        expect(paramFormProblem(ActionParamForm.appLink, url), isNull, reason: 'the contract expression accepts the string');
        final handed = _handed({
          'type': 'deeplink',
          'params': {'url': url},
        });
        expect(handed.invalid, isNull);
        expect(handed.standard, isA<DeeplinkAction>());
      });
    }
  });

  group('HOLE 2: the host gets a DIFFERENT address than the one checked (Uri normalises)', () {
    // The Uri in `standard` is built AFTER the expression check. The string was checked; what Uri made of it is open.
    for (final url in [
      'https://a.example/%zz',
      'https://a.example/%',
      'https://a.example/#a#b',
      'https://a.example/a/../../b',
      // `:00443` (leading zeros) is `invalid`; the string is kept in
      // `formCases`, and is absent here.
    ]) {
      test('$url: the Uri the host will open is the checked string', () {
        final handed = _handed({
          'type': 'openUrl',
          'params': {'url': url},
        });
        final standard = handed.standard;
        expect(standard, isA<OpenUrlAction>());
        expect((standard! as OpenUrlAction).url, url);
      });
    }

    test('myapp://h:99999999999999999999/: the fields of the checked Uri are readable without an exception', () {
      final handed = _handed({
        'type': 'deeplink',
        'params': {'url': 'myapp://h:99999999999999999999/'},
      });
      final standard = handed.standard;
      if (standard is! DeeplinkAction) return;
      // `url` is the checked STRING, `Uri` is only a getter (`null` when the
      // platform could not parse the address, and the verdict does not change).
      expect(() => standard.uri?.port, returnsNormally);
    });
  });

  group('HOLE 3: a `params` literal that is not a string -- Flutter turns it into text, React rejects it', () {
    // Schema: `params` is `additionalProperties: string`. For data, numbers must NOT be turned into text
    // (`3.0` is "3.0" in Dart, "3" in JS). For a literal the reader does exactly that.
    test('a number and a flag in params do not become a parameter', () {
      final handed = _handed({
        'type': 'pay',
        'params': {'amount': 3.0, 'confirmed': true, 'ok': 'x'},
      });
      expect(handed.params, {'ok': 'x'});
    });

    test('a key of the wrong form (space, empty, 33 characters) does not become a parameter', () {
      final handed = _handed({
        'type': 'pay',
        'params': {'url ': 'x', 'a b': 'x', '': 'x', 'k' * 33: 'x', 'ok': 'x'},
      });
      expect(handed.params.keys, ['ok']);
    });
  });

  group('ALIGNED WITH React (there was a DIVERGENCE)', () {
    test('navigate with paramBindings.screenId: the LITERAL applies both in the flow and in the action handed to the host', () {
      final action = ButtonAction.parse({
        'type': 'navigate',
        'params': {'screenId': 'safe'},
        'paramBindings': {'screenId': 'user.next'},
      });
      // `_handleAction` reads the action's `navigationTarget` FROM THE DOCUMENT, before `handOver`.
      expect(action.navigationTarget, 'safe');
      // ...and if screen `safe` does not exist and the action goes to the host, the catalog rule
      // (`navigate.screenId` is `bindable: false`) keeps the same literal, not
      // `admin` from the data: `admin` used to arrive here, and the host saw a different target
      // than the one the validator checked.
      expect(action.handOver((path) => path == 'user.next' ? 'admin' : null).params['screenId'], 'safe');
    });

    test('"other" action and a parameter the catalog does not name are read from data as before', () {
      final other = ButtonAction.parse({
        'type': 'pay',
        'params': {'orderId': 'literal'},
        'paramBindings': {'orderId': 'order.id'},
      });
      expect(other.handOver((path) => path == 'order.id' ? 'from-data' : null).params['orderId'], 'from-data');
      final open = ButtonAction.parse({
        'type': 'openUrl',
        'params': {'url': 'https://example.com/', 'target': 'literal'},
        'paramBindings': {'target': 'ui.target'},
      });
      expect(open.handOver((path) => path == 'ui.target' ? 'blank' : null).params['target'], 'blank');
    });

    test('track with the parameter key `constructor` or `prototype`: no event AT ALL', () {
      final action = ButtonAction.parse({
        'type': 'none',
        'track': {
          'event': 'offer_open',
          'params': {'constructor': 'x', 'prototype': 'y'},
        },
      });
      expect(action.track, isNull);
      // An event name with the same word -- too.
      for (final event in ['constructor', 'prototype']) {
        expect(ButtonAction.parse({'type': 'none', 'track': {'event': event}}).track, isNull, reason: event);
      }
    });
  });

  group('GUARD: form of an https address', () {
    for (final url in [
      'https://bank.example@evil.example/',
      r'https:\\evil.example/',
      r'https://bank.example\@evil.example/',
      r'https:/\evil.example',
      'https:///evil.example',
      'ht\ttps://evil.example',
      'https://bank.example/\n',
      'https://bank.example/\njavascript:alert(1)',
      ' https://bank.example',
      'HTTPS://bank.example',
      'https://bаnk.example',
      'https://bank．example',
      // ignore: text_direction_code_point_in_literal
      'https://bank.example‮elpmaxe.live',
      'https://bank.example./',
      'https://[::1]/',
      'https://bank.example%2eevil.example/',
      'https://bank.example:123456/',
      'https://bank.example/\u{1F600}',
      'https://bank.example/\u0000',
      'javascript:alert(1)',
      'http://bank.example',
    ]) {
      test('${Uri.encodeComponent(url)} -- invalid, the helper does not execute', () {
        final handed = _handed({
          'type': 'openUrl',
          'params': {'url': url},
        });
        expect(handed.standard, isNull);
        expect(handed.invalid?.param, 'url');
        var opened = 0;
        expect(runStandardAction(handed, openUrl: (_) => opened += 1), isFalse);
        expect(opened, 0);
      });
    }

    test('exactly 2048 passes; from data 2049 is "absent", the literal applies', () {
      const head = 'https://bank.example/';
      final exact = '$head${'a' * (2048 - head.length)}';
      expect(
        _handed({
          'type': 'openUrl',
          'params': {'url': exact},
        }).standard,
        isA<OpenUrlAction>(),
      );
      final bound = _handed(
        {
          'type': 'openUrl',
          'params': {'url': '${head}literal'},
          'paramBindings': {'url': 'offer.url'},
        },
        {'offer.url': '${exact}a'},
      );
      expect((bound.standard! as OpenUrlAction).url, '${head}literal');
    });
  });

  group('GUARD: app link and helper', () {
    for (final url in ['JavaScript:alert(1)', ' javascript:alert(1)', '\tjavascript:alert(1)', 'intent://x#Intent;end', 'file:///etc/passwd', 'content://sms/inbox']) {
      test('${Uri.encodeComponent(url)} -- not standard', () {
        final handed = _handed({
          'type': 'deeplink',
          'params': {'url': url},
        });
        expect(handed.standard, isNull);
        expect(
          runStandardAction(handed, deeplinkSchemes: ['javascript', 'intent', 'file', 'content'], openDeeplink: (_) {}),
          isFalse,
        );
      });
    }

    test('tel: is standard by form, but without the host list the helper does not execute', () {
      final handed = _handed({
        'type': 'deeplink',
        'params': {'url': 'tel:+380000000000'},
      });
      expect(handed.standard, isA<DeeplinkAction>());
      var opened = 0;
      expect(runStandardAction(handed, openDeeplink: (_) => opened += 1), isFalse);
      expect(runStandardAction(handed, deeplinkSchemes: ['myapp'], openDeeplink: (_) => opened += 1), isFalse);
      expect(opened, 0);
    });

    test('data is not a string -- "absent", the literal applies; a string of the wrong form does not replace the literal', () {
      const action = {
        'type': 'openUrl',
        'params': {'url': 'https://bank.example/literal'},
        'paramBindings': {'url': 'offer.url'},
      };
      for (final value in <Object?>[42, 3.0, true, ['https://evil.example'], {'a': 1}, '', null]) {
        final handed = _handed(action, {'offer.url': value});
        expect((handed.standard! as OpenUrlAction).url, 'https://bank.example/literal', reason: '$value');
      }
      final hostile = _handed(action, {'offer.url': 'javascript:alert(1)'});
      expect(hostile.standard, isNull);
      expect(hostile.invalid?.problem, ActionParamProblem.notHttps);
    });

    test('carryRecord is exactly true; an invalid track -- no event', () {
      for (final carry in <Object?>['true', 1, 'yes', <Object?>[], <String, Object?>{}]) {
        expect(ButtonAction.parse({'type': 'navigate', 'carryRecord': carry}).carryRecord, isFalse, reason: '$carry');
      }
      for (final track in <Object?>[
        {'event': 'buy\n'},
        {'event': 'buy now'},
        {'event': 'a' * 41},
        {
          'event': 'buy',
          'params': {for (var index = 0; index < 26; index += 1) 'p$index': 'x'},
        },
        {
          'event': 'buy',
          'params': {'amount': 10},
        },
        ['buy'],
      ]) {
        expect(ButtonAction.parse({'type': 'none', 'track': track}).track, isNull, reason: '$track');
      }
      expect(_noData('x'), isNull);
    });
  });
}
