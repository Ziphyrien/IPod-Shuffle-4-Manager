import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../services/shuffler_service.dart';
import '../theme.dart';
import '../widgets/console_log.dart';
import '../widgets/ipod_device.dart';
import '../widgets/knob_slider.dart';
import '../widgets/led_indicator.dart';
import '../widgets/sync_button.dart';
import '../widgets/toggle_switch.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final ShufflerService _service = ShufflerService();
  final ShufflerConfig _config = ShufflerConfig();
  final List<LogEntry> _logEntries = [];
  bool _isSyncing = false;
  bool _isPathValid = false;
  bool _enableAutoDirPlaylists = false;
  bool _enableAutoId3Playlists = false;

  late AnimationController _fadeInController;

  @override
  void initState() {
    super.initState();
    _fadeInController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    super.dispose();
  }

  void _selectFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择 iPod 根目录',
    );
    if (result != null) {
      setState(() {
        _config.ipodPath = result;
        _isPathValid = _service.validatePath(result);
      });
      if (!_isPathValid) {
        _addLog('[SYS] 警告: 路径 "$result" 中未找到 iPod_Control 目录', isSystem: true);
      } else {
        _addLog('[SYS] iPod 路径已设置: $result', isSystem: true);
        // 尝试获取可用空间
        try {
          // 简单检查
          final dir = Directory(result);
          final stat = await dir.stat();
          _addLog('[SYS] 设备类型: ${stat.type}', isSystem: true);
        } catch (_) {}
      }
    }
  }

  void _startSync() {
    if (_config.ipodPath.isEmpty || !_isPathValid) return;
    setState(() {
      _isSyncing = true;
      _logEntries.clear();
    });
    _addLog('[SYS] ═══ 同步开始 ═══', isSystem: true);

    _service.startSync(
      _config,
      onOutput: (line) => _addLog(line),
      onError: (line) => _addLog(line, isError: true),
      onComplete: (exitCode) {
        _addLog(
          exitCode == 0
              ? '[SYS] ═══ 同步完成 (exit: $exitCode) ═══'
              : '[SYS] ═══ 同步失败 (exit: $exitCode) ═══',
          isSystem: true,
        );
        if (mounted) setState(() => _isSyncing = false);
      },
    );
  }

  void _cancelSync() {
    _service.cancelSync();
    _addLog('[SYS] 用户取消同步', isSystem: true);
    setState(() => _isSyncing = false);
  }

  void _addLog(String text, {bool isError = false, bool isSystem = false}) {
    if (mounted) {
      setState(() {
        _logEntries.add(LogEntry(
          text: text,
          isError: isError,
          isSystem: isSystem || text.startsWith('[SYS]'),
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: FadeTransition(
        opacity: CurvedAnimation(
          parent: _fadeInController,
          curve: Curves.easeOut,
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                children: [
                  // 左侧 iPod 设备区域
                  _buildDevicePanel(),
                  // 主内容区
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _buildConfigPanel()),
                        _buildConsolePanel(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部标题栏
  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: AppDecorations.headerBar,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // 拉丝纹理线
          Container(
            width: 3,
            height: 24,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.amber, AppColors.amberDim],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'iPod Shuffle 4G',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'MANAGER',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              fontWeight: FontWeight.w300,
              color: AppColors.amber,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          // 版本号
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Text(
              'v1.6.0',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 状态指示灯
          Row(
            children: [
              LedIndicator(
                isOn: _isPathValid,
                color: AppColors.ledGreen,
                size: 6,
                pulsing: _isSyncing,
              ),
              const SizedBox(width: 4),
              LedIndicator(
                isOn: _isSyncing,
                color: AppColors.amber,
                size: 6,
                pulsing: true,
              ),
              const SizedBox(width: 4),
              LedIndicator(
                isOn: false,
                color: AppColors.ledRed,
                size: 6,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 左侧设备面板
  Widget _buildDevicePanel() {
    return Container(
      width: 200,
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        border: Border(
          right: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // 区域标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'DEVICE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 1,
            color: AppColors.borderSubtle,
          ),
          const SizedBox(height: 20),
          // iPod 设备可视化
          Center(
            child: IpodDevice(
              isConnected: _isPathValid,
              devicePath: _config.ipodPath.isNotEmpty ? _config.ipodPath : null,
            ),
          ),
          const Spacer(),
          // 选择路径按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildPathSelector(),
          ),
        ],
      ),
    );
  }

  /// 路径选择器
  Widget _buildPathSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 路径显示
        if (_config.ipodPath.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.bgConsole,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: _isPathValid
                    ? AppColors.ledGreen.withValues(alpha: 0.3)
                    : AppColors.ledRed.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                LedIndicator(
                  isOn: true,
                  color: _isPathValid ? AppColors.ledGreen : AppColors.ledRed,
                  size: 5,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _config.ipodPath,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        // 选择按钮
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _selectFolder,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AppColors.borderActive),
                color: AppColors.bgCard,
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 14,
                      color: AppColors.amber.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '选择 iPod 目录',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 配置面板
  Widget _buildConfigPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 区域标题
          _buildSectionHeader('SYNC CONFIGURATION', Icons.tune_rounded),
          const SizedBox(height: 16),
          // 配置卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppDecorations.panelDecoration,
            child: Column(
              children: [
                // 旁白设置
                _buildSubHeader('语音旁白'),
                ToggleSwitch(
                  label: '曲目旁白',
                  subtitle: '为每首曲目生成中文语音',
                  value: _config.trackVoiceover,
                  onChanged: (v) => setState(() => _config.trackVoiceover = v),
                ),
                ToggleSwitch(
                  label: '播放列表旁白',
                  subtitle: '为每个播放列表生成语音',
                  value: _config.playlistVoiceover,
                  onChanged: (v) =>
                      setState(() => _config.playlistVoiceover = v),
                ),
                const SizedBox(height: 8),
                Divider(color: AppColors.borderSubtle.withValues(alpha: 0.5), height: 1),
                const SizedBox(height: 8),
                // 音量设置
                _buildSubHeader('音量控制'),
                KnobSlider(
                  label: '音量增益',
                  subtitle: '全局音量增益 (0-99)',
                  value: _config.trackGain.toDouble(),
                  min: 0,
                  max: 99,
                  divisions: 99,
                  onChanged: (v) =>
                      setState(() => _config.trackGain = v.toInt()),
                ),
                ToggleSwitch(
                  label: '自动音量均衡',
                  subtitle: '分析音频响度并自动调节增益',
                  value: _config.autoTrackGain,
                  onChanged: (v) =>
                      setState(() => _config.autoTrackGain = v),
                ),
                const SizedBox(height: 8),
                Divider(color: AppColors.borderSubtle.withValues(alpha: 0.5), height: 1),
                const SizedBox(height: 8),
                // 播放列表设置
                _buildSubHeader('自动播放列表'),
                ToggleSwitch(
                  label: '目录播放列表',
                  subtitle: '按文件夹自动生成播放列表',
                  value: _enableAutoDirPlaylists,
                  onChanged: (v) {
                    setState(() {
                      _enableAutoDirPlaylists = v;
                      _config.autoDirPlaylists = v ? -1 : null;
                    });
                  },
                ),
                if (_enableAutoDirPlaylists)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: KnobSlider(
                      label: '目录深度',
                      subtitle: '-1=无限制, 0=根目录, 1=艺术家...',
                      value: (_config.autoDirPlaylists ?? -1).toDouble(),
                      min: -1,
                      max: 5,
                      divisions: 6,
                      valueLabel: (v) {
                        final i = v.toInt();
                        return i == -1 ? '∞' : '$i';
                      },
                      onChanged: (v) =>
                          setState(() => _config.autoDirPlaylists = v.toInt()),
                    ),
                  ),
                ToggleSwitch(
                  label: 'ID3 标签播放列表',
                  subtitle: '按 ID3 元数据分组生成',
                  value: _enableAutoId3Playlists,
                  onChanged: (v) {
                    setState(() {
                      _enableAutoId3Playlists = v;
                      _config.autoId3Playlists = v ? '{artist}' : null;
                    });
                  },
                ),
                if (_enableAutoId3Playlists)
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 8, top: 6, bottom: 4),
                    child: _buildTemplateInput(),
                  ),
                const SizedBox(height: 8),
                Divider(color: AppColors.borderSubtle.withValues(alpha: 0.5), height: 1),
                const SizedBox(height: 8),
                // 其他
                _buildSubHeader('其他选项'),
                ToggleSwitch(
                  label: 'Unicode 规范化',
                  subtitle: '重命名含非 ASCII 字符的文件',
                  value: _config.renameUnicode,
                  onChanged: (v) =>
                      setState(() => _config.renameUnicode = v),
                ),
                ToggleSwitch(
                  label: '详细输出',
                  subtitle: '打印更多调试信息',
                  value: _config.verbose,
                  onChanged: (v) => setState(() => _config.verbose = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 同步按钮
          SyncButton(
            isSyncing: _isSyncing,
            isEnabled: _isPathValid && _config.ipodPath.isNotEmpty,
            onPressed: _startSync,
            onCancel: _cancelSync,
          ),
        ],
      ),
    );
  }

  /// ID3 模板输入框
  Widget _buildTemplateInput() {
    return Row(
      children: [
        Text(
          '模板:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: TextField(
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '{artist}',
                hintStyle: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              controller:
                  TextEditingController(text: _config.autoId3Playlists ?? '{artist}'),
              onChanged: (v) =>
                  _config.autoId3Playlists = v.isEmpty ? '{artist}' : v,
            ),
          ),
        ),
      ],
    );
  }

  /// 控制台面板
  Widget _buildConsolePanel() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      child: ConsoleLog(
        entries: _logEntries,
        height: 180,
      ),
    );
  }

  /// 区域标题
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.amber.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.borderSubtle.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// 子标题
  Widget _buildSubHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}
