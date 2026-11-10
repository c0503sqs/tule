import 'dart:async';

import 'package:flutter/material.dart';

import 'coloring_page.dart';

/// 10 个可涂颜色，默认第一个红色。
const List<Color> kPalette = [
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF00ACC1),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
  Color(0xFFEC407A),
  Color(0xFF8D6E63),
  Color(0xFF212121),
];

const Color _brown = Color(0xFF8D6E63);

class ColorPalette extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onSelected;

  const ColorPalette({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // 横屏 iPhone 装不下 10 个 56px 圆点时整体缩小，不折行、不溢出。
    return SizedBox(
      height: 64,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final color in kPalette)
              GestureDetector(
                onTap: () => onSelected(color),
                child: AnimatedScale(
                  scale: color == selected ? 1.1 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    width: 56,
                    height: 56,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: color == selected ? 4 : 0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ModeToggle extends StatelessWidget {
  final PaintMode mode;
  final ValueChanged<PaintMode> onChanged;

  const ModeToggle({required this.mode, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeButton(
          icon: Icons.format_color_fill,
          label: '填色',
          selected: mode == PaintMode.fill,
          onTap: () => onChanged(PaintMode.fill),
        ),
        const SizedBox(width: 16),
        _ModeButton(
          icon: Icons.brush,
          label: '涂鸦',
          selected: mode == PaintMode.doodle,
          onTap: () => onChanged(PaintMode.doodle),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.1 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _brown,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 4,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
      ),
    );
  }
}

/// 长按满 1 秒才重来，短按无反应。
class ResetButton extends StatefulWidget {
  final VoidCallback onReset;

  const ResetButton({required this.onReset, super.key});

  @override
  State<ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<ResetButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  Timer? _timer;
  int? _activePointer;

  // 用原始指针而不是长按手势：长按 accepted 后系统发 PointerCancel 时，
  // GestureDetector 不会再回调 onLongPressEnd/Cancel，计时会漏取消。
  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _progress.forward(from: 0);
    _timer = Timer(const Duration(seconds: 1), () {
      _progress
        ..stop()
        ..value = 1;
      widget.onReset();
    });
  }

  void _onPointerRelease(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _timer?.cancel();
    _timer = null;
    _progress.reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerRelease,
      onPointerCancel: _onPointerRelease,
      child: Semantics(
        label: '长按重来',
        button: true,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: _brown,
                  shape: BoxShape.circle,
                ),
              ),
              AnimatedBuilder(
                animation: _progress,
                builder: (context, _) {
                  final value = _progress.value;
                  if (value <= 0 || value >= 1) return const SizedBox.shrink();
                  return SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 5,
                      color: const Color(0xFF43A047),
                    ),
                  );
                },
              ),
              const Icon(Icons.autorenew, color: Colors.white, size: 36),
            ],
          ),
        ),
      ),
    );
  }
}
