// The modal layer of the screen stack: scrim, sheet or centred window.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/media_chrome_rules.dart';
import '../model/wide_chrome_rules.dart';
import 'motion.dart';
import 'screen_zones.dart';

/// Key of the modal layer's box, for tests that measure its rectangle.
@visibleForTesting
const Key kModalLayerKey = ValueKey<String>('hotlayout-modal-layer');

/// A sheet shown on a wide place as a WINDOW (schema 9.18.0): the screen in the layer cannot
/// tell this from its own width (that is 560, `compact`), so the layer tells it through this
/// scope. The root of such a layer takes its bottom corner radius from the top ones and has no
/// bottom safe area inset.
class SheetWindowScope extends InheritedWidget {
  const SheetWindowScope({super.key, required this.sheetWindow, required super.child});

  final bool sheetWindow;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetWindowScope>()?.sheetWindow ?? false;

  @override
  bool updateShouldNotify(SheetWindowScope oldWidget) => oldWidget.sheetWindow != sheetWindow;
}

/// The modal layer: a sheet sliding in from the bottom, or a window in the middle (schema
/// 9.9.0).
///
/// A stateful widget of our own, not `showModalBottomSheet`: the renderer has its own screen
/// stack (the document arrives whole and its screens are flow pages, not app routes), and
/// handing the host's `Navigator` over for the sake of an animation would change the
/// architecture for an effect.
///
/// The geometry is [modalBoxOf], checked against the `modalCases` table: a sheet spans the
/// area's full width and is pressed to the bottom; a window is the area minus an `xl` margin on
/// each side, at most 400 wide, centred on both axes. The height follows the content, at most
/// the available height; taller content scrolls INSIDE the layer (the screen root carries the
/// scroll). The layer has no built-in look: background, radius and shadow come from the screen
/// root's `style`. The scrim is black at 0.45 over the whole area; a touch outside the window
/// is `navigate.back`, like the system "back".
///
/// Only the APPEARANCE is animated. Disappearing is instant, by choice: a closing frame would
/// have to be kept in the stack after it was removed, i.e. an "almost removed screen" would
/// become flow state. The cost is a concept everyone touching navigation must keep in mind; the
/// benefit is 200 ms the user does not wait for anyway, as they are already looking at where they
/// returned. The sheet slides in, the window fades in (the contract is silent about motion).
class ModalLayer extends StatefulWidget {
  const ModalLayer({
    super.key,
    required this.onDismiss,
    required this.sheet,
    required this.placement,
    required this.windowMargin,
  });

  final VoidCallback onDismiss;
  final Widget sheet;
  final ModalPlacement placement;

  /// Margin of the window (`center.margin`, step `xl`), dp.
  final double windowMargin;

  @override
  State<ModalLayer> createState() => _ModalLayerState();
}

class _ModalLayerState extends State<ModalLayer> with SingleTickerProviderStateMixin {
  // The layer moves between sheet and window when the area changes its width class (rotation,
  // split screen): the key keeps the same subtree, so typed text and focus are not lost.
  final GlobalKey _layerSlot = GlobalKey(debugLabel: 'hotlayout-modal-layer');
  late final AnimationController _controller = AnimationController(vsync: this, duration: Motion.sheet);

  @override
  void initState() {
    super.initState();
    /*
     * The duration is taken in the first frame, not in the constructor: `MediaQuery` cannot be
     * read during `initState`. Zero here means "the system asks for no motion": the controller
     * then jumps to the end and the layer simply appears.
     */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.duration = motionOf(context, Motion.sheet);
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = CurvedAnimation(parent: _controller, curve: Motion.enter);
    // The on-screen keyboard (`rules.focus.modal`): the layer rises above it instead of staying
    // under it. The keyboard height comes from the reader's own `MediaQuery` context; a host that
    // has already shrunk the screen gives zero.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // The top safe inset (schema 9.19.0, `safeTop.modal`): none INSIDE the layer; the sheet is no taller
    // than the area below the inset, the window is centred in it, and the scrim covers the whole area,
    // the status bar strip included.
    final safeTop = topInsetOf(context);

    return LayoutBuilder(
      builder: (context, area) {
        // The area the host gave the screen. If infinite, neither scrim nor placement would be
        // visible; then the layer takes what its content has.
        final viewportWidth = area.hasBoundedWidth ? area.maxWidth : 0.0;
        final viewportHeight = area.hasBoundedHeight ? area.maxHeight : double.infinity;
        // HOW THE LAYER IS SHOWN (`modalShapeOf`): decided by the width class of the AREA the host
        // gave the screen, not of the layer. A sheet without the word `center` is a window in the
        // middle on `medium` / `expanded`; an infinite width is "unknown", i.e. `compact`.
        final shape = modalShapeOf(widget.placement.wire, viewportWidth);
        final window = shape != ModalShape.sheet;
        final sheetWindow = shape == ModalShape.sheetWindow;
        // The content is measured at the LAYER's width, not the area's: the rule says the window width,
        // and the screen root has no sizes of its own (`x-style.screenExcluded`). The content's width
        // class comes from this box: 560 < 600, so it is `compact`.
        final layerWidth = area.hasBoundedWidth
            ? modalLayerWidthOf(widget.placement.wire, viewportWidth, widget.windowMargin)
            : null;
        final raisedHeight = viewportHeight.isFinite
            ? math.max(0.0, viewportHeight - keyboard - safeTop)
            : viewportHeight;
        final availableHeight = !viewportHeight.isFinite
            ? double.infinity
            : sheetWindow
            ? math.max(0.0, math.min(raisedHeight * kWideModalMaxHeightShare, raisedHeight - 2 * widget.windowMargin))
            : window
            ? math.max(0.0, raisedHeight - 2 * widget.windowMargin)
            : raisedHeight;

        // The scrim does not see a touch INSIDE the layer: the layer is a box, not just its opaque
        // places (a root with no background is a transparent layer).
        final layer = Listener(
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            key: kModalLayerKey,
            constraints: BoxConstraints(
              minWidth: window ? (layerWidth ?? 0) : 0,
              maxWidth: window ? (layerWidth ?? double.infinity) : double.infinity,
              maxHeight: availableHeight,
            ),
            // The layer above the keyboard has already accounted for it: the screen inside does not
            // subtract it a second time nor add a safe area inset where the keyboard covers it.
            child: keyboard > 0 || safeTop > 0
                ? MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      viewInsets: MediaQuery.viewInsetsOf(context).copyWith(bottom: 0),
                      viewPadding: MediaQuery.viewPaddingOf(context).copyWith(
                        top: 0,
                        bottom: keyboard > 0 ? 0 : null,
                      ),
                      padding: MediaQuery.paddingOf(context).copyWith(top: 0, bottom: keyboard > 0 ? 0 : null),
                    ),
                    child: SheetWindowScope(sheetWindow: sheetWindow, child: widget.sheet),
                  )
                : SheetWindowScope(sheetWindow: sheetWindow, child: widget.sheet),
          ),
        );
        final slot = KeyedSubtree(key: _layerSlot, child: layer);

        return AnimatedBuilder(
          animation: progress,
          builder: (context, _) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDismiss,
                  // The scrim thickens along with the layer's appearance: otherwise the screen under it would
                  // darken before it becomes clear why.
                  child: ColoredBox(color: Colors.black.withValues(alpha: kModalScrimOpacity * progress.value)),
                ),
              ),
              if (window)
                Padding(
                  padding: EdgeInsets.only(top: safeTop, bottom: keyboard),
                  child: Center(
                    child: Opacity(opacity: progress.value, child: slot),
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.only(top: safeTop, bottom: keyboard),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    /*
                     * The offset is in FRACTIONS OF THE LAYER'S OWN HEIGHT, not pixels: a sheet may be three
                     * rows or half the screen, and both must slide in the same way, from behind their own
                     * bottom edge. Pixels would give short sheets a long path from nowhere.
                     */
                    child: FractionalTranslation(translation: Offset(0, 1 - progress.value), child: slot),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
