import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glp_buddy/widgets/pal_art.dart';

/// Renders every pal at every stage to PNG so the art can be reviewed without
/// faking streak data on a device. Set PAL_PREVIEW_DIR to write the sheets.
void main() {
  final outDir = Platform.environment['PAL_PREVIEW_DIR'];

  testWidgets('pal preview sheets', (tester) async {
    const species = ['ocean', 'bird', 'cat', 'dog', 'bear', 'bunny'];
    const cell = 150.0;
    final key = GlobalKey();

    Widget sheet(PalMood mood, double blink, double pop) => RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFFF9A5C),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in species)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var st = 0; st < 5; st++)
                        SizedBox(
                          width: cell,
                          height: cell,
                          child: PalArt(
                            species: s,
                            stage: st,
                            size: cell,
                            phase: 0.2,
                            blink: blink,
                            pop: pop,
                            mood: mood,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );

    Future<void> capture(String name, Widget w) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: w)));
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Real async work: toImage never completes under the fake clock.
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      expect(bytes, isNotNull);
      if (outDir != null) {
        File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      }
    }

    tester.view.physicalSize = const Size(1700, 2000);
    tester.view.devicePixelRatio = 1;
    await capture('pals_normal', sheet(PalMood.normal, 0, 0));
    await capture('pals_happy', sheet(PalMood.happy, 0, 0.5));
    await capture('pals_sleepy', sheet(PalMood.sleepy, 0, 0));
  });
}
