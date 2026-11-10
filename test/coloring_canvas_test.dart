import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tule/coloring_page.dart';

Future<PageArtwork> loadArtwork(WidgetTester tester) async {
  late PageArtwork artwork;
  await tester.runAsync(() async {
    final assets = await PageAssets.load(kPageSpecs[0]);
    artwork = await PageArtwork.create(assets);
  });
  return artwork;
}

Future<Rect> pumpCanvas(
  WidgetTester tester,
  PageArtwork artwork,
  ValueChanged<Offset> onFill, {
  PaintMode mode = PaintMode.fill,
  Color color = Colors.red,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 300),
            child: ColoringCanvas(
              artwork: artwork,
              mode: mode,
              color: color,
              onFillRequested: onFill,
              onArtworkChanged: () {},
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getRect(find.byType(ColoringCanvas));
}

void main() {
  testWidgets('canvas hands normalized coordinates to onFillRequested', (
    tester,
  ) async {
    final taps = <Offset>[];
    final rect = await pumpCanvas(tester, await loadArtwork(tester), taps.add);
    expect(rect.width, moreOrLessEquals(400));
    expect(rect.height, moreOrLessEquals(300));

    await tester.tapAt(rect.center);
    await tester.tapAt(
      rect.topLeft + Offset(rect.width * 0.25, rect.height * 0.75),
    );

    expect(taps, hasLength(2));
    expect(taps[0].dx, moreOrLessEquals(0.5));
    expect(taps[0].dy, moreOrLessEquals(0.5));
    expect(taps[1].dx, moreOrLessEquals(0.25));
    expect(taps[1].dy, moreOrLessEquals(0.75));
  });

  testWidgets('taps outside the canvas are ignored', (tester) async {
    final taps = <Offset>[];
    final rect = await pumpCanvas(tester, await loadArtwork(tester), taps.add);

    await tester.tapAt(Offset(rect.left - 20, rect.top + 20));
    await tester.tapAt(Offset(rect.right + 20, rect.bottom - 20));

    expect(taps, isEmpty);
  });

  testWidgets('a second pointer is ignored while the first is down', (
    tester,
  ) async {
    final taps = <Offset>[];
    final rect = await pumpCanvas(tester, await loadArtwork(tester), taps.add);

    final first = await tester.startGesture(rect.center);
    final second = await tester.startGesture(
      rect.center + const Offset(10, 10),
    );
    await first.up();
    await second.up();

    expect(taps, hasLength(1));
    expect(taps.single, const Offset(0.5, 0.5));

    // 抬手后新的按下重新生效。
    await tester.tapAt(rect.center);
    expect(taps, hasLength(2));
  });

  testWidgets('doodle tracks only the first pointer as one stroke', (
    tester,
  ) async {
    final artwork = await loadArtwork(tester);
    final rect = await pumpCanvas(
      tester,
      artwork,
      (_) {},
      mode: PaintMode.doodle,
      color: Colors.blue,
    );

    final first = await tester.startGesture(rect.topLeft + const Offset(40, 30));
    final second = await tester.startGesture(
      rect.topLeft + const Offset(100, 100),
    );
    await first.moveBy(const Offset(20, 10));
    await second.moveBy(const Offset(30, 30));
    await first.moveBy(const Offset(20, 10));
    await first.up();
    await second.up();

    expect(artwork.strokes, hasLength(1));
    final stroke = artwork.strokes.single;
    expect(stroke.color, Colors.blue);
    expect(stroke.width, 22);
    expect(stroke.points, hasLength(3));
    expect(stroke.points.first.dx, moreOrLessEquals(40 / 400));
    expect(stroke.points.first.dy, moreOrLessEquals(30 / 300));
    expect(stroke.points.last.dx, moreOrLessEquals(80 / 400));

    // 单点单击也留下一笔（一个圆点），不产生第二笔的只有第二根手指。
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(artwork.strokes, hasLength(2));
    expect(artwork.strokes.last.points, hasLength(1));
  });

  testWidgets('doodle points are clamped to the canvas', (tester) async {
    final artwork = await loadArtwork(tester);
    final rect = await pumpCanvas(
      tester,
      artwork,
      (_) {},
      mode: PaintMode.doodle,
    );

    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(1000, 1000));
    await gesture.up();

    final last = artwork.strokes.single.points.last;
    expect(last.dx, 1);
    expect(last.dy, 1);
  });
}
