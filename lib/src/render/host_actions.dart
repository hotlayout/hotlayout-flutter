/// A ready `onRecordAction` for the host: one handler per app-specific action
/// type, the checked standard actions, and one place for everything else.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/action.dart';
import '../model/action_catalog.dart';

/// One press handed to the host, as [HostActions] gives it to a handler.
@immutable
final class HostActionCall {
  /// Creates a call; [HostActions] does this for every action it receives.
  const HostActionCall({required this.action, required this.nodeId, this.record});

  /// The action as the renderer handed it over (parameters after the data
  /// bindings were applied).
  final ButtonAction action;

  /// The id of the node that was pressed.
  final String nodeId;

  /// The record of that node: the list row it is drawn in over the record the
  /// screen was opened with, as a flat map of data paths; `null` when there is
  /// none. User input: validate an id on your backend before you act on it.
  final Map<String, Object?>? record;

  /// The action type, as written in the document (`redeem`, `copy`, …).
  String get type => action.type;

  /// The action parameters (strings only).
  Map<String, String> get params => action.params;

  /// The value of [key]: the action parameter first, then the [record] at the
  /// same path, as text. `null` when neither has it.
  ///
  /// A shortcut for the usual "which item" question: a `redeem` button in a
  /// list row may name the id as a parameter or simply be pressed inside the
  /// row whose record carries `reward.id`.
  String? valueOf(String key) {
    final param = params[key];
    if (param != null) return param;
    final fromRecord = record?[key];
    return switch (fromRecord) {
      null => null,
      final String text => text,
      final num number => number.toString(),
      final bool flag => flag.toString(),
      _ => null,
    };
  }

  @override
  String toString() => 'HostActionCall($action, node: $nodeId)';
}

/// Handles one app-specific action. May be asynchronous: a `redeem` that
/// writes to a database returns its `Future`.
typedef HostActionHandler = FutureOr<void> Function(HostActionCall call);

/// Why [HostActions] did not perform an action.
enum HostActionMiss {
  /// No handler is registered for this type.
  noHandler,

  /// A standard action (`openUrl`, `deeplink`, `close`) whose executor was not
  /// given, or whose scheme is not one of `deeplinkSchemes`.
  noExecutor,

  /// A standard action whose parameter failed the form check
  /// ([ButtonAction.invalid]). It is never performed.
  invalid,

  /// The handler of the same type is still running (a second tap on a
  /// `redeem` button while the first one is being written).
  busy,
}

/// The host's actions, routed by type: pass [handle] to `renderDocument` as
/// `onRecordAction`.
///
/// ```dart
/// final actions = HostActions(
///   handlers: {
///     'redeem': (call) => rewards.redeem(call.valueOf('reward.id')),
///     'copy': (call) => Clipboard.setData(ClipboardData(text: call.valueOf('text') ?? '')),
///   },
///   openUrl: (url) => launchUrl(Uri.parse(url)),
///   deeplinkSchemes: const {'myapp'},
///   openDeeplink: (url) => launchUrl(Uri.parse(url)),
/// );
/// // …
/// renderDocument(document, theme: theme, data: data, onRecordAction: actions.handle);
/// ```
///
/// The order is fixed:
///
///  1. a standard action of the catalog (`openUrl`, `deeplink`, `close`) goes
///     to [runStandardAction] with the executors given here — it is checked
///     there, and [handlers] never see these types;
///  2. any other type goes to its handler in [handlers];
///  3. whatever was not performed goes to [onMiss], with the reason.
///
/// A handler that returns a `Future` blocks the same type until it completes
/// ([HostActionMiss.busy]): two quick taps on "redeem" redeem once. Pass
/// `exclusive: false` to run every press. An error of a handler — thrown or
/// from its `Future` — goes to [onError]; without it, to
/// `FlutterError.reportError`. It never reaches the renderer.
///
/// What a handler answers is shown through your data: write the result where
/// your data stream comes from (`redemption.status`, `redemption.code`) and
/// pass the new data to `renderDocument`; the open screen follows it.
class HostActions {
  /// Creates the router. [handlers] are keyed by action type; the standard
  /// types `openUrl`, `deeplink` and `close` are not accepted there (use
  /// [openUrl], [openDeeplink] and [close], which only run checked actions).
  HostActions({
    Map<String, HostActionHandler> handlers = const {},
    this.openUrl,
    this.deeplinkSchemes,
    this.openDeeplink,
    this.close,
    this.onMiss,
    this.onError,
    this.exclusive = true,
  }) : handlers = Map.unmodifiable(handlers) {
    for (final type in handlers.keys) {
      if (_standardTypes.contains(type)) {
        throw ArgumentError.value(
          type,
          'handlers',
          'is a standard action; pass openUrl, openDeeplink or close instead, which perform it only after its check',
        );
      }
    }
  }

  static const Set<String> _standardTypes = {kOpenUrlActionType, kDeeplinkActionType, kCloseActionType};

  /// Handlers of app-specific actions, by type.
  final Map<String, HostActionHandler> handlers;

  /// Opens an `https` address of `openUrl`; see [runStandardAction].
  final void Function(String url)? openUrl;

  /// The link schemes your app owns; `deeplink` is never performed without them.
  final Iterable<String>? deeplinkSchemes;

  /// Opens a `deeplink` of one of [deeplinkSchemes].
  final void Function(String url)? openDeeplink;

  /// Closes the flow on `close` (the renderer does not touch its stack).
  final VoidCallback? close;

  /// An action that was not performed, and why. `navigate.back` from the first
  /// screen and a `navigate` to a screen the document lacks arrive here too,
  /// unless a handler is registered for them.
  final void Function(HostActionCall call, HostActionMiss reason)? onMiss;

  /// An error thrown by a handler or completed into its `Future`.
  final void Function(HostActionCall call, Object error, StackTrace stack)? onError;

  /// Whether a running asynchronous handler blocks presses of the same type.
  final bool exclusive;

  final Set<String> _running = {};

  /// The types whose asynchronous handler is running now.
  @visibleForTesting
  Set<String> get running => Set.unmodifiable(_running);

  /// The `onRecordAction` of `renderDocument`, `ScreenFlow` and `renderScreen`.
  void handle(ButtonAction action, String nodeId, Map<String, Object?>? record) {
    final call = HostActionCall(action: action, nodeId: nodeId, record: record);
    if (_standardTypes.contains(action.type)) {
      if (action.invalid != null) {
        onMiss?.call(call, HostActionMiss.invalid);
        return;
      }
      final done = _guard(
        call,
        () => runStandardAction(
          action,
          openUrl: openUrl,
          deeplinkSchemes: deeplinkSchemes,
          openDeeplink: openDeeplink,
          close: close,
        ),
      );
      if (done == false) onMiss?.call(call, HostActionMiss.noExecutor);
      return;
    }

    final handler = handlers[action.type];
    if (handler == null) {
      onMiss?.call(call, HostActionMiss.noHandler);
      return;
    }
    if (exclusive && _running.contains(action.type)) {
      onMiss?.call(call, HostActionMiss.busy);
      return;
    }
    final result = _guard(call, () => handler(call));
    if (result is Future<void>) {
      if (exclusive) _running.add(action.type);
      result.then<void>((_) {}, onError: (Object error, StackTrace stack) => _report(call, error, stack)).whenComplete(() {
        if (exclusive) _running.remove(action.type);
      });
    }
  }

  /// Runs [body], reporting a synchronous error instead of throwing it into the renderer.
  /// `null` when it threw.
  T? _guard<T>(HostActionCall call, T Function() body) {
    try {
      return body();
    } catch (error, stack) {
      _report(call, error, stack);
      return null;
    }
  }

  void _report(HostActionCall call, Object error, StackTrace stack) {
    final onError = this.onError;
    if (onError != null) {
      onError(call, error, stack);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'hotlayout_flutter',
        context: ErrorDescription('while handling the host action "${call.type}" of node "${call.nodeId}"'),
      ),
    );
  }
}
