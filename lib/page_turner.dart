import 'package:flutter/material.dart';

const Color _brown = Color(0xFF8D6E63);

/// 只提供左右按钮翻页；页点只显示，不响应点击。
class PageTurner extends StatelessWidget {
  final int pageCount;
  final int current;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const PageTurner({
    required this.pageCount,
    required this.current,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ArrowButton(
                icon: Icons.chevron_left,
                label: '上一页',
                onPressed: current > 0 ? onPrevious : null,
              ),
              _ArrowButton(
                icon: Icons.chevron_right,
                label: '下一页',
                onPressed: current < pageCount - 1 ? onNext : null,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pageCount; i++)
                Container(
                  width: i == current ? 12 : 9,
                  height: i == current ? 12 : 9,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: _brown.withValues(alpha: i == current ? 1 : 0.3),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ArrowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        width: 88,
        height: 88,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 64,
          padding: EdgeInsets.zero,
          color: _brown,
          disabledColor: _brown.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}
