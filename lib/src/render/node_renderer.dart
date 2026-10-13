/// Draws the nodes of a screen: the context a subtree is drawn with and the
/// dispatch from a node to its widget.
library;

import 'package:flutter/material.dart';

import '../data/screen_data.dart';
import '../model/action.dart';
import '../model/bindable.dart';
import '../model/carousel_rules.dart';
import '../model/list_marker.dart';
import '../model/localization.dart';
import '../model/media_chrome_rules.dart';
import '../model/node.dart';
import '../model/node_style.dart';
import '../model/shown_text.dart';
import '../model/text_emphasis.dart';
import '../model/tokens.dart';
import '../model/width_class.dart';
import '../theme/render_theme.dart';
import 'carousel.dart';
import 'choice_scope.dart';
import 'host_callbacks.dart';
import 'inputs.dart';
import 'labels.dart';
import 'render_scope.dart';
import 'screen_form.dart';
import 'widgets/app_bar.dart';
import 'widgets/button.dart';
import 'widgets/column.dart';
import 'widgets/grid.dart';
import 'widgets/image.dart';
import 'widgets/input_fields.dart';
import 'widgets/leaves.dart';
import 'widgets/list_tile.dart';
import 'widgets/nav_bar.dart';
import 'widgets/node_box.dart';
import 'widgets/overlay.dart';
import 'widgets/progress.dart';
import 'widgets/repeater.dart';
import 'widgets/row.dart';
import 'widgets/screen.dart';
import 'widgets/tabs.dart';
import 'widgets/text.dart';

class NodeRenderer {
  NodeRenderer({
    required this.theme,
    required this.data,
    this.strings = LocalizedStrings.none,
    this.locale,
    required this.now,
    this.onAction,
    this.onWrite,
    this.choice,
    this.inherited,
    this.insideListItem = false,
    this.labels = const RendererLabels(),
    this.carouselMemory,
    this.instance = const [],
    this.shownScreenId = '',
    this.form,
    this.listInstance,
  });

  /// Instance of a list-item template from data: the number and group size of THIS instance.
  /// Only for a `Repeater` template that is itself a numbered item.
  final ListInstance? listInstance;

  /// The screen's form: the root and data layers of the screen, from which a button with
  /// `requiresFilled` learns whether the form is filled. One per screen.
  final ScreenForm? form;

  /// The screen this renderer paints (`ScreenEntry.screenId`): from it the navigation bar knows
  /// which item is active (`isActiveNavAction`).
  final String shownScreenId;

  /// The theme to draw with.
  final RenderTheme theme;
  final ScreenData data;

  /// The stack frame's carousel memory and the chain of template instance indices from the root
  /// to this node: together with the node `id` they give the state key ([carouselStateKey]).
  final CarouselMemory? carouselMemory;
  final List<int> instance;

  /// The renderer's own words (back arrow, image placeholder), in the host's language.
  final RendererLabels labels;

  /// Translations of the chosen language. Empty for a single-language document, in which case
  /// [text] returns exactly what the document says.
  final LocalizedStrings strings;

  /// The locale bound dates are formatted in.
  ///
  /// Separate from [strings]: for the default language the table is empty and names no language,
  /// while a date is needed in that case too.
  final String? locale;

  /// "Now" of this screen: `daysUntil` is counted from it.
  final DateTime now;

  final ActionHandler? onAction;

  /// Whether this node is painted in a `Repeater` instance (becomes `true` in [withListItem]).
  /// Together with [ScreenData.record] this is the action's origin: it decides which record
  /// `navigate` opens the screen with.
  final bool insideListItem;

  /// Hand the action upward together with this node's record scope.
  void emit(ButtonAction action, String nodeId) => onAction?.call(action, nodeId, (
    record: data.record,
    insideListItem: insideListItem,
    read: data.lookup,
  ));

  /// Where to write what the user changed in a bound field.
  final SduiValueWrite? onWrite;

  /// The selection of the group we are painting inside, or `null` for "no group".
  ///
  /// This is neither a node prop nor a document field but a render CONTEXT: a `ChoiceGroup` holds
  /// the choice and a row asks it. Otherwise "selected" would have to be put on the row, and a
  /// document with two selected rows would become expressible, which is exactly what the
  /// contract made structurally impossible.
  final ChoiceScope? choice;

  /// INHERITED FOREGROUND: colour and font named by the nearest ancestor. `null` means nobody
  /// named anything and the root applies ([currentForeground]).
  ///
  /// The same kind of context as [choice] and the list record: the value affects the whole
  /// subtree, so it travels down as a NEW RENDERER rather than a parameter of every method.
  /// `DefaultTextStyle` does not fit for two reasons: only `Text` and `Icon` read the inherited
  /// value (`x-style.readers`), while the captions of composite widgets do not, and
  /// `DefaultTextStyle` would recolour them too; and the value is held already RESOLVED, because
  /// "no token" means "the parent's stays", which is decided where the reference meets the theme.
  final Foreground? inherited;

  NodeRenderer copy({
    ScreenData? data,
    ChoiceScope? choice,
    Foreground? inherited,
    bool? insideListItem,
    List<int>? instance,
    ListInstance? listInstance,
  }) => NodeRenderer(
    theme: theme,
    data: data ?? this.data,
    strings: strings,
    locale: locale,
    now: now,
    onAction: onAction,
    onWrite: onWrite,
    choice: choice ?? this.choice,
    inherited: inherited ?? this.inherited,
    insideListItem: insideListItem ?? this.insideListItem,
    labels: labels,
    carouselMemory: carouselMemory,
    instance: instance ?? this.instance,
    shownScreenId: shownScreenId,
    form: form,
    listInstance: listInstance ?? this.listInstance,
  );

  /// The same renderer, but with a LIST RECORD in scope.
  ///
  /// A new renderer rather than a field, for the same reason as the choice group: the record
  /// affects the whole template subtree, and passing it down by hand would mean every paint
  /// method must know about it.
  ///
  /// [index] is the instance number; it goes into the carousel state key chain.
  NodeRenderer withListItem(String item, Object? value, int index) =>
      copy(data: data.withItem(item, value), insideListItem: true, instance: [...instance, index]);

  /// The same renderer, but for the subtree of a group.
  NodeRenderer withChoice(ChoiceScope scope) => copy(choice: scope);

  /// Foreground at this point of the tree. At the root it is `onSurface` and `bodyM` from the
  /// theme core (`x-style.root`), which is why the core is mandatory.
  Foreground get currentForeground =>
      inherited ??
      (
        color: theme.color(ColorToken.onSurface),
        style: theme.text(TypographyToken.bodyM),
        named: false,
        emphasis: TextEmphasis.root,
      );

  /// WHICH COLOUR TO PAINT A PART OF A COMPOSITE WIDGET WITH (`x-style.colorParts`).
  ///
  /// Mirrors the reference implementation's `partColorOf`. As long as NOBODY has named a colour, a
  /// composite widget (`ListTile`, `AppBar`, `Tab`, `Accordion`) is painted with its built-in
  /// colour [builtIn], as before schema 9.0.0. Once a colour is named on the node or an ancestor,
  /// the main parts take it and the secondary ones ([secondary]) take the same colour with the
  /// `x-style.secondaryOpacity` opacity.
  ///
  /// What is asked is the FLAG "a colour was named", not "the colour differs from the root's": a
  /// card that named `onSurface` explicitly also named a colour.
  Color partColor(ColorToken builtIn, {bool secondary = false}) {
    final foreground = currentForeground;
    if (!foreground.named) return theme.color(builtIn);
    final color = foreground.color;
    return secondary ? color.withValues(alpha: color.a * kSecondaryPartOpacity) : color;
  }

  /// A renderer for a node with this style and its subtree.
  ///
  /// Mirrors the reference implementation's `inheritTextStyle` with one difference that it does
  /// not have by construction: here a reference immediately becomes a value. A token the theme
  /// does not declare gives `null` and the context does NOT change, i.e. the parent's stays
  /// (`tokenWithoutFieldDefault: 'omit-field'` for inherited fields).
  ///
  /// The font is inherited WHOLE, not by fields: `{token: titleM, fontSize: 22}` on an ancestor
  /// and `caption` on a descendant give `caption`, not "caption at size 22".
  ///
  /// [own] is the style ALREADY with its state: the style after the state merge is inherited
  /// (`x-style.inheritance: 'after-case-merge'`), so a state that paints a card also paints the
  /// captions in it.
  NodeRenderer inheriting(NodeStyle? own) {
    final color = own?.color == null ? null : theme.resolveColor(own!.color!);
    final style = own?.typography == null ? null : theme.resolveTypography(own!.typography!);
    final parent = currentForeground;
    // Slant and line (schema 9.17.0) need no theme words; a named field replaces the inherited
    // one, an unread one (`null`) leaves the parent's.
    final emphasis = inheritTextEmphasis(
      parent.emphasis,
      fontStyle: own?.fontStyle,
      textDecoration: own?.textDecoration,
    );
    if (color == null && style == null && identical(emphasis, parent.emphasis)) return this;
    return copy(
      inherited: (
        color: color ?? parent.color,
        style: style ?? parent.style,
        // A token the theme does not know does NOT count as a named colour
        // (`unknownInheritedToken: 'keep-parent'`).
        named: parent.named || color != null,
        emphasis: emphasis,
      ),
    );
  }

  /// The text of a field, with data and translations together.
  ///
  /// One function for the whole renderer on purpose: otherwise "does a translation also belong
  /// here?" would have to be remembered at each of a dozen places where a caption is painted, and
  /// a forgotten place would look not like an error but like a string in the wrong language in
  /// the middle of a screen.
  ///
  /// The text for DISPLAY: the string after substitution with whitespace collapsed
  /// ([collapseShownWhitespace]).
  String text(BindableString value) => collapseShownWhitespace(value.resolve(data, strings, locale, now));


  /// The root's content is always made scrollable: the document is made by a manager in the
  /// admin, and no check guarantees the content fits a phone screen. The screen BODY scrolls;
  /// the app bar stands (`appBarScroll`).
  Widget renderRoot(
    UiNode root, {
    ScreenPresentationToken presentation = ScreenPresentationToken.page,
    ModalPlacement placement = ModalPlacement.bottom,
    WidthClass widthClass = WidthClass.compact,
  }) => switch (root) {
    ScreenNode() => buildScreen(
      root,
      shrink: presentation == ScreenPresentationToken.modal,
      window: presentation == ScreenPresentationToken.modal && placement == ModalPlacement.center,
      widthClass: widthClass,
    ),
    // A root without `Screen` is not described by the schema, but the renderer survives it.
    final ChildNode node => SingleChildScrollView(
      child: node.isVisible(data)
          ? renderNode(node, flow: Axis.vertical)
          : const SizedBox.shrink(),
    ),
  };

  /// Conditional visibility. The LIST is filtered, not a single node: otherwise a hidden node
  /// would leave its `gap` behind, and a screen with a condition would look different from one
  /// where the node is simply absent.
  List<ChildNode> visibleNodes(List<ChildNode> nodes) {
    _numberSiblings(nodes);
    // The commonest case is no condition in the list; then nothing is copied.
    if (nodes.every((node) => !node.hasVisibilityRule)) return nodes;
    return [for (final node in nodes) if (node.isVisible(data)) node];
  }

  /// NUMBERING OF LIST ITEMS (`listMarker.number`). Computed over the CHILDREN OF ONE PARENT BY
  /// THE DOCUMENT, before conditionally hidden ones are filtered out: a group is numbered
  /// siblings in a row (another node, a hidden one too, breaks it); the number is how many
  /// VISIBLE items of the group stand up to and including it; the column width follows the group
  /// size by the document. The result is put on the node (`Expando`), and [buildText] reads it
  /// at once, in the same build pass.
  ///
  /// The parent's type does not matter: a column, a row, a stack and carousel cards are counted
  /// the same, as siblings in a row (like `listNumberOf` over `children` in the reference
  /// implementation). The one exception is a `Repeater` template: its group is its instances
  /// ([listInstance]).
  void _numberSiblings(List<ChildNode> nodes) {
    if (!nodes.any((node) => node is TextNode && node.marker == TextMarker.number)) return;
    final markers = [for (final node in nodes) node is TextNode ? drawnMarkerOf(node.marker) : null];
    final visible = [for (final node in nodes) node.isVisible(data)];
    for (var i = 0; i < nodes.length; i += 1) {
      final number = listNumberOf(markers, i, visible);
      final groupSize = listMarkerGroupSize(markers, i);
      if (number == null || groupSize == null) continue;
      siblingNumbers[nodes[i]] = (number: number, groupSize: groupSize);
    }
  }

  Widget renderBody(ChildNode node, NodeStyle? own, {bool naturalRow = false, Slot slot = Slot.free}) =>
      switch (node) {
        // An `AppBar` gets here only out of place: the screen takes a correctly placed bar for itself
        // in [buildScreen]. It is painted anyway; the renderer does not decide for the manager what to
        // drop from the document.
        AppBarNode() => buildAppBar(node),
        ColumnNode() => buildColumn(node, own, slot),
        RowNode() => buildRow(node, own, naturalRow: naturalRow),
        ContainerNode() => buildContainer(node, own, slot, naturalRow: naturalRow),
        GridNode() => buildGrid(node),
        StackNode() => buildOverlay(node),
        TabsNode() => buildTabs(node),
        TabNode() => buildTab(node),
        AccordionNode() => buildAccordion(node),
        ChoiceGroupNode() => buildChoiceGroup(node),
        RepeaterNode() => buildRepeater(node, own),
        SpacerNode() => buildSpacer(node),
        DividerNode() => buildDivider(node),
        TextNode() => buildText(node),
        ImageNode() => buildImage(node),
        IconNode() => buildIcon(node),
        ButtonNode() => buildButton(node, own),
        IconButtonNode() => buildIconButton(node, own),
        // A navigation bar that is not in the bottom zone (not the last child of the root, or not on
        // the root): an ordinary child where it stands, without a safe area inset (`navBarNotLast`).
        // An item outside the bar is not a child (`insideOtherThanScreenRoot`): only the bar paints it.
        NavBarNode() => buildNavBar(node, own, safeBottom: 0, zone: false),
        NavItemNode() => const SizedBox.shrink(),
        ListTileNode() => buildListTile(node),
        ProgressBarNode() => buildProgressBar(node),
        CircularProgressNode() => buildCircularProgress(node, own, slot),
        BadgeNode() => buildBadge(node, own),
        TextFieldNode() => buildTextField(node),
        SwitchNode() => buildToggle(node, InputToggleKind.switchControl, node.label, node.valuePath, node.disabledIf),
        CheckboxNode() => buildToggle(
          node,
          InputToggleKind.checkbox,
          node.label,
          node.valuePath,
          node.disabledIf,
          mandatory: node.required,
        ),
        UnknownNode() => buildUnknown(node),
      };

}

