/// What the screen stack draws: the frame of one screen and the modal layers
/// over the last page.
part of 'screen_flow.dart';

extension _ScreenFlowStack on _ScreenFlowState {
  Widget _frameAt(int index) {
    final frame = _stack[index];
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
          presentation: _presentationAt(index),
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
  Widget _modalLayer(
    Widget sheet, {
    required String nodeId,
    required Map<String, Object?>? record,
    required ModalPlacement placement,
    required double windowMargin,
  }) =>
      ModalLayer(
        placement: placement,
        windowMargin: windowMargin,
        // The scrim is not a node, so it has no record of its own: the host (if "back" would leave the
        // flow) gets the layer's record.
        onDismiss: () => _handleAction(
          const ButtonAction(ButtonAction.navigateBack),
          nodeId,
          (record: record, insideListItem: false, read: readNothing),
        ),
        sheet: sheet,
      );

  Widget _buildStack() {
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
    var base = _stack.length - 1;
    while (base > 0 && _stack[base].screen.presentation == ScreenPresentationToken.modal) {
      base -= 1;
    }

    final bottom = _frameAt(base);

    /*
     * The `Stack` is ALWAYS there, layer or not: the bottom frame stays at the same place in the
     * tree, so opening and closing a modal layer does not mount the page anew (scroll, fields,
     * focus and carousel memory are kept). Without a layer the frame's size is the same as it
     * would be: `passthrough` hands it the parent's constraints as they are.
     */
    return Stack(
      fit: base == _stack.length - 1 ? StackFit.passthrough : StackFit.loose,
      children: [
        bottom,
        for (var i = base + 1; i < _stack.length; i += 1)
          _modalLayer(
            _frameAt(i),
            nodeId: _stack[i].screen.screenId,
            record: _stack[i].record,
            placement: _stack[i].screen.placement,
            windowMargin: _windowMargin,
          ),
      ],
    );
  }
}
