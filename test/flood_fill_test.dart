import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tule/flood_fill.dart';

Uint8List wallsFromRows(List<String> rows) {
  final h = rows.length, w = rows[0].length;
  final data = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      data[i + 3] = rows[y][x] == '#' ? 255 : 0;
    }
  }
  return data;
}

const ring = [
  '         ',
  '         ',
  '  #####  ',
  '  #   #  ',
  '  #   #  ',
  '  #   #  ',
  '  #####  ',
  '         ',
  '         ',
];

void main() {
  test('background mask marks border-connected area only', () {
    final bg = computeBackgroundMask(
        rgba: wallsFromRows(ring), width: 9, height: 9);
    expect(bg[0], 1);          // 角上是背景
    expect(bg[4 * 9 + 4], 0);  // 环内不是背景
  });

  test('enclosed region fills and does not touch border', () {
    final r = computeFillRegion(
        rgba: wallsFromRows(ring), width: 9, height: 9,
        startX: 4, startY: 4);
    expect(r.foundStart, isTrue);
    expect(r.touchesBorder, isFalse);
    expect(r.area, 9);
    expect(r.mask[4 * 9 + 4], 1);
    expect(r.mask[3 * 9 + 3], 1);
    expect(r.mask[0], 0);
    expect(r.mask[2 * 9 + 2], 0); // 墙上
  });

  test('tap on background does nothing', () {
    final r = computeFillRegion(
        rgba: wallsFromRows(ring), width: 9, height: 9,
        startX: 0, startY: 0);
    expect(r.foundStart, isFalse);
  });

  test('tap on a wall snaps to the enclosed side', () {
    final r = computeFillRegion(
        rgba: wallsFromRows(ring), width: 9, height: 9,
        startX: 2, startY: 4);
    expect(r.foundStart, isTrue);
    expect(r.area, 9);
    expect(r.touchesBorder, isFalse);
  });

  test('a gap large enough to leak makes the interior unfillable', () {
    final leaky = [
      '         ',
      '         ',
      '  #   #  ', // 3px 缺口，1px 膨胀后仍漏
      '  #   #  ',
      '  #   #  ',
      '  #   #  ',
      '  #####  ',
      '         ',
      '         ',
    ];
    final bg = computeBackgroundMask(
        rgba: wallsFromRows(leaky), width: 9, height: 9);
    expect(bg[4 * 9 + 4], 1); // 内部与外界连通，被判定为背景
    final r = computeFillRegion(
        rgba: wallsFromRows(leaky), width: 9, height: 9,
        startX: 4, startY: 4);
    expect(r.foundStart, isFalse);
  });

  test('applyRegionColor writes only masked pixels', () {
    final rgba = Uint8List(8); // 2 个透明像素
    final mask = Uint8List.fromList([1, 0]);
    applyRegionColor(rgba, mask, 0xFFFF0000);
    expect(rgba.sublist(0, 4), [255, 0, 0, 255]);
    expect(rgba.sublist(4, 8), [0, 0, 0, 0]);
  });

  test('normalizedToPixel clamps both ends', () {
    expect(normalizedToPixel(0, 0, 10, 20), (0, 0));
    expect(normalizedToPixel(1, 1, 10, 20), (9, 19));
    expect(normalizedToPixel(0.5, 0.5, 10, 10), (5, 5));
  });
}
