import 'package:flutter/foundation.dart';

/// The version compatibility mechanism.
///
/// The reader does not compare the document version for exact equality: a
/// document either matches or is "not ours", and that cannot tell a widget from
/// a future version apart from a mistake in the document.
///
/// The artifact has an `x-compatibility` block: a machine-readable degradation
/// policy and a map from widget to the version where it appeared. This file is
/// the Dart mirror of both; `test/schema_version_test.dart` compares the mirror
/// with the artifact, so they cannot drift silently.

/// How many records a repeater draws at most.
///
/// A number from the CONTRACT, not a renderer decision: if each platform chose
/// its own, the same document would show a different number of rows in the
/// builder and on the phone.
const int kMaxRepeaterItems = 50;

/// The bounds of the grid column count, also from the CONTRACT and for the same
/// reason as [kMaxRepeaterItems]: if each platform chose its own, the same
/// document would be laid out differently in the builder and on the phone.
///
/// One column is a `Column`, so the minimum is two; the maximum comes from the
/// arithmetic of a narrow phone (at 360dp a fifth column is about 65dp, which
/// is no longer a card).
const int kGridMinColumns = 2;
const int kGridMaxColumns = 4;

/// How many columns a grid takes when `columns` is not a number. A schema
/// default, not a renderer choice.
const int kGridDefaultColumns = 2;

/// The document contract version this renderer understands.
///
/// Deliberately separate from [kWidgetCatalog]: the catalog arrives with the
/// artifact and may be fresher than the code, and that difference is what
/// recognizes a "widget from the future". A version change can alter a
/// capability or a field's shape without showing in the catalog at all, so the
/// only thing that stops a document of another major version before this code
/// is the version rule below.
const String kSupportedSchemaVersion = '9.20.0';

/// The document semver: exactly three numbers as in the schema, with no suffixes or pre-releases.
@immutable
final class SchemaVersion implements Comparable<SchemaVersion> {
  const SchemaVersion(this.major, this.minor, this.patch);

  static final RegExp _pattern = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$');

  final int major;
  final int minor;
  final int patch;

  static SchemaVersion? tryParse(String? text) {
    if (text == null) return null;
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    return SchemaVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(SchemaVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is SchemaVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

// The verdict of the compatibility rule. It mirrors the builder's
// `VersionVerdict`: both sides must answer "can this be read" the same way.
/// Whether a reader can read a document or a theme of a given version.
///
/// The rule: the major version must match; a newer minor is readable.
enum VersionVerdict {
  // Same major and the document's minor is not newer than ours: all is understood.
  /// Same major, and the minor is not newer than the reader's.
  ok,

  // The document's minor is newer. It CAN be read: the contract policy promises
  // that minor changes only add optional fields, so anything unfamiliar shows
  // up at most as an unknown widget or token, which degrades gently.
  /// Same major, newer minor. Readable: minor versions only add optional
  /// parts, and unknown ones degrade by the compatibility policy.
  newerMinor,

  // A different major version CANNOT be read in either direction: the structures
  // are incompatible. But there are TWO directions, and they differ in who can
  // do something about it.
  //
  // The reference implementation (`checkVersion`) uses one word for both,
  // `major_mismatch`, and so does the contract policy (`majorMustMatch`). The
  // distinction lives in the readers (here and in `@hotlayout/react`:
  // `document-newer` / `document-older`) and only concerns WHAT TO TELL THE
  // PERSON; it does not change the contract.
  //
  // A document of a NEWER major: the app is out of date and the user can update
  // it. This is the only case where there is something worth saying aloud.
  /// The document's major version is newer than the reader's. Not readable;
  /// a newer app would read it, so "update the app" is true.
  newerMajor,

  // A document of an OLDER major (8.x for a 9.x reader): updating the app does
  // not help, since a newer reader does not read the old major either. It is
  // fixed by republishing from the builder, so the user can do nothing.
  /// The document's major version is older than the reader's. Not readable,
  /// and updating the app does not help: the document has to be republished
  /// from the builder.
  olderMajor,

  // Not semver at all: `schemaVersion` is missing or corrupted.
  /// The version is missing or is not `major.minor.patch`. Not readable.
  unparsable;

  // Whether the renderer should draw such a document at all.
  /// Whether the document should be drawn at all.
  bool get canRender => this == ok || this == newerMinor;

  // What the reference implementation and the policy call by one word. Needed
  // where the direction does not matter: the document source falls back to the
  // bundled copy in both cases.
  /// Whether the major version differs, in either direction ([newerMajor] or
  /// [olderMajor]).
  bool get isMajorMismatch => this == newerMajor || this == olderMajor;
}

/// The rule in place of equality: the major version must match, and a newer
/// minor is readable.
///
/// It rests on the `minorAdditionsAreOptional` promise of `x-compatibility`: if
/// a minor version ever adds a required field, this very rule starts to lie.
///
/// The rule is deliberately NOT tied to the widget schema: there are two
/// independently versioned contracts (`screen-schema.json` and `theme.json`)
/// and their numbers are unrelated. What they share is not a number but the
/// question "can this be read", so there is one function and the reader's
/// version is a parameter.
VersionVerdict checkContractVersion(String? version, {required String readerVersion}) {
  final document = SchemaVersion.tryParse(version);
  final reader = SchemaVersion.tryParse(readerVersion);
  if (document == null || reader == null) return VersionVerdict.unparsable;
  if (document.major != reader.major) {
    return document.major > reader.major ? VersionVerdict.newerMajor : VersionVerdict.olderMajor;
  }
  if (document.minor > reader.minor) return VersionVerdict.newerMinor;
  return VersionVerdict.ok;
}

/// The same rule for the widget contract, with the renderer's version by
/// default. The separate name only makes the call site easier to read.
VersionVerdict checkSchemaVersion(
  String? documentVersion, {
  String readerVersion = kSupportedSchemaVersion,
}) => checkContractVersion(documentVersion, readerVersion: readerVersion);

/// The map from widget type to the schema version where it appeared.
///
/// Mirror of `x-compatibility.widgets`. It is updated together with the
/// artifact, which is why it may run ahead of [kSupportedSchemaVersion]: the
/// renderer code ships through the store, while the contract copy updates
/// separately.
const Map<String, String> kWidgetCatalog = {
  'Screen': '1.0.0',
  'AppBar': '6.0.0',
  'Column': '1.0.0',
  'Row': '2.0.0',
  'Container': '2.0.0',
  'Accordion': '3.0.0',
  'ChoiceGroup': '6.0.0',
  'Spacer': '1.0.0',
  'Divider': '1.0.0',
  'Text': '1.0.0',
  'Image': '1.0.0',
  'Icon': '2.0.0',
  'Button': '1.0.0',
  'ListTile': '1.0.0',
  'ProgressBar': '2.0.0',
  'Badge': '2.0.0',
  'Repeater': '8.4.0',
  'Grid': '8.5.0',
  'Stack': '8.6.0',
  'CircularProgress': '8.7.0',
  'Tabs': '8.8.0',
  'Tab': '8.8.0',
  // The icon button. A 9.4 reader sees it as `unknownWidget`, an empty place.
  'IconButton': '9.5.0',
  // The bottom navigation bar and its item (9.12.0). A 9.11 reader sees them as
  // `unknownWidget`, an empty place, with no way to reach another section.
  'NavBar': '9.12.0',
  'NavItem': '9.12.0',
  // Input fields (9.13.0). A 9.12 reader sees them as `unknownWidget`: a form without fields.
  'TextField': '9.13.0',
  'Switch': '9.13.0',
  'Checkbox': '9.13.0',
};

/// Mirror of `x-compatibility.features`: capability to the schema version it
/// came from.
///
/// A sibling of [kWidgetCatalog] that exists for the same reason: without it,
/// "the reader did not show a translation" and "the reader does not know the
/// word localization at all" look the same. The widget catalog cannot answer
/// that, because localization is not a widget.
///
/// It is read like the catalog: a value NEWER than [kSupportedSchemaVersion]
/// means "the document can do something this code cannot yet". `unboundedText`
/// is the case the map exists for: a capability visible neither in the set of
/// widgets nor in the shape of fields. A document that names it tells the
/// reader "I may have a 300-character heading"; a reader without it has to
/// fail on the version rule rather than draw truncated text and pretend all is
/// well.
const Map<String, String> kFeatureCatalog = {
  'localization': '7.2.0',
  'unboundedText': '8.0.0',
  'containerDirection': '8.1.0',
  'boundImageSource': '8.2.0',
  // A node-level style override. The gentlest degradation in the catalog: a
  // reader without it draws the node BY THE THEME, as it always did. Only the
  // deviation from the design system is lost, which is why the override refers
  // to a token and not to a value.
  'nodeStyle': '8.3.0',
  // Node STATES: "condition to style", the first one whose condition holds
  // applies. The degradation is as gentle as for `nodeStyle`: a reader without
  // it draws the node with the BASE style, as it always did. The distinction
  // between states is lost, not the content of the screen.
  'nodeStyleCases': '8.9.0',
  // Named entry points. A reader without it opens the document from the start
  // screen, as it always did: addressability is lost, not content.
  'entryPoints': '8.10.0',
  // Horizontal scrolling of a row. The only 8.11.0 capability whose loss costs
  // CONTENT: a reader without it draws an ordinary row, which cuts off whatever
  // does not fit the screen width, and there is no way to reach the rest.
  'rowScroll': '8.11.0',
  // A card's border and set height. A reader without them draws the card with
  // no border and as tall as its content, as always: layout changes, content does not.
  'containerFrame': '8.11.0',
  // How an image is fitted. A reader without it draws `cover`, exactly what the
  // author avoided by choosing `contain`: the frame crops a logo at the edges.
  'imageFit': '8.11.0',
  // A screen shown OVER the previous one. A reader without it opens the modal as
  // an ordinary screen: content is whole, buttons work, "back" returns; what is
  // lost is exactly the context that was meant to stay visible beneath it. Not
  // a zero loss, but not a destructive one.
  'modalScreens': '8.12.0',
  // Repeater instances arranged in a grid. A reader without it draws the list as
  // a column: all records are present and legible, the LAYOUT is what is lost,
  // and a grid of badges becomes a long column. Noticeable, but not broken.
  'repeaterGrid': '8.13.0',
  // A layer that fills the whole stack. A reader without it draws the layer at
  // its own size, and a gradient strip has no content of its own, i.e. zero
  // pixels. The layer does not "look different", it is not visible at all: an
  // element of the screen disappears, not a decoration.
  'stackFill': '8.14.0',
  // A share of the row width. A reader without it draws the child at its own
  // width, as it always did. What is lost is the PROPORTION: a diagram of
  // containers of different weights becomes a row of equal bars, so the screen
  // tells a falsehood about the data rather than merely looking different.
  'rowWeights': '8.17.0',
  // An absent value counts as empty. A reader without it applies the old rule,
  // "no value, so the condition does not hold", and hides the EMPTY STATE
  // exactly when it is needed: a "nothing yet" message does not appear on a
  // screen without data. The rest of the screen is whole and nothing crashes.
  'missingDataIsEmpty': '8.18.0',
  // Three element state colours. A reader without them draws the node in the
  // field's default colour (`unknownToken: 'fallback-to-field-default'`): the
  // screen is whole, but a locked task is no longer distinguished from an
  // available one by colour. A loss of SIGNAL, not of structure: the other
  // state cues (caption, icon, conditional style) stay in place.
  'elementStateColors': '8.19.0',
  // The format of a bound value: a date from data is shown as a date rather than
  // an ISO string. A reader without it skips the unknown key and draws the
  // value as is, exactly as it did before 8.20.0. Ugly but truthful: the value
  // on screen is the same, only its look is lost.
  'bindingFormat': '8.20.0',
  // The three 9.0.0 entries are listed for completeness, not for degradation:
  // this is a major version, and an 8.x reader does not open a 9.x document at
  // all (`majorMustMatch`).
  'openTokens': '9.0.0',
  'tokenOrValue': '9.0.0',
  'sharedNodeStyle': '9.0.0',
  // The device locale finds the document language (9.1.0). A reader without it
  // compares literally: `ar-EG` on a document with `ar` shows the source
  // language. The document shape is unchanged, so the degradation is gentle but
  // not zero: a person does not see their own language even though a
  // translation exists.
  'localeLookup': '9.1.0',
  'recordScope': '9.2.0',
  // The icon library (9.3.0): the list of names grew from 10 to 332, and the
  // drawing became contract data. A reader without it cannot draw a new name
  // and leaves an empty box of the same size (`unknownIcon`). A reader of 9.2,
  // already shipped, did not know this rule and draws a star in that place.
  'iconLibrary': '9.3.0',
  // Text templates and plurals (9.4.0): a string of `kind: 'template'`. A
  // reader without it shows an empty place instead of such a string
  // (`unknownStringKind: 'render-empty'`): the node and its neighbours are
  // whole, the text is missing. The loss is bigger than for formats, since a
  // whole sentence disappears, which is why the capability is named.
  'textTemplate': '9.4.0',
  // The `number`, `currency` and `daysUntil` formats (9.4.0). A reader without
  // them draws the value as is (`unknownBindingFormat`): "1850" instead of
  // "1,850", an ISO string in place of a number of days. Truthful, but
  // unreadable for `daysUntil`.
  'numberFormats': '9.4.0',
  // An icon in a button and a badge, and the button size (9.5.0). A reader
  // without it draws the button and badge with no icon and at the default size:
  // the caption is in place, only the look is lost.
  'iconBesideLabel': '9.5.0',
  // The "icon beside text" rule as data (9.5.0): gap, centre, colour and order
  // are the same for a button, a badge and the trailing slot of a row. The
  // document shape did not change; what changed is the interpretation where the
  // contract was silent (in this reader, the colour of a row's trailing text).
  'iconBesideTextRule': '9.5.0',
  // Composed text (9.6.0): `Text.spans`. A reader without it draws the string in
  // one style: the text is the same, only the styles of the parts are lost.
  'textSpans': '9.6.0',
  // The template value `kind: 'text'` (9.6.0). A reader without it shows an
  // empty place instead of the word (`unknownTemplateValueKind`): the sentence
  // stays, the word is missing from it.
  'templateWord': '9.6.0',
  // Bar and ring (9.7.0): `thickness`, `trackColor`, `gradient`. A reader
  // without them draws the scale as before: solid, with the default thickness
  // and track.
  'progressLook': '9.7.0',
  // Ring diameter from the node's box (9.7.0). A reader without it takes the
  // diameter from the `size` word.
  'ringDiameterFromBox': '9.7.0',
  // Scale geometry and paint as data (`x-style.layout.progress`, 9.7.0).
  'progressGeometry': '9.7.0',
  // The action catalog and related (9.8.0). A reader without them hands
  // `openUrl`, `deeplink` and `close` to the host as an unknown action, with no
  // verdict on the URL; it does not read `paramBindings`, `track` or
  // `carryRecord` and sends no analytics or screen-shown events. Nothing opens
  // by itself, but nothing is checked either.
  'actionCatalog': '9.8.0',
  'actionParamBinding': '9.8.0',
  'actionTrack': '9.8.0',
  'screenShownEvent': '9.8.0',
  'carryRecord': '9.8.0',
  // Images, app bar, centre window, status bar request (9.9.0). A reader
  // without them reads a custom ratio as `16:9`; does not draw app bar actions,
  // and keeps the app bar fixed outside the scroll with only the body scrolling
  // (`appBarFixed`); draws the window as a sheet; does not pass the status bar
  // icon request to the host.
  'imageCustomRatio': '9.9.0',
  'imageBoxGeometry': '9.9.0',
  'appBarActions': '9.9.0',
  'appBarFixed': '9.9.0',
  'appBarTitleRoom': '9.9.0',
  'modalPlacement': '9.9.0',
  'modalLayerLook': '9.9.0',
  'statusBarIcons': '9.9.0',
  // Offset layering (9.10.0): `layer` on a stack child and `pull` on a flow
  // child. A reader without them draws the layer as an ordinary one and places
  // the node where the flow puts it.
  'layerPlacement': '9.10.0',
  'flowPull': '9.10.0',
  // Carousel and segmented progress (9.11.0): `carousel` in `Row` and
  // `Repeater`, `segments` and `currentColor` in `ProgressBar`. A reader without
  // them scrolls the row without snapping and dots, does not scroll a list laid
  // out as a row, and draws a solid bar.
  'carousel': '9.11.0',
  'progressSegments': '9.11.0',
  // 9.12.0: the bottom zone. A reader without it draws the pinned block as the
  // last child of the body (it scrolls with it), does not draw the bar, and
  // hands `navigate.section` to the host as an app action.
  'bottomNavigation': '9.12.0',
  'pinnedBottom': '9.12.0',
  'sectionSwitch': '9.12.0',
  'bottomSafeInset': '9.12.0',
  // 9.13.0: input fields. A reader without them draws no fields at all
  // (`unknownWidget`); the worse case, "a field exists but nothing is recorded",
  // cannot occur.
  'textField': '9.13.0',
  'toggles': '9.13.0',
  'inputDisabledIf': '9.13.0',
  // 9.14.0: a survey form. A 9.13 reader does not know the minor's fields: the
  // button is always enabled, the numeric field writes a string, and there is no
  // asterisk (`unreadableRequired`).
  'inputRequired': '9.14.0',
  'pressDisabled': '9.14.0',
  'numberInput': '9.14.0',
  // 9.16.0: the app bar from a design. A 9.15 reader draws the zone's icon button
  // as one more action, does not draw a captioned button among the app bar's
  // children, centres the title, and sizes the glyph by the word.
  'appBarLeadingNode': '9.16.0',
  'appBarTitleAlign': '9.16.0',
  'ownGlyphSize': '9.16.0',
  // 9.17.0: text emphasis, list item marker, own style of the ring label. A 9.16
  // reader skips the fields: upright text, no marker, the label is
  // `caption` / `onSurface`.
  'textEmphasis': '9.17.0',
  'listMarker': '9.17.0',
  'ringLabelStyle': '9.17.0',
  // 9.18.0: adaptivity by width, step 1. A 9.17 reader draws the base (the phone
  // layout) at every width, shows nodes with `showOn` at all widths, does not
  // read `styleOn` / `propsOn` and does not know `contentMaxWidth`
  // (`olderReader`).
  'widthClassVisibility': '9.18.0',
  'widthClassStyle': '9.18.0',
  'widthClassProps': '9.18.0',
  'screenContentMaxWidth': '9.18.0',
  // 9.18.0, step 2: the wide place. A 9.17 reader (and a reader without step 2)
  // draws the navigation bar at the bottom and the sheet from the bottom at every
  // width (`olderReader`): the screen works but looks like a phone.
  'navBarOnWide': '9.18.0',
  'modalSheetOnWide': '9.18.0',
  // 9.19.0: free composition. A 9.18 reader draws a column in a column and a deep tree too (it never
  // checked child types or depth), but skips `action` and `label` on a container: the card is not
  // pressable, the buttons and rows inside work (`olderReader`).
  'sameTypeNesting': '9.19.0',
  'treeDepthEight': '9.19.0',
  'pressableContainer': '9.19.0',
  // 9.20.0: motion of a node and blur. A 9.19 reader skips the fields: the node stands, the modal layer has only
  // its scrim, and a node has no glass (`olderReader`).
  'nodeMotion': '9.20.0',
  'backdropBlur': '9.20.0',
};

/// Whether THIS code supports a capability the document names.
///
/// A separate function rather than an inline comparison, because the question is
/// the same as for a widget from the future, and answering it in two different
/// ways is the shortest path to disagreement.
bool supportsFeature(String feature, {String readerVersion = kSupportedSchemaVersion}) {
  final since = SchemaVersion.tryParse(kFeatureCatalog[feature]);
  final reader = SchemaVersion.tryParse(readerVersion);
  if (since == null || reader == null) return false;
  return since.compareTo(reader) <= 0;
}

/// Where a node the renderer did not draw came from.
enum WidgetOrigin {
  /// The type is in the catalog and not from the future, so the renderer should
  /// be able to draw it. It really means one thing: the code lags behind its own
  /// copy of the contract.
  contractual,

  /// The type is in the catalog but appeared in a version newer than
  /// [kSupportedSchemaVersion]. A normal situation in server-driven UI: the
  /// builder can already do it, the mobile app cannot yet.
  fromFuture,

  /// The type is not in the catalog at all: the contract knows nothing about it.
  /// This is not "the future" but a broken document or a typo by the author.
  outsideContract,
}

/// Classifies an unknown type. The map `x-compatibility.widgets` exists in the
/// artifact for exactly this: without it "Chart" and "Colunm" look the same.
///
/// The catalog and the reader's version are parameters, not globals: otherwise
/// this logic could not be tested, because the renderer's catalog is always full.
WidgetOrigin widgetOriginOf(
  String type, {
  Map<String, String> catalog = kWidgetCatalog,
  String readerVersion = kSupportedSchemaVersion,
}) {
  final since = SchemaVersion.tryParse(catalog[type]);
  if (since == null) return WidgetOrigin.outsideContract;
  final reader = SchemaVersion.tryParse(readerVersion);
  if (reader == null) return WidgetOrigin.outsideContract;
  return since.compareTo(reader) > 0 ? WidgetOrigin.fromFuture : WidgetOrigin.contractual;
}

/// An explanation for the debug placeholder and logs. Not used in release: the
/// word "Chart" tells an end user nothing.
String describeWidgetOrigin(
  String type,
  WidgetOrigin origin, {
  Map<String, String> catalog = kWidgetCatalog,
}) => switch (origin) {
  WidgetOrigin.fromFuture =>
    'Widget "$type" is from version ${catalog[type] ?? '?'}, newer than this app',
  WidgetOrigin.outsideContract => 'Widget "$type" is not in the contract',
  WidgetOrigin.contractual => 'Widget "$type" is in the contract, but the renderer does not draw it',
};
