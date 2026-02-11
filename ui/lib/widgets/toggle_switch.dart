import 'package:flutter/material.dart';
import '../theme.dart';

/// 仿硬件拨动开关
class ToggleSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? subtitle;

  const ToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.subtitle,
  });

  @override
  State<ToggleSwitch> createState() => _ToggleSwitchState();
}

class _ToggleSwitchState extends State<ToggleSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnim;
  late Animation<Color?> _colorAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
    _slideAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _colorAnim = ColorTween(
      begin: AppColors.textMuted,
      end: AppColors.amber,
    ).animate(_controller);
  }

  @override
  void didUpdateWidget(ToggleSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      widget.value ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onChanged(!widget.value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              // 标签
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
              const SizedBox(width: 12),
              // 开关
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Container(
                    width: 48,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: AppColors.bgDeep,
                      border: Border.all(
                        color: _colorAnim.value ?? AppColors.textMuted,
                        width: 1.5,
                      ),
                      boxShadow: widget.value
                          ? [
                              BoxShadow(
                                color: AppColors.amber.withValues(alpha: 0.15),
                                blurRadius: 8,
                                spreadRadius: -2,
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      children: [
                        // 轨道标签
                        Positioned(
                          left: 6,
                          top: 5,
                          child: Text(
                            'ON',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.amber
                                  .withValues(alpha: _slideAnim.value * 0.7),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 5,
                          child: Text(
                            'OFF',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted
                                  .withValues(alpha: (1 - _slideAnim.value) * 0.7),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        // 滑块
                        Positioned(
                          left: 2 + (_slideAnim.value * 22),
                          top: 2,
                          child: Container(
                            width: 20,
                            height: 18,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: widget.value
                                    ? [
                                        AppColors.amber,
                                        AppColors.amberDim,
                                      ]
                                    : [
                                        AppColors.textMuted,
                                        const Color(0xFF3A3A3A),
                                      ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            // 拉丝纹理
                            child: Center(
                              child: Container(
                                width: 10,
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
