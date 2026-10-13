import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// Both edges of a row are a union (since 6.0.0) instead of a set of
/// independent props.
///
/// What this fixes: before 6.0.0 `trailing: BindableString?` and
/// `showChevron: bool` could both be on, and "a row without an icon" was
/// expressed by an icon one hoped nobody would notice. Both cases are now
/// unrepresentable.
ListTileNode tileOf(Map<String, Object?> raw) =>
    flattenDocument(docWith([raw])).whereType<ListTileNode>().single;

void main() {
  group('ListTile.leading', () {
    test('three union branches parse into their own types', () {
      expect(tileOf(listTileNode('Без нічого')).leading, isA<LeadingNone>());

      final icon = tileOf(
        listTileNode('З іконкою', leading: {'kind': 'icon', 'icon': 'gift'}),
      ).leading;
      expect(icon, isA<LeadingIcon>());
      expect((icon as LeadingIcon).icon, IconToken.gift);

      final asset = tileOf(
        listTileNode(
          'З ассетом',
          leading: {
            'kind': 'image',
            'source': {'kind': 'asset', 'asset': 'banner'},
          },
        ),
      ).leading;
      expect(asset, isA<LeadingImage>());
      expect((asset as LeadingImage).source, isA<AssetImageSource>());

      final url = tileOf(
        listTileNode(
          'З фото',
          leading: {
            'kind': 'image',
            'source': {'kind': 'url', 'url': 'https://cdn.example.com/p.png'},
          },
        ),
      ).leading;
      expect(((url as LeadingImage).source as UrlImageSource).url, 'https://cdn.example.com/p.png');
    });

    testWidgets('image reuses the same source as Image, network included', (tester) async {
      // The key point: a storage photo works in a row not because the row
      // learned networking, but because the contract has a single source.
      await pumpDocument(
        tester,
        docWith([
          listTileNode(
            'Смартфон',
            leading: {
              'kind': 'image',
              'source': {'kind': 'url', 'url': 'https://cdn.example.com/iphone.png'},
            },
          ),
        ]),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('none leaves behind neither an icon nor a gap', (tester) async {
      await pumpDocument(tester, docWith([listTileNode('Голий рядок')]));

      // No icon in the row: neither decoration nor chevron.
      expect(find.byType(IconGlyph), findsNothing);
    });

    test('a broken or unknown form degrades to none instead of failing the node', () {
      expect(tileOf(listTileNode('Битий', leading: const {'kind': 'sticker'})).leading, isA<LeadingNone>());
      final missing = flattenDocument(
        docWith([
          {
            'id': 'tile',
            'type': 'ListTile',
            'props': {
              'title': {'kind': 'literal', 'value': 'Без слотів'},
            },
          },
        ]),
      ).whereType<ListTileNode>().single;
      expect(missing.leading, isA<LeadingNone>());
      expect(missing.trailing, isA<TrailingNone>());
    });
  });

  group('ListTile.trailing', () {
    test('four union branches parse into their own types', () {
      expect(tileOf(listTileNode('Порожньо')).trailing, isA<TrailingNone>());
      expect(
        tileOf(listTileNode('Шеврон', trailing: const {'kind': 'chevron'})).trailing,
        isA<TrailingChevron>(),
      );
      expect(
        tileOf(
          listTileNode(
            'Текст',
            trailing: const {
              'kind': 'text',
              'text': {'kind': 'literal', 'value': '1250'},
            },
          ),
        ).trailing,
        isA<TrailingText>(),
      );
      final radio = tileOf(optionNode('Опція', optionValue: 'iphone')).trailing;
      expect(radio, isA<TrailingRadio>());
      expect((radio as TrailingRadio).optionValue, 'iphone');
    });

    testWidgets('text is a binding: the value comes from data', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          listTileNode(
            'Бали',
            trailing: const {
              'kind': 'text',
              'text': {'kind': 'binding', 'path': 'user.points', 'fallback': '0'},
            },
          ),
        ]),
        data: const {'user.points': 1250},
      );

      expect(find.text('1250'), findsOneWidget);
    });

    testWidgets('chevron and text can no longer both be on', (tester) async {
      // Not because the renderer picks one of the two, but because a document
      // with both edges cannot exist: in the schema it is a single slot.
      await pumpDocument(
        tester,
        docWith([
          listTileNode(
            'Тільки текст',
            trailing: const {
              'kind': 'text',
              'text': {'kind': 'literal', 'value': '42'},
            },
          ),
        ]),
      );

      expect(find.text('42'), findsOneWidget);
      expect(findIcon(IconToken.chevron), findsNothing);
    });

    test('radio without optionValue is not an option: it cannot be chosen even in theory', () {
      expect(
        tileOf(listTileNode('Безіменна', trailing: const {'kind': 'radio'})).trailing,
        isA<TrailingNone>(),
      );
      expect(
        tileOf(listTileNode('Порожня', trailing: const {'kind': 'radio', 'optionValue': ''})).trailing,
        isA<TrailingNone>(),
      );
    });

    testWidgets('the selection mark is drawn by ChoiceOptionMark, not a raw Icon', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          choiceGroupNode(
            [optionNode('Нагорода', optionValue: 'reward')],
            value: const {'kind': 'literal', 'value': 'reward'},
          ),
        ]),
      );

      final mark = tester.widget<ChoiceOptionMark>(find.byType(ChoiceOptionMark));
      expect(mark.optionValue, 'reward');
      expect(mark.selected, isTrue);
      expect(mark.enabled, isTrue);
    });
  });

  group('ListTile.action (6.1.0)', () {
    test('the field is optional, and its absence is not `none` but "no action"', () {
      expect(tileOf(listTileNode('Німий рядок')).action, isNull);
      expect(
        tileOf(listTileNode('Рядок із дією', action: const {'type': 'submit'})).action?.type,
        'submit',
      );
    });

    testWidgets('tapping a row hands the action to the host, through the same machinery as a button', (tester) async {
      final fired = <String>[];
      await pumpDocument(
        tester,
        docWith([
          listTileNode(
            'Обраний шанс на виграш',
            id: 'chance',
            trailing: const {'kind': 'chevron'},
            action: const {
              'type': 'openRewards',
              'params': {'source': 'tile'},
            },
          ),
        ]),
        onAction: (action, nodeId) => fired.add('${action.type}:${action.params}@$nodeId'),
      );

      await tester.tap(find.text('Обраний шанс на виграш'));
      await tester.pump();

      expect(fired, ['openRewards:{source: tile}@chance']);
    });

    testWidgets('the row runs `navigate` itself, like a button', (tester) async {
      // The point of this test: the row got no machinery of its own; the same
      // action is intercepted by the same `ScreenFlow`.
      await pumpDocument(
        tester,
        docWithScreens([
          screenEntry('task', [
            listTileNode(
              'Обраний шанс на виграш',
              trailing: const {'kind': 'chevron'},
              action: const {
                'type': 'navigate',
                'params': {'screenId': 'items'},
              },
            ),
          ]),
          screenEntry('items', [textNode('Оберіть нагороду')]),
        ], initialScreenId: 'task'),
      );

      await tester.tap(find.text('Обраний шанс на виграш'));
      await tester.pumpAndSettle();

      expect(find.text('Оберіть нагороду'), findsOneWidget);
    });

    testWidgets('a row without an action is not a tap target', (tester) async {
      final fired = <String>[];
      await pumpDocument(
        tester,
        docWith([listTileNode('Просто рядок', trailing: const {'kind': 'chevron'})]),
        onAction: (action, nodeId) => fired.add(action.type),
      );

      await tester.tap(find.text('Просто рядок'));
      await tester.pump();

      expect(fired, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chevron no longer lies: it can now lead somewhere', (tester) async {
      // Before 6.1.0 the chevron promised a navigation the row could not do.
      // The test guards the link itself: appearance and ability together.
      final fired = <String>[];
      await pumpDocument(
        tester,
        docWith([
          listTileNode(
            'Категорія',
            trailing: const {'kind': 'chevron'},
            action: const {'type': 'open'},
          ),
        ]),
        onAction: (action, _) => fired.add(action.type),
      );

      expect(findIcon(IconToken.chevron), findsOneWidget);
      await tester.tap(findIcon(IconToken.chevron));
      await tester.pump();

      expect(fired, ['open']);
    });
  });

  group('catalog fixture', () {
    testWidgets('all four row decoration kinds render without exceptions', (tester) async {
      await pumpDocument(tester, loadFixture('full-catalog-screen'));

      expect(find.text('Рядок без оздоблення'), findsOneWidget);
      expect(find.text('Банер кампанії'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
