import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

/// iPod Shuffle 4 代设备可视化
class IpodDevice extends StatefulWidget {
  final bool isConnected;
  final String? devicePath;
  final String? freeSpace;

  const IpodDevice({
    super.key,
    this.isConnected = false,
    this.devicePath,
    this.freeSpace,
  });

  @override
  State<IpodDevice> createState() => _IpodDeviceState();
}

class _IpodDeviceState extends State<IpodDevice>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _IpodPainter(
            isConnected: widget.isConnected,
            animValue: _controller.value,
          ),
          child: SizedBox(
            width: 160,
            height: 280,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 状态信息
                if (widget.isConnected) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bgDeep.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.ledGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.ledGreen,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.ledGreen
                                        .withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '已连接',
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: AppColors.ledGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (widget.freeSpace != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.freeSpace!,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 30),
                    child: Text(
                      '未连接',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IpodPainter extends CustomPainter {
  final bool isConnected;
  final double animValue;

  _IpodPainter({required this.isConnected, required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final deviceW = 100.0;
    final deviceH = 200.0;
    final left = cx - deviceW / 2;
    final top = 20.0;

    // 设备体渐变
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, deviceW, deviceH),
      const Radius.circular(10),
    );

    // 外部光晕
    if (isConnected) {
      final glowPaint = Paint()
        ..color = AppColors.amber
            .withValues(alpha: 0.06 + math.sin(animValue * 2 * math.pi) * 0.03);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left - 4, top - 4, deviceW + 8, deviceH + 8),
          const Radius.circular(14),
        ),
        glowPaint,
      );
    }

    // 设备主体
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A2A30),
            const Color(0xFF1A1A20),
            const Color(0xFF151518),
          ],
        ).createShader(Rect.fromLTWH(left, top, deviceW, deviceH)),
    );

    // 设备边框
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = isConnected
            ? AppColors.amber.withValues(alpha: 0.3)
            : AppColors.borderSubtle
        ..strokeWidth = 1.5,
    );

    // 圆形控制区（iPod Click Wheel）
    final wheelCx = cx;
    final wheelCy = top + deviceH * 0.6;
    final wheelR = 32.0;

    // 外环
    canvas.drawCircle(
      Offset(wheelCx, wheelCy),
      wheelR,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.borderSubtle
        ..strokeWidth = 2,
    );

    // 刻度
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi - math.pi / 2;
      final startR = wheelR - 4;
      final endR = wheelR - 8;
      canvas.drawLine(
        Offset(wheelCx + math.cos(angle) * startR,
            wheelCy + math.sin(angle) * startR),
        Offset(wheelCx + math.cos(angle) * endR,
            wheelCy + math.sin(angle) * endR),
        Paint()
          ..color = AppColors.textMuted.withValues(alpha: 0.3)
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      );
    }

    // 中心按钮
    canvas.drawCircle(
      Offset(wheelCx, wheelCy),
      10,
      Paint()
        ..shader = RadialGradient(
          colors: [
            isConnected ? AppColors.amber.withValues(alpha: 0.4) : const Color(0xFF3A3A40),
            isConnected ? AppColors.amberDim.withValues(alpha: 0.3) : const Color(0xFF2A2A30),
          ],
        ).createShader(
          Rect.fromCircle(center: Offset(wheelCx, wheelCy), radius: 10),
        ),
    );

    // 屏幕区域（小方块代表屏幕）
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + 18, top + 18, deviceW - 36, 40),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      screenRect,
      Paint()..color = const Color(0xFF0A0A0E),
    );
    canvas.drawRRect(
      screenRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.borderSubtle.withValues(alpha: 0.5)
        ..strokeWidth = 0.5,
    );

    // 屏幕上的文字
    final textPainter = TextPainter(
      text: TextSpan(
        text: isConnected ? '♫ READY' : 'NO DEVICE',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          color: isConnected ? AppColors.amber : AppColors.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        cx - textPainter.width / 2,
        top + 32,
      ),
    );

    // 夹子
    final clipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + deviceW - 6, top + 30, 10, 50),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      clipRect,
      Paint()..color = const Color(0xFF2A2A30),
    );
    canvas.drawRRect(
      clipRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.borderSubtle
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _IpodPainter oldDelegate) =>
      isConnected != oldDelegate.isConnected ||
      animValue != oldDelegate.animValue;
}
