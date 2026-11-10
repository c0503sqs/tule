import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tule/coloring_page.dart';
import 'package:tule/page_turner.dart';
import 'package:tule/palette.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('mode toggle reports the tapped mode', (tester) async {
    final modes = <PaintMode>[];
    await tester.pumpWidget(
      _wrap(ModeToggle(mode: PaintMode.fill, onChanged: modes.add)),
    );

    await tester.tap(find.byIcon(Icons.brush));
    await tester.tap(find.byIcon(Icons.format_color_fill));

    expect(modes, [PaintMode.doodle, PaintMode.fill]);
  });

  testWidgets('palette reports the tapped color', (tester) async {
    final picked = <Color>[];
    await tester.pumpWidget(
      _wrap(
        ColorPalette(selected: kPalette.first, onSelected: picked.add),
      ),
    );

    final dots = find.descendant(
      of: find.byType(ColorPalette),
      matching: find.byType(GestureDetector),
    );
    expect(dots, findsNWidgets(kPalette.length));

    await tester.tap(dots.at(1));
    expect(picked, [kPalette[1]]);
  });

  testWidgets('page turner disables arrows at the ends', (tester) async {
    var previous = 0;
    var next = 0;

    await tester.pumpWidget(
      _wrap(
        PageTurner(
          pageCount: 3,
          current: 0,
          onPrevious: () => previous++,
          onNext: () => next++,
        ),
      ),
    );

    IconButton arrow(IconData icon) => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, icon),
    );
    expect(arrow(Icons.chevron_left).onPressed, isNull);
    expect(arrow(Icons.chevron_right).onPressed, isNotNull);
    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(next, 1);
    expect(previous, 0);

    await tester.pumpWidget(
      _wrap(
        PageTurner(
          pageCount: 3,
          current: 2,
          onPrevious: () => previous++,
          onNext: () => next++,
        ),
      ),
    );
    expect(arrow(Icons.chevron_left).onPressed, isNotNull);
    expect(arrow(Icons.chevron_right).onPressed, isNull);
    await tester.tap(find.byIcon(Icons.chevron_left));
    expect(previous, 1);
  });

  testWidgets('reset needs a full long press and shows progress', (
    tester,
  ) async {
    var resets = 0;
    await tester.pumpWidget(_wrap(ResetButton(onReset: () => resets++)));

    // 短按无效。
    await tester.tap(find.byType(ResetButton));
    await tester.pump(const Duration(seconds: 2));
    expect(resets, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ResetButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    // 动画首帧只建立 ticker 起点，再泵一帧才有进度值。
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(resets, 0);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(resets, 1);

    // 继续按住不会重复触发；第二根手指也不响应。
    final second = await tester.startGesture(
      tester.getCenter(find.byType(ResetButton)),
      pointer: 2,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(resets, 1);
    await second.up();

    await gesture.up();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('pointer cancel stops the reset timer', (tester) async {
    var resets = 0;
    await tester.pumpWidget(_wrap(ResetButton(onReset: () => resets++)));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ResetButton)),
    );
    // 超过旧的长按识别时间，确认 cancel 仍然生效。
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.cancel();
    await tester.pump(const Duration(seconds: 2));

    expect(resets, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('early release cancels the reset', (tester) async {
    var resets = 0;
    await tester.pumpWidget(_wrap(ResetButton(onReset: () => resets++)));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ResetButton)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    expect(resets, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
