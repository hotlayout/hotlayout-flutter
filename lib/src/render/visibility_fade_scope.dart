/// The fade of a node whose `visibleIf` changes (schema 9.33.0, `visibilityTransition: 'fade'`): the clock and the
/// widgets. The phases and their moments are the pure rules of `model/visibility_fade.dart`.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../model/visibility_fade.dart';

/// What the screen knows about the nodes that fade: the state of each, and the clock that moves them.
///
/// The clock is the ticker of the scope that owns the book, so it follows the frames of the app (and the fake time of a
/// test). While no node is in a transition the ticker is stopped. A node that is not yet known, or is seen under another
/// language or width class, or under "disable animations", stands at rest of its condition: there is no transition.
class FadeBook {
  FadeBook({required TickerProvider vsync, required VoidCallback onStructure}) : _onStructure = onStructure {
    _ticker = vsync.createTicker(_onTick);
  }

  final VoidCallback _onStructure;
  late final Ticker _ticker;
  final Map<String, _Entry> _entries = {};

  final ChangeNotifier _frames = _Frames();

  /// Tells the boxes of the nodes that fade that they should repaint (every frame while a transition runs).
  Listenable get frames => _frames;

  String _context = '';
  bool _animate = true;
  double _base = 0;
  double _elapsed = 0;

  /// Where the clock stands: milliseconds of the frames this book has run for.
  double get now => _base + _elapsed;

  /// A pass of drawing begins: [context] is what a change of makes a node stand at once (the width class and the
  /// language), [animate] is false under the system "disable animations".
  void begin({required String context, required bool animate}) {
    _context = context;
    _animate = animate;
  }

  /// Tells the book that the node under [key] has the condition [shown] now, and answers whether the node stands in
  /// the layout. Idempotent: the same answer is asked many times in a pass of drawing.
  bool sync(String key, bool shown) {
    final entry = _entries[key];
    if (entry == null) {
      final created = _Entry(shown, _context, visibilityFadeRest(shown, now));
      _entries[key] = created;
      return visibilityFadeInLayout(created.state.phase);
    }
    if (entry.context != _context) {
      entry
        ..context = _context
        ..shown = shown
        ..state = visibilityFadeRest(shown, now);
    } else if (entry.shown != shown) {
      entry
        ..shown = shown
        ..state = visibilityFadeChange(entry.state, shown, now, animate: _animate);
      _wake();
    }
    return visibilityFadeInLayout(entry.state.phase);
  }

  /// What the node under [key] draws now.
  VisibilityFadeFrame frameOf(String key) {
    final entry = _entries[key];
    return entry == null ? visibilityFadeAt(visibilityFadeRest(true), 0) : visibilityFadeAt(entry.state, now);
  }

  void _wake() {
    if (_ticker.isActive) return;
    _elapsed = 0;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed.inMicroseconds / 1000;
    var structural = false;
    var running = false;
    for (final entry in _entries.values) {
      final next = visibilityFadeSettle(entry.state, now);
      if (next != entry.state) {
        if (visibilityFadeInLayout(next.phase) != visibilityFadeInLayout(entry.state.phase)) structural = true;
        entry.state = next;
      }
      if (visibilityFadeEndsAt(entry.state) != null) running = true;
    }
    if (!running) {
      // Nothing moves any more: the clock stops here and the next transition starts from this moment.
      _base += _elapsed;
      _elapsed = 0;
      _ticker.stop();
    }
    (_frames as _Frames).ping();
    if (structural) _onStructure();
  }

  void dispose() {
    _ticker.dispose();
    _frames.dispose();
  }
}

/// A notifier that can be pinged from outside its own class.
final class _Frames extends ChangeNotifier {
  void ping() => notifyListeners();
}

final class _Entry {
  _Entry(this.shown, this.context, this.state);

  bool shown;
  String context;
  VisibilityFadeState state;
}

/// Owns the [FadeBook] of one screen. The book lives as long as the screen is built, so going back to a screen makes
/// a new one: the nodes stand at rest.
class FadeScope extends StatefulWidget {
  const FadeScope({super.key, required this.builder});

  final Widget Function(BuildContext context, FadeBook fades) builder;

  @override
  State<FadeScope> createState() => _FadeScopeState();
}

class _FadeScopeState extends State<FadeScope> with SingleTickerProviderStateMixin {
  late final FadeBook _book = FadeBook(vsync: this, onStructure: _rebuild);

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _book.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _book);
}

/// The box of a node that fades: its opacity follows the book, a leaving node catches no press, takes no focus and
/// leaves the accessibility tree at once, an entering one is a control from the moment it enters the layout.
class FadeBox extends StatelessWidget {
  const FadeBox({super.key, required this.book, required this.entryKey, required this.child});

  final FadeBook book;
  final String entryKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: book.frames,
    builder: (context, _) {
      final frame = book.frameOf(entryKey);
      return Opacity(
        opacity: frame.opacity.clamp(0.0, 1.0),
        child: IgnorePointer(
          ignoring: !frame.interactive,
          child: ExcludeSemantics(
            excluding: !frame.interactive,
            child: ExcludeFocus(excluding: !frame.interactive, child: child),
          ),
        ),
      );
    },
  );
}
