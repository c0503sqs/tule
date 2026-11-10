import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tule/coloring_page.dart';
import 'package:tule/main.dart';
import 'package:tule/page_turner.dart';
import 'package:tule/palette.dart';

/// 测试里不落盘、不走 path_provider。
class _NoDiskAudioCache extends AudioCache {
  @override
  Future<Uri> fetchToMemory(String fileName) async =>
      Uri.file('/tmp/$fileName');
}

/// audioplayers 在 widget test 里没有原生实现，用空实现顶掉。
/// 返回播放器通道收到的调用，便于统计播放次数（resume 即开始播放）。
List<MethodCall> mockAudioPlayer() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  MockStreamHandlerEventSink? playerEvents;

  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (call) async {
      calls.add(call);
      if (call.method == 'create') {
        // playerId 是运行时随机值，只能等 create 拿到后再挂事件通道。
        final playerId = (call.arguments as Map)['playerId'];
        messenger.setMockStreamHandler(
          EventChannel('xyz.luan/audioplayers/events/$playerId'),
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              playerEvents = events;
            },
          ),
        );
      } else if (call.method == 'setSourceUrl' && playerEvents != null) {
        // _completePrepared 在等原生 prepared 事件，mock 里立刻补上。
        playerEvents!.success({'event': 'audio.onPrepared', 'value': true});
      }
      return null;
    },
  );
  messenger.setMockStreamHandler(
    const EventChannel('xyz.luan/audioplayers.global/events'),
    MockStreamHandler.inline(onListen: (arguments, events) {}),
  );
  AudioCache.instance = _NoDiskAudioCache();
  return calls;
}

/// 让真正的加载链路（rootBundle + isolate）在 widget test 里跑完。
Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(844, 390); // 横屏 iPhone
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // 首次全局初始化放在真实 zone：audioplayers 把初始化结果存在静态 Future 里，
  // 若落在某个 test 的 fake zone，后续 test 等它会永远等不到。
  await tester.runAsync(() => AudioPlayer.global.ensureInitialized());
  await tester.pumpWidget(const TuleApp());
  for (var i = 0; i < 40 && find.byType(ColoringCanvas).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// 等真实异步（isolate / 音频通道）推进，直到 [done] 成立。
Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(done(), isTrue);
}

/// 让 fire-and-forget 的后续微任务（例如 pop 音）走完。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

bool hasOpaquePixel(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] == 255) return true;
  }
  return false;
}

int playCount(List<MethodCall> calls) =>
    calls.where((call) => call.method == 'resume').length;

/// 播放器的动态事件通道名带 playerId，没法预先 mock；这些 MissingPluginException
/// 与界面无关，取走它们，其他异常（例如布局 overflow）照常抛出。
void drainPluginExceptions(WidgetTester tester) {
  while (true) {
    final error = tester.takeException();
    if (error == null) return;
    if (error is MissingPluginException) continue;
    throw error;
  }
}

void main() {
  testWidgets('landscape iPhone fits, doodle/page/reset all work', (
    tester,
  ) async {
    mockAudioPlayer();
    await pumpApp(tester);
    drainPluginExceptions(tester);
    expect(find.byType(ColoringCanvas), findsOneWidget);
    expect(find.byType(ModeToggle), findsOneWidget);
    expect(find.byType(PageTurner), findsOneWidget);
    expect(find.byType(ResetButton), findsOneWidget);

    PageArtwork artwork() => tester
        .widget<ColoringCanvas>(find.byType(ColoringCanvas))
        .artwork;

    // 选绿色，切涂鸦，画一笔。
    final dots = find.descendant(
      of: find.byType(ColorPalette),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(dots.at(3));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.brush));
    await tester.pump();

    final canvasRect = tester.getRect(find.byType(ColoringCanvas));
    await tester.dragFrom(canvasRect.center, const Offset(60, 20));
    await tester.pump();

    final cat = artwork();
    expect(cat.strokes, hasLength(1));
    expect(cat.strokes.single.color, kPalette[3]);
    expect(cat.strokes.single.width, 22);

    // 翻页后笔迹互不串页，翻回来仍在。
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(artwork().strokes, isEmpty);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(artwork().strokes, hasLength(1));

    // 长按满 1 秒清空当前页。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ResetButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(cat.strokes, isEmpty);
    await gesture.up();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    drainPluginExceptions(tester);
  });

  testWidgets('fill in the frame right after a page turn colors the visible page', (
    tester,
  ) async {
    mockAudioPlayer();
    await pumpApp(tester);
    drainPluginExceptions(tester);

    PageArtwork artwork() => tester
        .widget<ColoringCanvas>(find.byType(ColoringCanvas))
        .artwork;
    final rect = tester.getRect(find.byType(ColoringCanvas));
    final cat = artwork();

    // 点右箭头只 setState 不 pump：画面还停在猫页，手指已落到画布上。
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.tapAt(rect.center);

    await tester.pump(); // 应用翻页那一帧，之后画布就是熊页
    await waitUntil(tester, () => !cat.isFilling);
    final bear = artwork();
    expect(identical(cat, bear), isFalse);
    expect(hasOpaquePixel(cat.colorPixels), isTrue);
    expect(hasOpaquePixel(bear.colorPixels), isFalse);
    drainPluginExceptions(tester);
  });

  testWidgets('tap fills a shape; tapping the background changes nothing', (
    tester,
  ) async {
    final calls = mockAudioPlayer();
    await pumpApp(tester);
    drainPluginExceptions(tester);

    final artwork = tester
        .widget<ColoringCanvas>(find.byType(ColoringCanvas))
        .artwork;
    final rect = tester.getRect(find.byType(ColoringCanvas));
    Offset normalized(double nx, double ny) =>
        Offset(rect.left + rect.width * nx, rect.top + rect.height * ny);

    expect(hasOpaquePixel(artwork.colorPixels), isFalse);

    // 猫页 1024x768 的可填内部点。
    await tester.tapAt(normalized(0.718, 0.52));
    await waitUntil(tester, () => !artwork.isFilling);
    await waitUntil(tester, () => playCount(calls) == 1);
    expect(hasOpaquePixel(artwork.colorPixels), isTrue);

    // 背景点不填、不响。
    final before = Uint8List.fromList(artwork.colorPixels);
    await tester.tapAt(normalized(0.05, 0.05));
    await waitUntil(tester, () => !artwork.isFilling);
    await settle(tester);
    expect(artwork.colorPixels, before);
    expect(playCount(calls), 1);
    drainPluginExceptions(tester);
  });
}
