import 'dart:typed_data';

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/widgets/outside_shadow.dart';

/// A shadow is painted only outside the box, as CSS `box-shadow` is: under a translucent background the
/// shadow must not show through.
void main() {
  const shadow = [
    BoxShadow(color: Color(0xFFFF0000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  final key = GlobalKey();

  Future<ByteData> paint(WidgetTester tester, Widget box) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: Padding(padding: const EdgeInsets.all(40), child: box),
            ),
          ),
        ),
      ),
    );
    late ByteData bytes;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      bytes = (await image.toByteData())!;
    });
    return bytes;
  }

  int redAt(ByteData data, int width, int x, int y) =>
      data.getUint8((y * width + x) * 4);

  testWidgets(
    'a translucent box shows no shadow inside, and the shadow outside',
    (tester) async {
      const size = Size(100, 60);
      final data = await paint(
        tester,
        OutsideShadow(
          shadow: shadow,
          radius: BorderRadius.circular(12),
          child: SizedBox.fromSize(
            size: size,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
      );
      const width = 180;
      // Centre of the box: transparent background over black, no red from the shadow.
      expect(redAt(data, width, 90, 70), 0);
      // Just below the bottom edge (the shadow is offset down): red is there.
      expect(redAt(data, width, 90, 40 + 60 + 3), greaterThan(40));
    },
  );

  testWidgets(
    'the plain decoration shadow does show inside a transparent box (what the widget fixes)',
    (tester) async {
      final data = await paint(
        tester,
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: shadow,
          ),
          child: const SizedBox(width: 100, height: 60),
        ),
      );
      expect(redAt(data, 180, 90, 70), greaterThan(40));
    },
  );

  test(
    'only a background that lets light through needs the outside shadow',
    () {
      expect(backgroundIsTranslucent(color: const Color(0xFF112233)), isFalse);
      expect(backgroundIsTranslucent(color: const Color(0x80112233)), isTrue);
      expect(backgroundIsTranslucent(), isFalse);
      expect(
        backgroundIsTranslucent(
          gradient: const LinearGradient(
            colors: [Color(0xFF000000), Color(0x00000000)],
          ),
        ),
        isTrue,
      );
      expect(
        backgroundIsTranslucent(
          gradient: const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
          ),
        ),
        isFalse,
      );
    },
  );
}
