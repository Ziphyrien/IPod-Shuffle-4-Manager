import 'package:flutter/material.dart';
import '../theme.dart';

/// LED 状态指示灯
class LedIndicator extends StatefulWidget {
  final bool isOn;
  final Color color;
  final double size;
  final bool pulsing;

  const LedIndicator({
    super.key,
    this.isOn = false,
    this.color = AppColors.ledGreen,
    this.size = 8,
    this.pulsing = false,
  });

  @override
  State<LedIndicator> createState() => _LedIndicatorState();
}

class _LedIndicatorState extends State<LedIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    if (widget.pulsing && widget.isOn) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(LedIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && widget.isOn) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulseValue = widget.pulsing ? _pulseController.value : 0.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isOn
                ? widget.color.withValues(alpha: 0.8 + pulseValue * 0.2)
                : widget.color.withValues(alpha: 0.15),
            boxShadow: widget.isOn
                ? [
                    BoxShadow(
                      color: widget.color
                          .withValues(alpha: 0.4 + pulseValue * 0.3),
                      blurRadius: 6 + pulseValue * 4,
                      spreadRadius: -1,
                    ),
                  ]
                : null,
            border: Border.all(
              color: widget.isOn
                  ? widget.color.withValues(alpha: 0.5)
                  : widget.color.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
        );
      },
    );
  }
}
