import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/offset_rules.dart';
import 'package:hotlayout_flutter/src/model/record_scope.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/text_spans.dart';
import 'package:hotlayout_flutter/src/model/text_template.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import 'support/fixtures.dart';

/// Compatibility guard.
///
/// Before 5.0.0 this file compared versions for **exact equality**: the renderer and the
/// schema had to match character for character. Now the contract has a mechanism
/// (`x-compatibility`), so the test checks something else - that the renderer implements the
/// RULE itself and that its mirror of the artifact (policy + widget catalog) has not drifted
/// from the artifact.
void main() {
  final schema =
      jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync())
          as Map<String, Object?>;
  final compatibility = schema['x-compatibility'] as Map<String, Object?>;
  final policy = compatibility['policy'] as Map<String, Object?>;
  final widgets = (compatibility['widgets'] as Map<String, Object?>).cast<String, String>();
  final features = (compatibility['features'] as Map<String, Object?>).cast<String, String>();
  final defs = schema[r'$defs'] as Map<String, Object?>;

  group('schema version', () {
    test('the renderer declares the same version as the artifact', () {
      expect(schema['x-schemaVersion'], UiDocument.supportedSchemaVersion);
    });

    test('all golden documents are read by this renderer', () {
      for (final id in fixtureIds) {
        final doc = loadFixture(id);
        expect(
          doc.versionVerdict,
          VersionVerdict.ok,
          reason: 'fixture $id migrated without the renderer',
        );
        expect(doc.isSupportedVersion, isTrue);
      }
    });
  });

  group('compatibility rule instead of version equality', () {
    test('same major and not an older minor - we read', () {
      expect(checkSchemaVersion('6.0.0', readerVersion: '6.0.0'), VersionVerdict.ok);
      expect(checkSchemaVersion('6.0.1', readerVersion: '6.0.0'), VersionVerdict.ok);
      expect(checkSchemaVersion('6.1.0', readerVersion: '6.4.0'), VersionVerdict.ok);
    });

    test('an older document minor is read: a minor only adds optional fields', () {
      final verdict = checkSchemaVersion('6.3.0', readerVersion: '6.0.0');
      expect(verdict, VersionVerdict.newerMinor);
      expect(verdict.canRender, isTrue);
    });

    test('another major cannot be read - neither forward nor back', () {
      // It cannot be read in either direction, but the verdict SAYS which one: the side
      // determines whether there is anything to advise the person (see the banner group below).
      expect(checkSchemaVersion('7.0.0', readerVersion: '6.0.0'), VersionVerdict.newerMajor);
      expect(checkSchemaVersion('5.0.0', readerVersion: '6.0.0'), VersionVerdict.olderMajor);
      // Minor and patch do not affect the side: only the major counts.
      expect(checkSchemaVersion('5.99.9', readerVersion: '6.0.0'), VersionVerdict.olderMajor);
      expect(checkSchemaVersion('7.0.0', readerVersion: '6.99.9'), VersionVerdict.newerMajor);
      for (final verdict in VersionVerdict.values) {
        expect(
          verdict.isMajorMismatch,
          verdict == VersionVerdict.newerMajor || verdict == VersionVerdict.olderMajor,
        );
      }
      expect(VersionVerdict.newerMajor.canRender, isFalse);
      expect(VersionVerdict.olderMajor.canRender, isFalse);
      // Without an explicit reader - against the renderer constant, so the number must be
      // foreign. On the move 7.3.0 -> 8.0.0 this line had to be moved forward: 8.0.0
      // became OUR major, and the assertion that had proved "a foreign one is not read"
      // started proving the opposite. The symmetry is deliberate - a foreign major is read
      // neither from above nor from below.
      //
      // On the move 8.20.0 -> 9.0.0 the same happened a SECOND time, so now the numbers
      // are computed from the own version (`foreignMajorVersion`), not written.
      expect(checkSchemaVersion(foreignMajorVersion).canRender, isFalse);
      expect(checkSchemaVersion(previousMajorVersion).canRender, isFalse);
      // And separately, by number: a document 8.20.0 - the last before the move of the look
      // into `style` - is NOT drawn by this reader. Drawn "as it comes out", it would lose
      // all styling silently: its `Container.padding` simply does not exist here.
      expect(checkSchemaVersion('8.20.0'), VersionVerdict.olderMajor);
    });

    test('a version that is not semver or is absent - not read either', () {
      expect(checkSchemaVersion(null), VersionVerdict.unparsable);
      expect(checkSchemaVersion(''), VersionVerdict.unparsable);
      expect(checkSchemaVersion('6.0'), VersionVerdict.unparsable);
      expect(checkSchemaVersion('6.0.0-beta'), VersionVerdict.unparsable);
      expect(VersionVerdict.unparsable.canRender, isFalse);
    });

    test('versions are compared as numbers, not strings', () {
      expect(
        SchemaVersion.tryParse('6.10.0')!.compareTo(SchemaVersion.tryParse('6.9.0')!),
        greaterThan(0),
      );
      expect(SchemaVersion.tryParse('6.0.0'), SchemaVersion.tryParse('6.0.0'));
    });

    test('a document with a foreign major is still parsed - the verdict is separate from the parser', () {
      // The action to take for the version is a renderer decision at the display level, not
      // the parser's: parsing must reach the end so the host has something to say aloud.
      final doc = docWith([textNode('З майбутнього')], schemaVersion: foreignMajorVersion);

      expect(doc.versionVerdict, VersionVerdict.newerMajor);
      expect(doc.isSupportedVersion, isFalse);
      expect(doc.screens, hasLength(1));
    });
  });

  group('first real minor: 6.1.0 is read by a 6.0.0 reader', () {
    // This block was written and run BEFORE `kSupportedSchemaVersion` was raised to 6.1.0 -
    // otherwise it would prove something else. The `minorAdditionsAreOptional` promise has
    // to be checked from the side of the OLD reader: a new reader reads anything, and that
    // says nothing about an app already installed on people's phones.

    /// A 6.1.0 row - with an action the 6.0.0 reader does not know.
    Map<String, Object?> tileWithAction() => {
      'id': 'chance-tile',
      'type': 'ListTile',
      'props': {
        'leading': {'kind': 'icon', 'icon': 'gift'},
        'title': {'kind': 'literal', 'value': 'Обраний шанс на виграш'},
        'trailing': {'kind': 'chevron'},
        'action': {
          'type': 'navigate',
          'params': {'screenId': 'items'},
        },
      },
    };

    test('the rule allows reading - and this is a claim about the RULE, not the constant', () {
      // The reader version is a parameter, so the test stays valid after the
      // renderer itself moved to 6.1.0: it is still about the pair (6.1.0, 6.0.0).
      final verdict = checkSchemaVersion('6.1.0', readerVersion: '6.0.0');

      expect(verdict, VersionVerdict.newerMinor);
      expect(verdict.canRender, isTrue);
    });

    testWidgets('a document with an older minor draws all its content, not a version banner', (
      tester,
    ) async {
      // `.99.0` of the own major is a minor the renderer will never reach, so the
      // test stays a test about a NEWER minor, not about a specific number. On the day of
      // writing the string '6.1.0' against the constant 6.0.0 gave exactly the same.
      await pumpDocument(tester, docWith([tileWithAction()], schemaVersion: futureMinorVersion));

      expect(find.text('Обраний шанс на виграш'), findsOneWidget);
      expect(find.textContaining('Please update the app'), findsNothing);
    });

    test('a field from a future minor does not make the node unknown', () {
      // This is exactly how `ListTile.action` looked to the renderer yesterday: an extra
      // key in props. The promise of a minor is that such a key costs nothing
      // - neither the node nor the screen.
      final doc = docWith([
        {
          'id': 'tile',
          'type': 'ListTile',
          'props': {
            'leading': {'kind': 'none'},
            'title': {'kind': 'literal', 'value': 'Рядок із майбутнього'},
            'trailing': {'kind': 'none'},
            'somethingFromNextMinor': {'kind': 'literal', 'value': 42},
          },
        },
      ], schemaVersion: futureMinorVersion);

      final nodes = flattenDocument(doc).toList();
      expect(nodes.whereType<UnknownNode>(), isEmpty);
      expect(nodes.whereType<ListTileNode>().single.action, isNull);
    });

    test('a new prop does not change the widget catalog: ListTile stays 1.0.0 as it was', () {
      // Here is the limit of the 5.0.0 mechanism: `x-compatibility.widgets` versions
      // WIDGETS, while 6.1.0 added a capability to an existing widget. For the catalog
      // this change did not happen at all.
      expect(widgets['ListTile'], '1.0.0');
      expect(widgetOriginOf('ListTile'), WidgetOrigin.contractual);
    });
  });

  group('9.0.0: the look lives in `style` - schema shape = model shape', () {
    // The 9.0.0 major moved the look from `props` into the shared `node.style`. Until then
    // this group guarded the background union in three widgets (`SurfaceBackground`, 7.0.0);
    // now the background is one of fifteen style fields, and THAT is what has to be guarded:
    // that the model knows exactly the fields the schema describes, and that they are no
    // longer in `props`. The `x-compatibility.widgets` catalog does not show this at all,
    // so the shape mirror is held separately.

    Map<String, Object?> propertiesOf(String def) =>
        (defs[def] as Map<String, Object?>)['properties'] as Map<String, Object?>;

    test('style fields in the artifact are exactly the ones the model parses', () {
      // Every schema field with some legal value must REACH the model: a field the
      // schema knows and the reader silently skips is a look lost without any error
      // (`unknownStyleField: 'ignore-field'` would hide it).
      const sample = <String, Object?>{
        'color': 'primary',
        'typography': 'titleM',
        // 9.17.0: italics and text line.
        'fontStyle': 'italic',
        'textDecoration': 'lineThrough',
        'padding': 'md',
        'margin': 'sm',
        'width': 100,
        'height': 100,
        'minWidth': 10,
        'maxWidth': 200,
        'minHeight': 10,
        'maxHeight': 200,
        'radius': 'md',
        'border': {'width': 1, 'color': 'border'},
        'background': {'kind': 'color', 'color': 'surface'},
        'shadow': 'low',
        'opacity': 0.5,
        // 9.20.0: glass.
        'backdropBlur': 12,
        // 9.23.0: a gradient on the glyphs of a text.
        'textGradient': 'brandBackdrop',
      };
      expect(propertiesOf('NodeStyle').keys.toSet(), sample.keys.toSet());

      for (final field in sample.keys) {
        expect(
          NodeStyle.parse({field: sample[field]}),
          isNotNull,
          reason: 'style.$field: the schema describes it, the model does not read it',
        );
      }
    });

    test('background union branches in the artifact are exactly the ones the model knows', () {
      final branches = (defs['NodeBackground'] as Map<String, Object?>)['oneOf'] as List<Object?>;
      final kinds = <String>{
        for (final branch in branches.cast<Map<String, Object?>>())
          ((branch['properties'] as Map<String, Object?>)['kind'] as Map<String, Object?>)['const']
              as String,
      };

      expect(kinds, {'color', 'gradient', 'image'});
      expect(
        NodeBackground.tryParse(const {'kind': 'color', 'color': 'primary'}),
        isA<ColorBackground>(),
      );
      expect(
        NodeBackground.tryParse(const {'kind': 'gradient', 'gradient': 'brandBackdrop'}),
        isA<GradientBackground>(),
      );
      expect(
        NodeBackground.tryParse(const {
          'kind': 'image',
          'source': {'kind': 'asset', 'asset': 'banner'},
          'fit': 'cover',
        }),
        isA<ImageBackground>(),
      );
    });

    test('a token name in the schema is a pattern, not a list, and the pattern is the same', () {
      // The main 9.0.0 change in the vocabulary: the closed `enum`s of the six dictionaries
      // are gone, names are declared by the theme.
      for (final def in [
        'ColorToken',
        'SpacingToken',
        'RadiusToken',
        'TypographyToken',
        'ElevationToken',
        'GradientToken',
      ]) {
        final declared = defs[def] as Map<String, Object?>;
        expect(declared.containsKey('enum'), isFalse, reason: '$def is a closed list again');
        expect(declared['pattern'], kTokenNamePattern, reason: def);
      }
      final tokens = schema['x-tokens'] as Map<String, Object?>;
      expect(tokens['namePattern'], kTokenNamePattern);
      expect(tokens['declaredBy'], 'theme');
      expect(isTokenName('brandCoral'), isTrue);
      expect(isTokenName('Brand'), isFalse);
      expect(isTokenName('brand-coral'), isFalse);
      expect(isTokenName('a' * 41), isFalse);
    });

    test('the core of the dictionaries in the schema = the renderer lists, one to one', () {
      // The lists in `tokens.dart` are the names the renderer refers to ITSELF
      // (field defaults, chrome of composed widgets, the inheritance root). They
      // must be exactly the core: a name outside it a theme is not obliged to have.
      final core = (schema['x-tokens'] as Map<String, Object?>)['core'] as Map<String, Object?>;
      Set<String> coreOf(String name) => (core[name]! as List<Object?>).cast<String>().toSet();

      expect(coreOf('color'), ColorToken.values.map((token) => token.wire).toSet());
      expect(coreOf('gradient'), GradientToken.values.map((token) => token.wire).toSet());
      expect(coreOf('spacing'), SpacingToken.values.map((token) => token.wire).toSet());
      expect(coreOf('radius'), RadiusToken.values.map((token) => token.wire).toSet());
      expect(coreOf('elevation'), ElevationToken.values.map((token) => token.wire).toSet());
      expect(coreOf('typography'), TypographyToken.values.map((token) => token.wire).toSet());
      expect(core.keys.toSet(), {'color', 'gradient', 'spacing', 'radius', 'elevation', 'typography'});
    });

    test('look fields are no longer in `props` - and the model does not look for them there', () {
      // The list is from the "widget -> field -> where" table of contract 9.
      const moved = <String, List<String>>{
        'ScreenProps': ['background', 'padding'],
        'AppBarProps': ['background'],
        'ColumnProps': ['padding'],
        'RowProps': ['padding'],
        'GridProps': ['padding'],
        'StackProps': ['padding'],
        'RepeaterProps': ['padding'],
        'ChoiceGroupProps': ['padding'],
        'ContainerProps': ['padding', 'radius', 'background', 'elevation', 'border', 'height'],
        'TextProps': ['color', 'typography'],
        'ImageProps': ['radius'],
        'IconProps': ['color'],
      };
      for (final entry in moved.entries) {
        for (final prop in entry.value) {
          expect(
            propertiesOf(entry.key).containsKey(prop),
            isFalse,
            reason: '${entry.key}.$prop returned to props',
          );
        }
      }

      // The same from the model side: a look field left in `props` (an 8.x document
      // or a foreign generator) has NO effect on the node. Otherwise a field would have two
      // places, and two readers would diverge on which one is current.
      final screen =
          UiNode.parse({
                'id': 'root',
                'type': 'Screen',
                'props': {
                  'background': {'kind': 'color', 'color': 'surface'},
                  'padding': 'md',
                },
              })
              as ScreenNode;
      expect(screen.style, isNull, reason: 'a screen without `style` has no background or padding');
    });

    test('no hidden look defaults: a node without a style is a node without a style', () {
      expect((schema['x-style'] as Map<String, Object?>)['hiddenDefaults'], 'none');
      for (final node in flattenDocument(
        docWith([
          {'id': 'c', 'type': 'Container', 'props': {'gap': 'none'}, 'children': <Object?>[]},
          {'id': 'b', 'type': 'AppBar', 'props': {'title': {'kind': 'literal', 'value': 'П'}}},
          {'id': 'i', 'type': 'Image', 'props': <String, Object?>{}},
        ]),
      ).whereType<ChildNode>()) {
        expect(node.style, isNull, reason: contractType(node));
      }
    });

    test('style and states are on EVERY schema node, the screen included', () {
      final nodeDefs = [
        for (final key in defs.keys)
          if (key.endsWith('Node') && key != 'ChildNode') key,
      ];
      // 9.5.0: the twenty-third node is `IconButtonNode`; 9.12.0: the twenty-fourth and
      // twenty-fifth are `NavBarNode` and `NavItemNode`; 9.14.0 added no nodes; 9.13.0: the twenty-sixth to
      // twenty-eighth are `TextFieldNode`, `SwitchNode`, `CheckboxNode`.
      expect(nodeDefs, hasLength(28));
      for (final def in nodeDefs) {
        // The screen has its own style shape without `margin` and sizes (`ScreenStyle`,
        // `x-style.screenExcluded`); the other nodes have the shared one.
        final expected = def == 'ScreenNode' ? 'ScreenStyle' : 'NodeStyle';
        expect(propertiesOf(def)['style'], {r'$ref': '#/\$defs/$expected'}, reason: def);
        expect(propertiesOf(def).containsKey('styleWhen'), isTrue, reason: def);
      }

      final screen =
          UiNode.parse({
                'id': 'root',
                'type': 'Screen',
                'props': const <String, Object?>{},
                'style': {'padding': 'lg'},
                'styleWhen': [
                  {
                    'when': {'path': 'user.vip', 'op': 'isTrue'},
                    'style': {'background': {'kind': 'color', 'color': 'accent'}},
                  },
                ],
              })
              as ScreenNode;
      expect(screen.style?.padding, isNotNull);
      expect(screen.styleWhen, hasLength(1));
    });
  });

  group('x-style mirror on the Dart side', () {
    final style = schema['x-style'] as Map<String, Object?>;

    test('style reading rules are the ones the renderer implements', () {
      // Each row here is a place where two readers would otherwise diverge silently;
      // the behaviour behind each is held by `style_cases_test.dart`,
      // `style_inheritance_test.dart` and `style_box_test.dart`.
      expect(style['caseSelection'], 'first-match');
      expect(style['caseMerge'], 'top-level-fields');
      expect(style['inherited'], ['color', 'typography']);
      expect(style['inheritance'], 'after-case-merge');
      expect(style['sides'], 'logical');
      expect(style['unnamedSide'], 'zero');
      expect(style['hiddenDefaults'], 'none');
      expect(style['weightOverridesWidth'], isTrue);
      // `fill` beats `style.width` / `height`; the behaviour is held by
      // `stack_test.dart`.
      expect(style['fillOverridesSize'], isTrue);
      expect(style['unknownInheritedToken'], 'keep-parent');
      // The radius clips background AND content; opacity acts on the whole box with its shadow.
      expect(style['radiusClips'], ['background', 'content']);
      expect(style['opacityAppliesTo'], ['background', 'border', 'shadow', 'content']);
    });

    test('parts of composed widgets that take a named colour are the same', () {
      expect(style['colorParts'], {
        for (final entry in kColorParts.entries)
          entry.key: {'whenUnnamed': entry.value.whenUnnamed, 'parts': entry.value.parts},
      });
      expect(style['secondaryOpacity'], kSecondaryPartOpacity);
      // Colour readers are exactly those that have parts.
      expect(kTextStyleReaders['color']!.toSet(), kColorParts.keys.toSet());
    });

    test('fields the screen does not read are the ones in the `ScreenStyle` schema', () {
      expect(style['screenExcluded'], kScreenExcludedStyleKeys);
      // The root schema really lacks these fields, and has the rest.
      final screenProps = (defs['ScreenStyle'] as Map<String, Object?>)['properties']
          as Map<String, Object?>;
      final nodeProps = (defs['NodeStyle'] as Map<String, Object?>)['properties']
          as Map<String, Object?>;
      expect(
        nodeProps.keys.toSet().difference(screenProps.keys.toSet()),
        kScreenExcludedStyleKeys.toSet(),
      );
    });

    test('gradient geometry is named identically in both artifacts', () {
      final geometry = schema['x-gradientGeometry'] as Map<String, Object?>;
      final themeArtifact =
          jsonDecode(File('assets/contract/theme.json').readAsStringSync()) as Map<String, Object?>;
      expect(themeArtifact['x-gradientGeometry'], geometry);
      expect(geometry['direction'], contains('physical'));
      expect(geometry['equalStops'], 'ordered');
      expect(geometry['diagonal'], contains('to <corner>'));
    });

    test('theme-optional core colours - the same fallback map', () {
      final optional =
          (schema['x-tokens'] as Map<String, Object?>)['optionalInTheme'] as Map<String, Object?>;
      expect(optional, {'color': kThemeColorFallbacks});
    });

    test('inheritance root and the reader list are the same', () {
      expect(style['root'], {'color': kRootTextColor, 'typography': kRootTypography});
      expect(style['readers'], kTextStyleReaders);
      // The root must be from the CORE: otherwise the fallback has nothing
      // to lean on in a theme that declares no names of its own.
      expect(ColorToken.values.map((token) => token.wire), contains(kRootTextColor));
      expect(TypographyToken.values.map((token) => token.wire), contains(kRootTypography));
    });

    test('widgets with a role: the table, the field list and the border thickness are the same', () {
      final roles = style['roles'] as Map<String, Object?>;
      expect(roles['widgets'], {
        for (final entry in kRoleWidgets.entries)
          entry.key: {'prop': entry.value.prop, 'group': entry.value.group},
      });
      expect(roles['overridableBy'], kRoleStyleKeys);
      expect(roles['roleBorderWidth'], kRoleBorderWidth);
      expect(roles['default'], 'theme-role');
      expect(roles['override'], 'own-style-per-slot');
      expect(roles['inheritedColor'], 'does-not-override-role');
      expect(roles['appliesTo'], 'widget-surface');
    });

    test('`withoutRoleSurface` leaves the box exactly the fields the role does not take', () {
      // Guard of the list: a field added to `NodeStyle` and forgotten here would
      // vanish silently from a button - neither on the surface nor on the box.
      const full = <String, Object?>{
        'color': 'primary',
        'typography': 'titleM',
        'padding': 'md',
        'margin': 'sm',
        'width': 100,
        'height': 100,
        'minWidth': 10,
        'maxWidth': 200,
        'minHeight': 10,
        'maxHeight': 200,
        'radius': 'md',
        'border': {'width': 1, 'color': 'border'},
        'background': {'kind': 'color', 'color': 'surface'},
        'shadow': 'low',
        'opacity': 0.5,
      };
      for (final field in full.keys) {
        final box = NodeStyle.parse({field: full[field]})!.withoutRoleSurface;
        expect(
          box == null,
          kRoleStyleKeys.contains(field),
          reason: 'style.$field: ${kRoleStyleKeys.contains(field) ? 'surface' : 'box'}',
        );
      }
    });

    test('number bounds in the schema are the ones parsing clamps to', () {
      Map<String, Object?> numberBranch(String def) =>
          ((defs[def] as Map<String, Object?>)['anyOf'] as List<Object?>)
              .cast<Map<String, Object?>>()
              .firstWhere((branch) => branch['type'] == 'integer' || branch['type'] == 'number');

      expect(numberBranch('SpacingRef')['maximum'], kMaxSpacingPx);
      expect(numberBranch('RadiusRef')['maximum'], kMaxRadiusPx);
      expect(numberBranch('Dimension')['minimum'], kStyleSizeMin);
      expect(numberBranch('Dimension')['maximum'], kStyleSizeMax);

      final border = (defs['NodeBorder'] as Map<String, Object?>)['properties'] as Map<String, Object?>;
      expect((border['width'] as Map<String, Object?>)['minimum'], kMinBorderWidthPx);
      expect((border['width'] as Map<String, Object?>)['maximum'], kMaxBorderWidthPx);

      final gradient =
          (defs['CustomGradient'] as Map<String, Object?>)['properties'] as Map<String, Object?>;
      expect(
        ((gradient['angle'] as Map<String, Object?>)['enum'] as List<Object?>).toSet(),
        {...kAxisGradientAngles, ...kCornerGradientAngles},
      );
      expect((gradient['stops'] as Map<String, Object?>)['minItems'], kMinGradientStops);
      expect((gradient['stops'] as Map<String, Object?>)['maxItems'], kMaxGradientStops);

      final shadow = ((defs['ShadowRef'] as Map<String, Object?>)['anyOf'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((branch) => branch['type'] == 'array');
      expect(shadow['maxItems'], kMaxShadowLayers);

      final typography =
          (defs['TypographyOverride'] as Map<String, Object?>)['properties'] as Map<String, Object?>;
      expect((typography['fontSize'] as Map<String, Object?>)['minimum'], kMinFontSizePx);
      expect((typography['fontSize'] as Map<String, Object?>)['maximum'], kMaxFontSizePx);
      expect((typography['lineHeight'] as Map<String, Object?>)['minimum'], kMinLineHeight);
      expect((typography['lineHeight'] as Map<String, Object?>)['maximum'], kMaxLineHeight);
      expect((typography['letterSpacing'] as Map<String, Object?>)['minimum'], kMinLetterSpacingPx);
      expect((typography['letterSpacing'] as Map<String, Object?>)['maximum'], kMaxLetterSpacingPx);
    });
  });

  group('8.0.0: human text no longer has a length bound', () {
    // The 8.0.0 major added nothing and moved nothing - it REMOVED a limit.
    // Tests for that are written inside out: what must be proved is not the appearance of a
    // capability but the ABSENCE of a check. So here are two sides of one claim - "there is
    // no bound where a human reads the text" and "the bound stayed where the string is technical".

    test('there is one bindable string in the artifact, and it has no maxLength', () {
      // Before 8.0.0 there were six (`BindableString16/24/32/48/64/120`) - that was a
      // known wart of the artifact, and it was closed in 8.0.0.
      expect(defs.keys.where((k) => k.startsWith('BindableString')).toSet(), {
        'BindableString',
        // An exception, and a meaningful one: `optionValue` is not human text but the
        // option NAME that `ChoiceGroup.value` refers to. The bound here is about
        // an identifier, not about readability.
        'BindableString64',
      });

      final branches = (defs['BindableString'] as Map<String, Object?>)['oneOf'] as List<Object?>;
      for (final branch in branches.cast<Map<String, Object?>>()) {
        final props = branch['properties'] as Map<String, Object?>;
        for (final field in ['value', 'fallback']) {
          final declared = props[field] as Map<String, Object?>?;
          if (declared == null) continue;
          expect(
            declared.containsKey('maxLength'),
            isFalse,
            reason: 'BindableString.$field has a bound again - this is no longer 8.0.0',
          );
        }
      }
    });

    test('alt text and translation values are also unbounded', () {
      expect((defs['AltText'] as Map<String, Object?>).containsKey('maxLength'), isFalse);

      final strings =
          ((defs['Localization'] as Map<String, Object?>)['properties']
              as Map<String, Object?>)['strings'] as Map<String, Object?>;
      final perLocale = strings['additionalProperties'] as Map<String, Object?>;
      final value = perLocale['additionalProperties'] as Map<String, Object?>;
      expect(value.containsKey('maxLength'), isFalse);
      // An empty translation is still not a translation: one bound remained here, and it is
      // not about length but about presence.
      expect(value['minLength'], 1);
    });

    test('identifiers and technical strings KEPT their bound', () {
      // The most important test of the group. "No more bounds" is untrue, and if someone
      // ever reads 8.0.0 that way, the bounds that hold not readability but
      // addressing will disappear: an id must stay an id.
      int? maxOf(String def, String prop) =>
          (((defs[def] as Map<String, Object?>)['properties'] as Map<String, Object?>)[prop]
                  as Map<String, Object?>)['maxLength']
              as int?;

      expect(maxOf('UiDocument', 'documentId'), 64);
      expect(maxOf('UiDocument', 'initialScreenId'), 64);
      expect(maxOf('ScreenEntry', 'screenId'), 64);
      for (final def in defs.keys.where((k) => k.endsWith('Node'))) {
        final props = (defs[def] as Map<String, Object?>)['properties'] as Map<String, Object?>?;
        if (props == null || !props.containsKey('id')) continue;
        expect(maxOf(def, 'id'), 64, reason: '$def.id lost its bound');
      }

      // The option name, image address, translation key, action type and the `visibleIf`
      // operand are also not human text. The option name is named TWICE, at both ends of
      // the reference, and the bound must be the same: in a row it is a literal
      // (`ListTileTrailing.optionValue`), and in a group it is a bindable value
      // (`ChoiceGroup.value` -> `BindableString64`). Were the numbers to diverge, the
      // row would become unreachable for its own group.
      expect(
        (((defs['ListTileTrailing'] as Map<String, Object?>)['oneOf'] as List<Object?>)
                    .cast<Map<String, Object?>>()
                    .firstWhere(
                      (b) => (b['properties'] as Map<String, Object?>).containsKey('optionValue'),
                    )['properties']
                as Map<String, Object?>)['optionValue'],
        containsPair('maxLength', 64),
      );
      expect(
        ((defs['ChoiceGroupProps'] as Map<String, Object?>)['properties']
            as Map<String, Object?>)['value'],
        {r'$ref': r'#/$defs/BindableString64'},
      );
      expect(maxOf('ButtonAction', 'type'), 64);
      expect((defs['LocalizationKey'] as Map<String, Object?>)['maxLength'], 194);
      expect(
        (((defs['ImageSource'] as Map<String, Object?>)['oneOf'] as List<Object?>)
                    .cast<Map<String, Object?>>()
                    .firstWhere((b) => (b['properties'] as Map<String, Object?>).containsKey('url'))[
                'properties'] as Map<String, Object?>)['url'],
        containsPair('maxLength', 2048),
      );
      expect(
        (((defs['EqualityVisibilityCondition'] as Map<String, Object?>)['properties']
                    as Map<String, Object?>)['value']
                as Map<String, Object?>)['anyOf'],
        contains(containsPair('maxLength', 128)),
      );
    });

    test('document weight: the only bound is x-budget, and it is on the builder side', () {
      // Field bounds were a side-effect size safeguard. They were removed - one
      // explicit budget remained, and the PRODUCER enforces it. The renderer holds no number
      // of its own, deliberately: two independent limits would diverge, and the app would
      // start silently rejecting documents the builder considers legal.
      final budget = schema['x-budget'] as Map<String, Object?>;
      expect(budget['maxDocumentBytes'], 1048576);
      expect(budget['enforcedBy'], 'producer');
      expect(budget['measure'], 'utf8-bytes-of-serialized-json');
    });
  });

  group('x-compatibility mirror on the Dart side', () {
    test('the artifact degradation policy is the one the renderer implements', () {
      expect(policy['majorMustMatch'], isTrue);
      expect(policy['minorAdditionsAreOptional'], isTrue);
      expect(policy['unknownWidget'], 'render-children');
      // 7.1.0 refined the row: not "the default" but the default of THIS VERY FIELD. Before
      // that the policy said only "fallback-to-default", and which default was meant -
      // of the token type or of the field - was decided by the reader.
      expect(policy['unknownToken'], 'fallback-to-field-default');
      expect(policy['tokenWithoutFieldDefault'], 'omit-field');
      expect(policy['unknownAction'], 'pass-to-host');
      // The most important row: an unknown condition does NOT hide content.
      expect(policy['unknownVisibilityOp'], 'visible');
      // 7.2.0. No translation - the node literal, NOT the next language in the list.
      expect(policy['missingTranslation'], 'fall-back-to-default-locale');
      // 8.0.0. Overflow is a DISPLAY question, not a validity one: the reader does not cut
      // at its own number and does not add an ellipsis of its own. What to do with the
      // excess is said by the document itself (`Text.maxLines` / `Text.overflow`).
      expect(policy['overlongText'], 'render-as-is');
      /*
       * 8.10.0. An entry name lives LONGER than a document: it has already gone into a push
       * and will come back in a week, when the document is already updated. The start screen
       * is better than an empty window - the user is not at fault that the name is stale.
       */
      expect(policy['unknownEntryPoint'], 'use-initial');
      /*
       * 8.20.0. Both binding-format rows say the same: the value on screen stays. ISO is
       * ugly but truthful, while an empty place would hide what is in the data. The
       * behaviour is held by `binding_format_test.dart`.
       */
      expect(policy['unknownBindingFormat'], 'render-as-is');
      expect(policy['unparsableBoundValue'], 'render-as-is');
      /*
       * 9.0.0. Three rows about node style; the behaviour behind each is held by
       * `node_style_test.dart` (unknown field), `style_refs_test.dart`
       * (gradient) and `style_box_test.dart` (sizes).
       */
      expect(policy['unknownStyleField'], 'ignore-field');
      expect(policy['unorderedGradient'], 'do-not-draw');
      expect(policy['gradientStopOrder'], 'non-descending');
      expect(policy['invertedSizeRange'], 'min-wins');
      /*
       * Contract 9, five new rows. The behaviour behind each is held by
       * `policy_38_test.dart`.
       */
      expect(policy['sizeOutsideRange'], 'clamp-to-range');
      expect(policy['malformedSideValue'], 'side-is-zero');
      expect(policy['initialTabOutOfRange'], 'first-visible');
      expect(policy['nonNumericLiteral'], 'lower-bound');
      expect(policy['fillOutsideStack'], 'ignore');
      /*
       * Seven rows that each reader used to guess. The behaviour is held by:
       * `style_refs_test.dart` (a side with an unknown token, the diagonal),
       * `style_inheritance_test.dart` (an unknown inherited token),
       * `style_box_test.dart` (a size from data, an unknown widget),
       * `background_test.dart` (an unknown kind), `tabs_test.dart` (a hidden
       * initial tab).
       */
      expect(policy['unknownSideToken'], 'side-is-zero');
      expect(policy['unknownInheritedToken'], 'keep-parent');
      expect(policy['boundSizeOutOfRange'], 'use-fallback');
      expect(policy['unknownBackgroundKind'], 'omit-field');
      expect(policy['unknownWidgetStyle'], 'ignore-style');
      expect(policy['hiddenInitialTab'], 'first-visible');
      expect(policy['diagonalGradientGeometry'], 'css-to-corner');
      /*
       * Further rows. The behaviour is held by: `style_box_test.dart`
       * (clamping, screen size, overflow, width in a scroll, a node in a
       * tight cell), `style_refs_test.dart` (two forms of an unknown token),
       * `stack_test.dart` (a stack with no non-stretched layer).
       */
      expect(policy['literalOutOfRange'], 'clamp');
      expect(policy['unknownBoxToken'], 'omit-field');
      expect(policy['screenBoxFields'], 'ignore');
      expect(policy['scrollPadding'], 'inside-scroll');
      expect(policy['sizedBoxOverflow'], 'clip');
      expect(policy['allLayersFilled'], 'ignore-fill');
      expect(policy['scrollableRowChildWidth'], 'row-viewport');
      expect(policy['sizedChildInTightSlot'], 'start-top');
      /*
       * Contract 9, policy rows readers used to guess - six rows. The behaviour is held by
       * `second_wave_test.dart`, the width of column children by `column_width_test.dart`.
       */
      expect(policy['columnChildWidth'], 'stretch-unless-natural');
      expect(policy['rowInUnboundedWidth'], 'natural-width-ignore-weights');
      expect(policy['nullNumericField'], 'absent');
      expect(policy['invalidWeight'], 'no-weight');
      expect(policy['justifyInNaturalRow'], 'nothing-to-distribute');
      expect(policy['naturalWidthInTightSlot'], 'natural-start-top');
      expect(policy['missingShadowLayerField'], 'zero');
      expect(policy['protoKeyWithoutValidation'], 'drop-entry');
      // Further rows and the unweighted row: the behaviour is held by
      // `third_wave_test.dart` and `row_natural_width_test.dart`.
      expect(policy['unweightedRowChild'], 'natural-shrink-proportionally');
      expect(policy['unweightedStretchInRow'], 'share-of-one');
      // 9.2.0: eight rows about the row record and data layers. Mirror -
      // `kRecordScopePolicy`; the behaviour is held by `record_scope_test.dart`.
      for (final entry in kRecordScopePolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // Guard of the list itself: a policy row this test does not know is a
      // contract decision the renderer may not have implemented.
      // 9.3.0: two rows about an icon the reader cannot draw. Mirror -
      // `kIconPolicy`; the behaviour is held by `icon_library_test.dart`.
      for (final entry in kIconPolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // 9.4.0: thirteen rows about template text, numbers and plurals. Mirror -
      // `kTemplatePolicy`; the behaviour is held by the case table
      // (`template_cases_test.dart`) and `template_text_test.dart`.
      for (final entry in kTemplatePolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      expect(policy.keys.toSet(), {
        ...kRecordScopePolicy.keys,
        ...kIconPolicy.keys,
        ...kTemplatePolicy.keys,
        // 9.5.0: three rows about an icon beside text and the icon button.
        // Mirror - `kIconTextPolicy`; the behaviour is held by `icon_text_test.dart`.
        ...kIconTextPolicy.keys,
        // 9.5.0 clarification: five rows about the date, rounding
        // and the plural of a fraction. Mirror - `kTemplateClarifiedPolicy`.
        ...kTemplateClarifiedPolicy.keys,
        // 9.6.0: seven rows about composed text. Mirror - `kTextSpansPolicy`;
        // the behaviour is held by the `rich-text-cases.json` table.
        ...kTextSpansPolicy.keys,
        // 9.8.0: ten rows about the action catalog, the analytics event and screen display.
        // Mirror - `kActionPolicy`; the behaviour is held by `actions_cases_test.dart`.
        ...kActionPolicy.keys,
        // 9.9.0: thirteen rows about the image, app bar, modal layer and status
        // bar. Mirror - `kMediaChromePolicy`; the behaviour is held by
        // `media_chrome_cases_test.dart`.
        ...kMediaChromePolicy.keys,
        // 9.10.0: ten rows about offset stacking. Mirror - `kOffsetPolicy`;
        // the behaviour is held by `offset_cases_test.dart`.
        ...kOffsetPolicy.keys,
        // 9.11.0: ten rows about the carousel and bar steps. Mirror - `kCarouselPolicy`;
        // the behaviour is held by `carousel_cases_test.dart` and `progress_cases_test.dart`.
        ...kCarouselPolicy.keys,
        // 9.12.0: sixteen rows about the bottom zone, `pin` and `navigate.section`.
        // Mirror - `kBottomZonePolicy`; the behaviour is held by `bottom_zone_cases_test.dart`.
        ...kBottomZonePolicy.keys,
        // 9.13.0: twenty rows about input fields. Mirror - `kInputsPolicy`;
        // the behaviour of each is held by `input_cases_test.dart`.
        ...kInputsPolicy.keys,
        // 9.14.0: fourteen rows about the survey form. Mirror -
        // `kFormPolicy`; the behaviour of each is held by `form_cases_test.dart`.
        ...kFormPolicy.keys,
        'majorMustMatch',
        'minorAdditionsAreOptional',
        'unknownWidget',
        'unknownToken',
        'tokenWithoutFieldDefault',
        'unknownAction',
        'unknownVisibilityOp',
        'missingConditionValue',
        'unknownBindingFormat',
        'unparsableBoundValue',
        'missingTranslation',
        'localeNormalization',
        'localeMatching',
        'localeChildFallback',
        'unmatchedLocale',
        'localeResolution',
        'directionFollows',
        'formattingLocale',
        'overlongText',
        'unknownEntryPoint',
        'unknownStyleField',
        'gradientStopOrder',
        'unorderedGradient',
        'invertedSizeRange',
        'sizeOutsideRange',
        'unknownSideToken',
        'malformedSideValue',
        'unknownInheritedToken',
        'boundSizeOutOfRange',
        'unknownBackgroundKind',
        'unknownWidgetStyle',
        'hiddenInitialTab',
        'initialTabOutOfRange',
        'diagonalGradientGeometry',
        'literalOutOfRange',
        'nonNumericLiteral',
        'unknownBoxToken',
        'screenBoxFields',
        'scrollPadding',
        'sizedBoxOverflow',
        'allLayersFilled',
        'fillOutsideStack',
        'scrollableRowChildWidth',
        'sizedChildInTightSlot',
        'columnChildWidth',
        'rowInUnboundedWidth',
        'nullNumericField',
        'invalidWeight',
        'justifyInNaturalRow',
        'naturalWidthInTightSlot',
        'missingShadowLayerField',
        'protoKeyWithoutValidation',
        'unweightedRowChild',
        'unweightedStretchInRow',
      });
    });

    test('unknownToken: fallback-to-field-default - the field default, not the type default', () {
      // The most valuable test of this group, and its value is not in the policy but in the
      // TABLE: defaults are taken from the artifact, so changing a default in the
      // builder fails the renderer build. That is how the `Divider.color` desync
      // was found.
      //
      // "The field default" is not pedantry. `color` fields have four different defaults
      // (`onSurface` for text, `primary` for the bar, `muted` for the divider), and a
      // reader that understood the policy as "the default of the token TYPE" would draw
      // grey text or a black progress bar - silently and everywhere.
      //
      // Since 9.0.0 "unknown token" means something else: in the six open dictionaries
      // names are declared by the THEME, so an unknown name is a pattern-valid name that
      // the theme being drawn with does not have, and this is found out at draw time. So
      // the table below reads the already RESOLVED value, and there are two broken values:
      // a name the theme does not know, and a string that cannot be a name at all.
      final theme = RenderTheme.fallback();
      for (final entry in _fieldDefaults) {
        final declared =
            ((defs['${entry.def}Props'] as Map<String, Object?>)['properties']
                    as Map<String, Object?>)[entry.prop]
                as Map<String, Object?>;
        expect(
          declared['default'],
          isNotNull,
          reason: '${entry.def}.${entry.prop}: a field without a default in the artifact',
        );

        ChildNode parse(Map<String, Object?> props) => flattenDocument(
          docWith([
            {'id': 'n', 'type': entry.def, 'props': props},
          ]),
        ).whereType<ChildNode>().single;

        // The reference is a node where the artifact default is written EXPLICITLY.
        final expected = entry.read(parse({entry.prop: declared['default']}), theme);

        for (final broken in ['tokenFromTheFuture', 'токен-з-майбутнього']) {
          if ((entry.def == 'IconButton' || entry.def == 'NavItem') && entry.prop == 'icon') {
            // The same exception for the icon button (9.5.0): an unknown name is
            // an empty box, the button stays; the field default (`info`) acts only
            // when there is no field at all.
            expect(entry.read(parse({entry.prop: broken}), theme), IconToken.unknown.wire, reason: 'unknownIcon');
            // Field default: `info` for the icon button, `house` for the panel item (9.12.0).
            expect(expected, entry.def == 'NavItem' ? 'house' : 'info');
            continue;
          }
          if (entry.def == 'Icon' && entry.prop == 'name') {
            // THE ONLY EXCEPTION OF THE TABLE (9.3.0): `unknownIcon` is stronger than
            // `unknownToken`. An unknown icon name does NOT become the field default
            // (`star`) - it is an empty box. Before, the row sat in the general rule,
            // and a star was drawn in place of any icon from a newer minor.
            expect(entry.read(parse({entry.prop: broken}), theme), IconToken.unknown.wire, reason: 'unknownIcon');
            expect(expected, 'star', reason: 'and the field default, when there is no field, stayed');
            continue;
          }
          expect(
            // Exactly one broken token: everything else is absent, so it is visible that
            // exactly this field resolves, not a neighbouring one.
            entry.read(parse({entry.prop: broken}), theme),
            expected,
            reason: '${entry.def}.${entry.prop} = «$broken»: the renderer takes a different default than the artifact',
          );
        }
        // No field at all - the same default.
        expect(entry.read(parse(const {}), theme), expected, reason: '${entry.def}.${entry.prop}');
      }
    });

    test('no field with a default in the artifact is missing from the table', () {
      // A guard of the guard. Without it a new token in the contract would simply not fall
      // under the check above - silently, because the test would stay green.
      final declared = <String>{
        for (final entry in defs.entries)
          if (entry.key.endsWith('Props'))
            if (entry.value case {'properties': final Map<String, Object?> props})
              for (final prop in props.entries)
                if (prop.value case {'default': final String _})
                  '${entry.key.substring(0, entry.key.length - 'Props'.length)}.${prop.key}',
      };

      final covered = {for (final entry in _fieldDefaults) '${entry.def}.${entry.prop}'};

      // `Screen.gap` is the only exception, and not out of laziness: `Screen` is not a
      // [ChildNode], so by type it does not fit the children table. Its default is guarded
      // by the next test.
      expect(declared.difference(covered), {'Screen.gap'});
      expect(covered.difference(declared), isEmpty);
    });

    test('Screen.gap: the field default is the one in the artifact', () {
      // The gap between root children before 9.0.0 was a number in the reader code - exactly
      // the hidden default the contract promised not to have.
      final declared =
          ((defs['ScreenProps'] as Map<String, Object?>)['properties'] as Map<String, Object?>)['gap']
              as Map<String, Object?>;
      final theme = RenderTheme.fallback();
      ScreenNode screen(Map<String, Object?> props) =>
          UiNode.parse({'id': 'root', 'type': 'Screen', 'props': props}) as ScreenNode;

      final expected = theme.fieldSpacing(screen({'gap': declared['default']}).gap);
      expect(theme.fieldSpacing(screen(const {}).gap), expected);
      expect(theme.fieldSpacing(screen(const {'gap': 'tokenFromTheFuture'}).gap), expected);
      expect(theme.fieldSpacing(screen(const {'gap': 20}).gap), 20);
    });

    test('tokenWithoutFieldDefault: omit-field - `style` has no defaults by construction', () {
      // The second half of the same row, and without it the first is incomplete. Before 9.0.0
      // there was one such field (`AppBar.background`); now it is EVERY style field:
      // none of them has a `default` in the artifact, so there is nothing to invent.
      final styleFields =
          (defs['NodeStyle'] as Map<String, Object?>)['properties'] as Map<String, Object?>;
      for (final field in styleFields.entries) {
        expect(
          (field.value as Map<String, Object?>).containsKey('default'),
          isFalse,
          reason: 'style.${field.key} got a default - the hidden look is back',
        );
      }

      // The token is not in the theme -> the property is not applied: the resolver yields
      // `null`, not a "similar" token. Rendering behind this is held by `style_box_test.dart`.
      final theme = RenderTheme.fallback();
      expect(theme.resolveColor(const ColorRef.token('colorFromTheFuture')), isNull);
      expect(theme.resolveGradient(const TokenGradientRef('gradientFromTheFuture')), isNull);
      expect(theme.resolveSpacing(const ScaleRef.token('spaceFromTheFuture')), isNull);
      expect(theme.resolveRadius(const ScaleRef.token('radiusFromTheFuture')), isNull);
      expect(theme.resolveTypography(const TypographyRef('fontFromTheFuture')), isNull);
      expect(theme.resolveShadow(const TokenShadowRef('shadowFromTheFuture')), isNull);
    });

    test('the divider colour default in the schema is the one the model takes as default', () {
      // The same guard that already stands on the background, but for 7.3.0: the `border`
      // token appeared exactly for dividers, and if the builder ever makes
      // it a field default too, the renderer must learn about it through the build.
      final declared =
          ((defs['DividerProps'] as Map<String, Object?>)['properties']
              as Map<String, Object?>)['color'] as Map<String, Object?>;
      final divider = flattenDocument(
        docWith([
          {
            'id': 'd',
            'type': 'Divider',
            'props': const <String, Object?>{},
          },
        ]),
      ).whereType<DividerNode>().single;

      expect(divider.color.fieldDefault.wire, declared['default']);
      expect(divider.color.ref, ColorRef.token(declared['default']! as String));
    });

    test('the renderer feature catalog matches the artifact', () {
      // A sister of the widget catalog, appeared in 7.2.0. Needed because
      // localization is not a widget: without it "the app did not translate" and
      // "the app does not know the word localization" look the same.
      expect(kFeatureCatalog, features);
      expect(supportsFeature('localization'), isTrue);
      // A feature missing from the catalog is not "supported" on faith.
      expect(supportsFeature('темна-тема-з-майбутнього'), isFalse);
      // ...and the same feature as seen by older code - not yet capable.
      expect(supportsFeature('localization', readerVersion: '7.1.0'), isFalse);
      // 8.0.0. `unboundedText` is exactly the case the map exists for:
      // the feature is visible neither in the widget set nor in the field shapes.
      expect(supportsFeature('unboundedText'), isTrue);
      expect(supportsFeature('unboundedText', readerVersion: '7.3.0'), isFalse);
    });

    test('the renderer widget catalog matches the artifact one to one', () {
      expect(kWidgetCatalog, widgets);
    });

    test('every type the renderer draws is in x-compatibility.widgets', () {
      // Otherwise a renderer-own widget would look to itself like "outside the
      // contract" - the 5.0.0 mechanism would lie in the simplest case.
      final rendered = flattenDocument(loadFixture('full-catalog-screen'))
          .map(contractType)
          .toSet();

      expect(rendered, hasLength(22));
      for (final type in rendered) {
        expect(widgets.containsKey(type), isTrue, reason: '$type is missing from the version catalog');
        expect(widgetOriginOf(type), WidgetOrigin.contractual, reason: type);
      }
    });

    test('all versions in the catalog are valid semver and not from the future', () {
      final reader = SchemaVersion.tryParse(UiDocument.supportedSchemaVersion)!;
      for (final entry in widgets.entries) {
        final since = SchemaVersion.tryParse(entry.value);
        expect(since, isNotNull, reason: entry.key);
        expect(
          since!.compareTo(reader),
          lessThanOrEqualTo(0),
          reason: '${entry.key} appeared in a version newer than the renderer version',
        );
      }
    });
  });
}

/// One field with a default: where it is declared in the artifact and what value
/// comes out of it. For closed enums this is the word (`center`, `cover`), for
/// theme references - the already resolved value (pixels, colour).
typedef _FieldDefault = ({String def, String prop, Object Function(ChildNode, RenderTheme) read});

/// ALL contract fields in which the artifact declares a string `default`.
///
/// The table is written by hand, deliberately: automatically deriving "which model field
/// corresponds to the prop `gap`" is impossible, and if it ever becomes possible the point of
/// the test disappears. The cost of the manual work is one and small: a new field has to be
/// added here, otherwise the guard does not guard it. The neighbouring test catches this -
/// "no field with a default in the artifact is missing from the table".
///
/// Since 9.0.0 the table is shorter by fifteen rows: look fields
/// (`padding`, `radius`, `elevation`, `color` and the text `typography`) moved from
/// `props` into `style`, where there are no defaults.
final List<_FieldDefault> _fieldDefaults = [
  (def: 'Badge', prop: 'tone', read: (n, _) => (n as BadgeNode).tone.wire),
  (def: 'Button', prop: 'variant', read: (n, _) => (n as ButtonNode).variant.wire),
  (def: 'ChoiceGroup', prop: 'gap', read: (n, t) => t.fieldSpacing((n as ChoiceGroupNode).gap)),
  (def: 'CircularProgress', prop: 'color', read: (n, t) => t.fieldColor((n as CircularProgressNode).color)),
  (def: 'CircularProgress', prop: 'size', read: (n, _) => (n as CircularProgressNode).size.wire),
  (def: 'CircularProgress', prop: 'labelFormat', read: (n, _) => (n as CircularProgressNode).labelFormat.wire),
  (def: 'Column', prop: 'gap', read: (n, t) => t.fieldSpacing((n as ColumnNode).gap)),
  (def: 'Column', prop: 'align', read: (n, _) => (n as ColumnNode).align.wire),
  (def: 'Container', prop: 'direction', read: (n, _) => (n as ContainerNode).direction.wire),
  (def: 'Container', prop: 'gap', read: (n, t) => t.fieldSpacing((n as ContainerNode).gap)),
  (def: 'Divider', prop: 'color', read: (n, t) => t.fieldColor((n as DividerNode).color)),
  (def: 'Divider', prop: 'spacing', read: (n, t) => t.fieldSpacing((n as DividerNode).spacing)),
  (def: 'Divider', prop: 'orientation', read: (n, _) => (n as DividerNode).orientation.wire),
  (def: 'Grid', prop: 'gap', read: (n, t) => t.fieldSpacing((n as GridNode).gap)),
  (def: 'Image', prop: 'fit', read: (n, _) => (n as ImageNode).fit.wire),
  (def: 'Icon', prop: 'name', read: (n, _) => (n as IconNode).name.wire),
  // 9.5.0. `Button.size` and `iconPosition` do NOT go here: in the schema they have no
  // `default`, deliberately - their default is in `x-style.layout` (`icon_text_test.dart`).
  (def: 'IconButton', prop: 'icon', read: (n, _) => (n as IconButtonNode).icon.wire),
  // 9.12.0. A navigation panel item: the same `info` default and the same empty
  // box for an unknown name as the icon button.
  (def: 'NavItem', prop: 'icon', read: (n, _) => (n as NavItemNode).icon.wire),
  (def: 'IconButton', prop: 'variant', read: (n, _) => (n as IconButtonNode).variant.wire),
  (def: 'IconButton', prop: 'size', read: (n, _) => (n as IconButtonNode).size.name),
  (def: 'Icon', prop: 'size', read: (n, _) => (n as IconNode).size.wire),
  (def: 'Image', prop: 'aspectRatio', read: (n, _) => (n as ImageNode).aspectRatio.wire),
  (def: 'ProgressBar', prop: 'color', read: (n, t) => t.fieldColor((n as ProgressBarNode).color)),
  (def: 'ProgressBar', prop: 'labelFormat', read: (n, _) => (n as ProgressBarNode).labelFormat.wire),
  (def: 'Repeater', prop: 'direction', read: (n, _) => (n as RepeaterNode).direction.wire),
  (def: 'Repeater', prop: 'gap', read: (n, t) => t.fieldSpacing((n as RepeaterNode).gap)),
  (def: 'Row', prop: 'gap', read: (n, t) => t.fieldSpacing((n as RowNode).gap)),
  (def: 'Row', prop: 'align', read: (n, _) => (n as RowNode).align.wire),
  (def: 'Row', prop: 'justify', read: (n, _) => (n as RowNode).justify.wire),
  (def: 'Spacer', prop: 'size', read: (n, t) => t.fieldSpacing((n as SpacerNode).size)),
  (def: 'Spacer', prop: 'orientation', read: (n, _) => (n as SpacerNode).orientation.wire),
  (def: 'Stack', prop: 'alignHorizontal', read: (n, _) => (n as StackNode).alignHorizontal.wire),
  (def: 'Stack', prop: 'alignVertical', read: (n, _) => (n as StackNode).alignVertical.wire),
  (def: 'Text', prop: 'align', read: (n, _) => (n as TextNode).align.wire),
  (def: 'Text', prop: 'overflow', read: (n, _) => (n as TextNode).overflow.wire),
];
