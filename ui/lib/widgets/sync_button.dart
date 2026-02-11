import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

/// 琥珀金同步按钮，带脉冲动画
class SyncButton extends StatefulWidget {
  final bool isSyncing;
  final bool isEnabled;
  final VoidCallback onPressed;
  final VoidCallback? onCancel;

  const SyncButton({
    super.key,
    required this.isSyncing,
    required this.isEnabled,
    required this.onPressed,
    this.onCancel,
  });

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _hoverController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(SyncButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSyncing && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!widget.isSyncing) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.isEnabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      onEnter: (_) {
        _hoverController.forward();
      },
      onExit: (_) {
        _hoverController.reverse();
      },
      child: GestureDetector(
        onTap: widget.isEnabled
            ? (widget.isSyncing ? widget.onCancel : widget.onPressed)
            : null,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _hoverController]),
          builder: (context, _) {
            final hoverValue = _hoverController.value;
            final pulseValue = widget.isSyncing
                ? (math.sin(_pulseController.value * 2 * math.pi) + 1) / 2
                : 0.0;

            return Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: widget.isEnabled
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: widget.isSyncing
                            ? [
                                AppColors.ledRed.withValues(alpha: 0.8),
                                AppColors.ledRed.withValues(alpha: 0.6),
                              ]
                            : [
                                Color.lerp(
                                  AppColors.amber,
                                  AppColors.amberDim,
                                  0.2 - hoverValue * 0.2,
                                )!,
                                Color.lerp(
                                  AppColors.amberDim,
                                  AppColors.amber,
                                  hoverValue * 0.3,
                                )!,
                              ],
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF2A2A30), Color(0xFF22222A)],
                      ),
                border: Border.all(
                  color: widget.isEnabled
                      ? (widget.isSyncing ? AppColors.ledRed : AppColors.amber)
                            .withValues(alpha: 0.5 + hoverValue * 0.3)
                      : AppColors.borderSubtle,
                  width: 1,
                ),
                boxShadow: widget.isEnabled
                    ? [
                        BoxShadow(
                          color:
                              (widget.isSyncing
                                      ? AppColors.ledRed
                                      : AppColors.amber)
                                  .withValues(
                                    alpha:
                                        0.15 +
                                        hoverValue * 0.1 +
                                        pulseValue * 0.1,
                                  ),
                          blurRadius: 16 + hoverValue * 8 + pulseValue * 8,
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isSyncing) ...[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: widget.isEnabled
                              ? AppColors.bgDeep
                              : AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                    Text(
                      widget.isSyncing ? '取 消 同 步' : '开 始 同 步',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: widget.isEnabled
                            ? (widget.isSyncing
                                  ? Colors.white
                                  : AppColors.bgDeep)
                            : AppColors.textMuted,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
