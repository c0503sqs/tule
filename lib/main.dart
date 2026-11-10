import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'coloring_page.dart';
import 'flood_fill.dart';
import 'page_turner.dart';
import 'palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const TuleApp());
}

class TuleApp extends StatelessWidget {
  const TuleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: '涂了',
      debugShowCheckedModeBanner: false,
      home: ColoringBookScreen(),
    );
  }
}

class ColoringBookScreen extends StatefulWidget {
  const ColoringBookScreen({super.key});

  @override
  State<ColoringBookScreen> createState() => _ColoringBookScreenState();
}

class _ColoringBookScreenState extends State<ColoringBookScreen> {
  static final _popSound = AssetSource('sfx/pop.wav');

  final AudioPlayer _player = AudioPlayer();
  final GlobalKey<ColoringCanvasState> _canvasKey = GlobalKey();
  List<PageArtwork>? _artworks;
  int _currentPage = 0;
  PaintMode _mode = PaintMode.fill;
  Color _selectedColor = kPalette.first;

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.stop);
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final assets = await Future.wait(kPageSpecs.map(PageAssets.load));
    final artworks = await Future.wait(assets.map(PageArtwork.create));
    if (!mounted) return;
    setState(() => _artworks = artworks);
  }

  Future<void> _handleFill(PageArtwork artwork, Offset point) async {
    if (artwork.isFilling) return;
    final color = _selectedColor;
    final assets = artwork.assets;
    final width = assets.fillWidth;
    final height = assets.fillHeight;
    final (x, y) = normalizedToPixel(point.dx, point.dy, width, height);
    // 只捕获可发送的局部变量，绝不把 artwork（含 ui.Image）送进 isolate。
    final lineRgba = assets.lineRgba;
    final backgroundMask = assets.backgroundMask;
    artwork.isFilling = true;
    try {
      final region = await Isolate.run(
        () => computeFillRegion(
          rgba: lineRgba,
          width: width,
          height: height,
          startX: x,
          startY: y,
          backgroundMask: backgroundMask,
        ),
      );
      if (!region.foundStart || region.touchesBorder) return;
      applyRegionColor(artwork.colorPixels, region.mask, color.toARGB32());
      await artwork.refreshColorImage();
      if (!mounted) return;
      setState(() {});
      // 翻页后脉冲不能闪到别的页上。
      if (identical(_artworks?[_currentPage], artwork)) {
        _canvasKey.currentState?.flashPulse(point);
      }
      HapticFeedback.lightImpact();
      _player.play(_popSound);
    } finally {
      artwork.isFilling = false;
    }
  }

  Future<void> _resetCurrentPage() async {
    final artwork = _artworks?[_currentPage];
    if (artwork == null) return;
    // 填充未结束时清空会被随后写回，先不响应。
    if (artwork.isFilling) return;
    artwork.strokes.clear();
    artwork.colorPixels.fillRange(0, artwork.colorPixels.length, 0);
    await artwork.refreshColorImage();
    if (!mounted) return;
    setState(() {});
  }

  void _turnPage(int delta) {
    final page = _currentPage + delta;
    if (page < 0 || page >= (_artworks?.length ?? 0)) return;
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) {
    final artworks = _artworks;
    // 显示和填充回调必须锁同一个对象：翻页 setState 后下一帧才重建，
    // 这一帧里手指仍可能点在旧画布上。
    final currentArtwork = artworks?[_currentPage];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F0E4),
      body: SafeArea(
        child: artworks == null || currentArtwork == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ModeToggle(
                          mode: _mode,
                          onChanged: (mode) => setState(() => _mode = mode),
                        ),
                        ResetButton(onReset: _resetCurrentPage),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(88, 8, 88, 36),
                          child: Center(
                            child: ColoringCanvas(
                              key: _canvasKey,
                              artwork: currentArtwork,
                              mode: _mode,
                              color: _selectedColor,
                              onFillRequested: (point) =>
                                  _handleFill(currentArtwork, point),
                              onArtworkChanged: () => setState(() {}),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: PageTurner(
                            pageCount: artworks.length,
                            current: _currentPage,
                            onPrevious: () => _turnPage(-1),
                            onNext: () => _turnPage(1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ColorPalette(
                    selected: _selectedColor,
                    onSelected: (color) =>
                        setState(() => _selectedColor = color),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
      ),
    );
  }
}
