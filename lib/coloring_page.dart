import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flood_fill.dart';

enum PaintMode { fill, doodle }

class PageSpec {
  final String name;
  final String lineAsset;
  final String paperAsset;

  const PageSpec(this.name)
    : lineAsset = 'assets/pages/${name}_line.png',
      paperAsset = 'assets/pages/${name}_paper.png';
}

const List<PageSpec> kPageSpecs = [
  PageSpec('cat'),
  PageSpec('bear'),
  PageSpec('bunny'),
];

class PageAssets {
  final ui.Image lineArt;
  final ui.Image paper;
  final int fillWidth, fillHeight;
  final Uint8List lineRgba;
  final Uint8List backgroundMask;

  const PageAssets._(
    this.lineArt,
    this.paper,
    this.fillWidth,
    this.fillHeight,
    this.lineRgba,
    this.backgroundMask,
  );

  static Future<PageAssets> load(PageSpec spec) async {
    final lineData = await rootBundle.load(spec.lineAsset);
    final paperData = await rootBundle.load(spec.paperAsset);
    final lineBytes = lineData.buffer.asUint8List(
      lineData.offsetInBytes,
      lineData.lengthInBytes,
    );
    final paperBytes = paperData.buffer.asUint8List(
      paperData.offsetInBytes,
      paperData.lengthInBytes,
    );

    final lineArt = await _decode(lineBytes);
    final paper = await _decode(paperBytes);

    final scale = 1024 / math.max(lineArt.width, lineArt.height);
    final fillWidth = (lineArt.width * scale).round();
    final fillHeight = (lineArt.height * scale).round();

    final thumbCodec = await ui.instantiateImageCodec(
      lineBytes,
      targetWidth: fillWidth,
      targetHeight: fillHeight,
    );
    final thumb = (await thumbCodec.getNextFrame()).image;
    thumbCodec.dispose();
    final pixelData = await thumb.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    thumb.dispose();
    final lineRgba = pixelData!.buffer.asUint8List(
      pixelData.offsetInBytes,
      pixelData.lengthInBytes,
    );

    // 只把可发送的值送进 Isolate，绝不捕获 ui.Image。
    final backgroundMask = await Isolate.run(
      () => computeBackgroundMask(
        rgba: lineRgba,
        width: fillWidth,
        height: fillHeight,
      ),
    );

    return PageAssets._(
      lineArt,
      paper,
      fillWidth,
      fillHeight,
      lineRgba,
      backgroundMask,
    );
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}

class Stroke {
  final List<Offset> points;
  final Color color;
  final double width;

  const Stroke({
    required this.points,
    required this.color,
    required this.width,
  });
}

class PageArtwork {
  final PageAssets assets;
  final Uint8List colorPixels;
  ui.Image colorImage;
  final List<Stroke> strokes;
  bool isFilling;

  PageArtwork._(this.assets, this.colorPixels, this.colorImage)
    : strokes = [],
      isFilling = false;

  static Future<PageArtwork> create(PageAssets assets) async {
    final colorPixels = Uint8List(assets.fillWidth * assets.fillHeight * 4);
    final colorImage = await _makeColorImage(
      colorPixels,
      assets.fillWidth,
      assets.fillHeight,
    );
    return PageArtwork._(assets, colorPixels, colorImage);
  }

  /// colorPixels 是唯一数据源，改完后用它重生成图像。
  Future<void> refreshColorImage() async {
    final image = await _makeColorImage(
      colorPixels,
      assets.fillWidth,
      assets.fillHeight,
    );
    colorImage.dispose();
    colorImage = image;
  }
}

Future<ui.Image> _makeColorImage(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class ColoringCanvas extends StatefulWidget {
  final PageArtwork artwork;
  final PaintMode mode;
  final Color color;
  final ValueChanged<Offset> onFillRequested;
  final VoidCallback onArtworkChanged;

  const ColoringCanvas({
    required this.artwork,
    required this.mode,
    required this.color,
    required this.onFillRequested,
    required this.onArtworkChanged,
    super.key,
  });

  @override
  ColoringCanvasState createState() => ColoringCanvasState();
}

class ColoringCanvasState extends State<ColoringCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  Offset? _pulseCenter;
  int? _activePointer;
  Stroke? _currentStroke;

  /// 成功的填充由外层调用，落点脉冲只在真的填上色时出现。
  void flashPulse(Offset normalized) {
    _pulseCenter = normalized;
    _pulse.forward(from: 0);
  }

  static Offset _normalize(Offset p, Size size) => Offset(
    (p.dx / size.width).clamp(0.0, 1.0),
    (p.dy / size.height).clamp(0.0, 1.0),
  );

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    final point = _normalize(event.localPosition, size);
    if (widget.mode == PaintMode.fill) {
      widget.onFillRequested(point);
      return;
    }
    final stroke = Stroke(points: [point], color: widget.color, width: 22);
    widget.artwork.strokes.add(stroke);
    _currentStroke = stroke;
    widget.onArtworkChanged();
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (event.pointer != _activePointer) return;
    final stroke = _currentStroke;
    if (stroke == null) return;
    stroke.points.add(_normalize(event.localPosition, size));
    widget.onArtworkChanged();
  }

  void _clearPointer(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    _currentStroke = null;
  }

  @override
  void didUpdateWidget(ColoringCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.artwork, widget.artwork) ||
        oldWidget.mode != widget.mode) {
      _activePointer = null;
      _currentStroke = null;
      _pulse.stop();
      _pulseCenter = null;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = widget.artwork.assets;
    return AspectRatio(
      aspectRatio: assets.lineArt.width / assets.lineArt.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _onPointerDown(e, size),
            onPointerMove: (e) => _onPointerMove(e, size),
            onPointerUp: (e) => _clearPointer(e.pointer),
            onPointerCancel: (e) => _clearPointer(e.pointer),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: PagePainter(
                  widget.artwork,
                  pulseCenter: _pulseCenter,
                  pulse: _pulse.value,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PagePainter extends CustomPainter {
  final PageArtwork artwork;
  final Offset? pulseCenter;
  final double pulse;

  PagePainter(this.artwork, {this.pulseCenter, this.pulse = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;

    void drawImage(ui.Image image) {
      canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        dst,
        imagePaint,
      );
    }

    drawImage(artwork.assets.paper);
    drawImage(artwork.colorImage);

    canvas.save();
    canvas.clipRect(dst);
    for (final stroke in artwork.strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.width;
      Offset scaled(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
      // 单点 Stroke 画不出线，补一个圆点，孩子点一下也有痕迹。
      if (stroke.points.length == 1) {
        canvas.drawPoints(
          ui.PointMode.points,
          [scaled(stroke.points.first)],
          paint,
        );
        continue;
      }
      final path = Path()..moveTo(
        scaled(stroke.points.first).dx,
        scaled(stroke.points.first).dy,
      );
      for (final point in stroke.points.skip(1)) {
        final p = scaled(point);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();

    drawImage(artwork.assets.lineArt);

    final center = pulseCenter;
    if (center != null && pulse < 1) {
      canvas.drawCircle(
        Offset(center.dx * size.width, center.dy * size.height),
        size.shortestSide * (0.02 + 0.08 * pulse),
        Paint()..color = Colors.white.withValues(alpha: 1 - pulse),
      );
    }
  }

  @override
  bool shouldRepaint(PagePainter oldDelegate) => true;
}
