import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

/// 旋钮风格滑块
class KnobSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String label;
  final String? subtitle;
  final String Function(double)? valueLabel;

  const KnobSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 99,
    this.divisions = 99,
    required this.onChanged,
    required this.label,
    this.subtitle,
    this.valueLabel,
  });

  @override
  State<KnobSlider> createState() => _KnobSliderState();
}

class _KnobSliderState extends State<KnobSlider> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final normalizedValue =
        ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    final displayValue =
        widget.valueLabel?.call(widget.value) ?? widget.value.toInt().toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (widget.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              // 数值显示 — LCD 风格
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _isDragging ? AppColors.amber : AppColors.borderSubtle,
                    width: 1,
                  ),
                ),
                child: Text(
                  displayValue,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _isDragging ? AppColors.amber : AppColors.textPrimary,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 滑轨
          SizedBox(
            height: 28,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                return GestureDetector(
                  onPanStart: (details) {
                    setState(() => _isDragging = true);
                    _updateValue(details.localPosition.dx, trackWidth);
                  },
                  onPanUpdate: (details) {
                    _updateValue(details.localPosition.dx, trackWidth);
                  },
                  onPanEnd: (_) {
                    setState(() => _isDragging = false);
                  },
                  onTapDown: (details) {
                    _updateValue(details.localPosition.dx, trackWidth);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: CustomPaint(
                      size: Size(trackWidth, 28),
                      painter: _KnobTrackPainter(
                        value: normalizedValue,
                        isDragging: _isDragging,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _updateValue(double dx, double trackWidth) {
    final ratio = (dx / trackWidth).clamp(0.0, 1.0);
    final rawValue = widget.min + ratio * (widget.max - widget.min);
    final snapped = (rawValue / ((widget.max - widget.min) / widget.divisions))
            .round() *
        ((widget.max - widget.min) / widget.divisions);
    widget.onChanged(snapped.clamp(widget.min, widget.max));
  }
}

class _KnobTrackPainter extends CustomPainter {
  final double value;
  final bool isDragging;

  _KnobTrackPainter({required this.value, required this.isDragging});

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = size.height / 2;
    const trackH = 4.0;
    const knobRadius = 8.0;

    // 轨道背景
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY - trackH / 2, size.width, trackH),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      trackRect,
      Paint()..color = const Color(0xFF2A2A30),
    );

    // 已填充部分
    final fillWidth = value * size.width;
    if (fillWidth > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY - trackH / 2, fillWidth, trackH),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        fillRect,
        Paint()
          ..shader = const LinearGradient(
            colors: [AppColors.amberDim, AppColors.amber],
          ).createShader(Rect.fromLTWH(0, 0, fillWidth, trackH)),
      );
    }

    // 刻度线
    const numTicks = 10;
    for (int i = 0; i <= numTicks; i++) {
      final x = (i / numTicks) * size.width;
      final isActive = x <= fillWidth;
      canvas.drawLine(
        Offset(x, trackY + trackH / 2 + 3),
        Offset(x, trackY + trackH / 2 + 7),
        Paint()
          ..color = isActive
              ? AppColors.amber.withValues(alpha: 0.5)
              : const Color(0xFF3A3A40)
          ..strokeWidth = 1,
      );
    }

    // 旋钮
    final knobX = value * size.width;

    // 光晕
    if (isDragging) {
      canvas.drawCircle(
        Offset(knobX, trackY),
        knobRadius + 6,
        Paint()..color = AppColors.amber.withValues(alpha: 0.1),
      );
    }

    // 外环
    canvas.drawCircle(
      Offset(knobX, trackY),
      knobRadius,
      Paint()..color = const Color(0xFF3A3A42),
    );

    // 内圈渐变
    canvas.drawCircle(
      Offset(knobX, trackY),
      knobRadius - 1.5,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF5A5A60), Color(0xFF2E2E34)],
        ).createShader(
          Rect.fromCircle(center: Offset(knobX, trackY), radius: knobRadius),
        ),
    );

    // 指示线
    canvas.drawLine(
      Offset(knobX, trackY - 3),
      Offset(knobX, trackY + 3),
      Paint()
        ..color = isDragging ? AppColors.amber : AppColors.textSecondary
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _KnobTrackPainter oldDelegate) =>
      value != oldDelegate.value || isDragging != oldDelegate.isDragging;
}
