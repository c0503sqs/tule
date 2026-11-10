import 'dart:typed_data';

/// 一次洪水填充的结果。
class FillRegion {
  /// width*height，1 = 属于填充区域。
  final Uint8List mask;
  final int area;
  final bool foundStart;
  final bool touchesBorder;

  const FillRegion({
    required this.mask,
    required this.area,
    required this.foundStart,
    required this.touchesBorder,
  });
}

/// alpha 大于 [wallAlpha] 的像素视为墙。
List<bool> _walls(Uint8List rgba, int width, int height, int wallAlpha) {
  final n = width * height;
  final walls = List<bool>.filled(n, false);
  for (var p = 0; p < n; p++) {
    walls[p] = rgba[p * 4 + 3] > wallAlpha;
  }
  return walls;
}

/// 墙的 4 邻域膨胀一次，用于封住 1px 断口。
List<bool> _dilatedWalls(List<bool> walls, int width, int height) {
  final out = List<bool>.from(walls);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = y * width + x;
      if (!walls[p]) continue;
      if (x > 0) out[p - 1] = true;
      if (x < width - 1) out[p + 1] = true;
      if (y > 0) out[p - width] = true;
      if (y < height - 1) out[p + width] = true;
    }
  }
  return out;
}

/// 从图片四边做 4 邻接填充，返回与边界连通的背景掩码。
Uint8List computeBackgroundMask({
  required Uint8List rgba,
  required int width,
  required int height,
  int wallAlpha = 40,
}) {
  final n = width * height;
  final bg = Uint8List(n);
  if (n == 0) return bg;

  final walls =
      _dilatedWalls(_walls(rgba, width, height, wallAlpha), width, height);
  final stack = <int>[];

  void seed(int x, int y) {
    final p = y * width + x;
    if (walls[p] || bg[p] == 1) return;
    bg[p] = 1;
    stack.add(p);
  }

  for (var x = 0; x < width; x++) {
    seed(x, 0);
    seed(x, height - 1);
  }
  for (var y = 0; y < height; y++) {
    seed(0, y);
    seed(width - 1, y);
  }

  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % width, y = p ~/ width;
    if (x > 0) seed(x - 1, y);
    if (x < width - 1) seed(x + 1, y);
    if (y > 0) seed(x, y - 1);
    if (y < height - 1) seed(x, y + 1);
  }
  return bg;
}

/// 从 [startX], [startY] 做 4 邻接填充；起点在背景里返回空结果，点在墙上时向外吸附。
FillRegion computeFillRegion({
  required Uint8List rgba,
  required int width,
  required int height,
  required int startX,
  required int startY,
  Uint8List? backgroundMask,
  int wallAlpha = 40,
  int snapRadius = 8,
}) {
  final n = width * height;
  final mask = Uint8List(n);
  if (startX < 0 || startX >= width || startY < 0 || startY >= height) {
    return FillRegion(
        mask: mask, area: 0, foundStart: false, touchesBorder: false);
  }

  final walls = _walls(rgba, width, height, wallAlpha);
  final snapWalls = _dilatedWalls(walls, width, height);
  final bg = backgroundMask ??
      computeBackgroundMask(
          rgba: rgba, width: width, height: height, wallAlpha: wallAlpha);

  var sx = startX, sy = startY;
  // 点在背景上不填充：只有点墙（含膨胀带）才吸附到最近的封闭侧。
  if (bg[sy * width + sx] != 0) {
    return FillRegion(
        mask: mask, area: 0, foundStart: false, touchesBorder: false);
  }
  if (snapWalls[sy * width + sx]) {
    var found = false;
    for (var r = 1; r <= snapRadius && !found; r++) {
      for (var dy = -r; dy <= r && !found; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dy.abs() != r) continue;
          final x = startX + dx, y = startY + dy;
          if (x < 0 || x >= width || y < 0 || y >= height) continue;
          final p = y * width + x;
          if (!snapWalls[p] && bg[p] == 0) {
            sx = x;
            sy = y;
            found = true;
            break;
          }
        }
      }
    }
    if (!found) {
      return FillRegion(
          mask: mask, area: 0, foundStart: false, touchesBorder: false);
    }
  }

  var area = 0;
  var touchesBorder = false;
  final stack = <int>[sy * width + sx];
  mask[sy * width + sx] = 1;

  void visit(int q) {
    if (mask[q] == 0 && !walls[q]) {
      mask[q] = 1;
      stack.add(q);
    }
  }

  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % width, y = p ~/ width;
    area++;
    if (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
      touchesBorder = true;
    }
    if (x > 0) visit(p - 1);
    if (x < width - 1) visit(p + 1);
    if (y > 0) visit(p - width);
    if (y < height - 1) visit(p + width);
  }

  return FillRegion(
      mask: mask, area: area, foundStart: true, touchesBorder: touchesBorder);
}

/// 给掩码内的像素写入颜色，alpha 固定 255。
void applyRegionColor(Uint8List rgba, Uint8List mask, int colorArgb) {
  final r = (colorArgb >> 16) & 0xFF;
  final g = (colorArgb >> 8) & 0xFF;
  final b = colorArgb & 0xFF;
  for (var p = 0; p < mask.length; p++) {
    if (mask[p] == 0) continue;
    final i = p * 4;
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = 255;
  }
}

/// 归一化坐标转像素坐标，两端都夹紧。
(int x, int y) normalizedToPixel(
    double nx, double ny, int width, int height) {
  final x = (nx * width).floor().clamp(0, width - 1).toInt();
  final y = (ny * height).floor().clamp(0, height - 1).toInt();
  return (x, y);
}
