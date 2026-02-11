import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

/// 终端风格日志面板
class ConsoleLog extends StatefulWidget {
  final List<LogEntry> entries;
  final double height;

  const ConsoleLog({
    super.key,
    required this.entries,
    this.height = 200,
  });

  @override
  State<ConsoleLog> createState() => _ConsoleLogState();
}

class _ConsoleLogState extends State<ConsoleLog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(ConsoleLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries.length > oldWidget.entries.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: AppDecorations.consoleBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.entries.isEmpty
                        ? AppColors.textMuted
                        : AppColors.ledGreen,
                    boxShadow: widget.entries.isNotEmpty
                        ? [
                            BoxShadow(
                              color: AppColors.ledGreen.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'CONSOLE OUTPUT',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.entries.length} lines',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // 日志内容
          Expanded(
            child: widget.entries.isEmpty
                ? Center(
                    child: Text(
                      '等待操作...',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: widget.entries.length,
                    itemBuilder: (context, index) {
                      final entry = widget.entries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 行号
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${index + 1}'.padLeft(3),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: AppColors.textMuted.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                            // 类型指示
                            Text(
                              entry.isError ? '▸ ' : '  ',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: entry.isError
                                    ? AppColors.ledRed
                                    : AppColors.amber,
                              ),
                            ),
                            // 内容
                            Expanded(
                              child: Text(
                                entry.text,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: entry.isError
                                      ? AppColors.ledRed
                                      : entry.isSystem
                                          ? AppColors.amber
                                          : AppColors.textPrimary
                                              .withValues(alpha: 0.85),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 日志条目
class LogEntry {
  final String text;
  final bool isError;
  final bool isSystem;
  final DateTime timestamp;

  LogEntry({
    required this.text,
    this.isError = false,
    this.isSystem = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
