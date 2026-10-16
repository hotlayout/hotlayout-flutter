/// What the screen stack draws: the frame of one screen and the modal layers
/// over the last page.
part of 'screen_flow.dart';

extension _ScreenFlowStack on _ScreenFlowState {
  Widget _frameAt(_Frame frame, int index) {
    return KeyedSubtree(
      // Keyed by position in the stack, not just `screenId`: returning to the same screen must
      // restore it from scratch rather than show the state of the previous one.
      key: ValueKey('sdui-screen-${index + 1}-${frame.screen.screenId}'),
      // The identity of the frame (its carousel memory): a new flow is a new frame at the same
      // stack position, and the old one's scroll state does not carry over through a position key
      // match.
      child: KeyedSubtree(
        key: ObjectKey(frame.memory),
        child: screenWidget(
          frame.screen,
          theme: widget.theme,
          data: widget.data,
          params: frame.params,
          record: frame.record,
          links: frame.links,
          session: _session,
          // The scope is asked for on EVERY frame, not at navigation: host data may arrive later than
          // the navigation (network), and the screen must then repaint with it rather than stay with
          // fallbacks forever.
          scopeFor: widget.scopeFor,
          strings: widget.doc.stringsFor(widget.locale),
          locale: _formatLocale,
          now: widget.now,
          handler: _handleAction,
          onWrite: _write,
          autofill: widget.autofill,
          labels: widget.labels,
          memory: frame.memory,
          presentation: index == 0 ? ScreenPresentationToken.page : frame.screen.presentation,
        ),
      ),
    );
  }

  /// The EFFECTIVE SHOW of the screen of frame [index] (`shownLookOf`): the ONE place that
  /// answers for both painting and the show event. The first screen of a flow (the bottom of
  /// the stack: the initial one, one named by an entry point, the start of a new flow) is always
  /// a page, even if the document called it modal: a layer that lies ON something has nothing
  /// under it. The layout is then a page's (no layer `shrink`), and the event says `page`
  /// without `modalPlacement`.
  ScreenPresentationToken _presentationAt(int index) =>
      index == 0 ? ScreenPresentationToken.page : _stack[index].screen.presentation;

  /// One modal layer: a scrim over the whole frame and a sheet from the bottom.
  ///
  /// A tap on the scrim is `navigate.back`, not a separate kind of action: closing a modal and
  /// going back one step are the same thing, and a second way back would diverge from the first
  /// at the first change.
  ///
  /// The layer SLIDES IN rather than appearing. A sheet that pops up instantly reads as a
  /// repainted screen, not as something laid OVER it, i.e. the very thing the presentation mode
  /// exists for disappears. Here motion carries meaning rather than decorating.
  Widget _modalLayer(_Frame frame, int index, {bool closing = false}) => ModalLayer(
    // Keyed by the frame: a layer that starts closing keeps its state (scroll, fields) while it
    // sinks away.
    key: ObjectKey(frame.memory),
    placement: frame.screen.placement,
    backdropBlur: frame.screen.backdropBlur,
    windowMargin: _windowMargin,
    dismissible: frame.screen.dismissible,
    animateIn: identical(frame.memory, _enteringLayer),
    closing: closing,
    onClosed: closing ? () => _layerClosed(frame.memory) : null,
    // The scrim is not a node, so it has no record of its own: the host (if "back" would leave the
    // flow) gets the layer's record.
    onDismiss: () => _handleAction(
      const ButtonAction(ButtonAction.navigateBack),
      frame.screen.screenId,
      (record: frame.record, insideListItem: false, read: readNothing, links: frame.links),
    ),
    sheet: _frameAt(frame, index),
  );

  /// One scene: the page a list of frames paints at the bottom, and its modal layers over it.
  ///
  /// A scene that is not [current] is one moving away or revealed for a moment (a page step, an
  /// edge swipe, a section switch): it takes no touches and is not announced.
  Widget _scene(List<_Frame> frames, {required bool current}) {
    /*
     * WHAT IS PAINTED: the last NON-modal frame, and over it all the modal ones above it in the
     * stack.
     *
     * One rule for any depth, which matters more than the case "one modal over one page": a modal
     * opened from a modal is painted by the same code, not by a separate branch nobody would test.
     *
     * The search starts from the TOP of the stack, not the bottom: under a modal the screen it was
     * opened from must remain, not the initial one.
     */
    final base = _baseOf(frames);
    final baseMemory = frames[base].memory;
    final leaving = current
        ? [
            for (final layer in _leaving)
              if (identical(layer.base, baseMemory)) _modalLayer(layer.frame, layer.index, closing: true),
          ]
        : const <Widget>[];
    final atRest = base == frames.length - 1 && leaving.isEmpty;

    /*
     * The `Stack` is ALWAYS there, layer or not: the bottom frame stays at the same place in the
     * tree, so opening and closing a modal layer does not mount the page anew (scroll, fields,
     * focus and carousel memory are kept). Without a layer the frame's size is the same as it
     * would be: `passthrough` hands it the parent's constraints as they are.
     */
    final scene = KeyedSubtree(
      key: _sceneKey(frames),
      child: Stack(
        fit: atRest ? StackFit.passthrough : StackFit.loose,
        children: [
          _frameAt(frames[base], base),
          for (var i = base + 1; i < frames.length; i += 1) _modalLayer(frames[i], i),
          ...leaving,
        ],
      ),
    );
    return IgnorePointer(
      ignoring: !current,
      child: ExcludeSemantics(excluding: !current, child: scene),
    );
  }

  Widget _buildStack() {
    final current = _scene(_stack, current: true);
    final move = _move;
    if (move == null) return Stack(fit: StackFit.passthrough, children: [current]);
    final other = _scene(move.other, current: false);
    final progress = move.controller;

    if (move.kind == _MoveKind.fade) {
      return AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final look = sectionSwitchLook(progress.value);
          return Stack(
            fit: StackFit.passthrough,
            children: [
              Opacity(opacity: look.outgoing, child: other),
              Opacity(opacity: look.incoming, child: current),
            ],
          );
        },
      );
    }

    final leavingOnTop = move.kind == _MoveKind.pop;
    final cupertino = cupertinoPagesOf(context);
    Widget page(PageRole role, Widget child) => PageMotion(
      role: role,
      progress: progress,
      forward: move.kind == _MoveKind.push,
      cupertino: cupertino,
      linear: _swiping,
      child: child,
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        page(PageRole.under, leavingOnTop ? current : other),
        page(PageRole.over, leavingOnTop ? other : current),
      ],
    );
  }
}
