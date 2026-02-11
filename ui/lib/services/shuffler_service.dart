import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models.dart';

/// 后端服务，调用 Rust CLI 可执行文件
class ShufflerService {
  Process? _process;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// 查找 Rust CLI 可执行文件路径
  String _findExecutable() {
    // 尝试多个位置
    final candidates = [
      // 与 ui/ 同级的 target/release
      '${Platform.resolvedExecutable.replaceAll(RegExp(r'[/\\][^/\\]+$'), '').replaceAll(RegExp(r'[/\\]ui[/\\].*'), '')}${Platform.pathSeparator}target${Platform.pathSeparator}release${Platform.pathSeparator}ipod-shuffle-4g${Platform.isWindows ? '.exe' : ''}',
      // 当前工作目录的上级
      '..${Platform.pathSeparator}target${Platform.pathSeparator}release${Platform.pathSeparator}ipod-shuffle-4g${Platform.isWindows ? '.exe' : ''}',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }

    // fallback: 假设在 PATH 中
    return 'ipod-shuffle-4g${Platform.isWindows ? '.exe' : ''}';
  }

  /// 验证 iPod 路径是否有效
  bool validatePath(String path) {
    if (path.isEmpty) return false;
    final dir = Directory(path);
    if (!dir.existsSync()) return false;
    // 检查 iPod_Control 目录
    final ipodControl = Directory('$path${Platform.pathSeparator}iPod_Control');
    return ipodControl.existsSync();
  }

  /// 启动同步任务
  Future<void> startSync(
    ShufflerConfig config, {
    required void Function(String line) onOutput,
    required void Function(String line) onError,
    required void Function(int exitCode) onComplete,
  }) async {
    if (_isRunning) return;
    _isRunning = true;

    final executable = _findExecutable();
    final args = config.toArgs();

    try {
      onOutput('[SYS] 启动: $executable ${args.join(' ')}');

      _process = await Process.start(
        executable,
        args,
        workingDirectory: config.ipodPath,
      );

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => onOutput(line));

      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => onError(line));

      final exitCode = await _process!.exitCode;
      _isRunning = false;
      _process = null;
      onComplete(exitCode);
    } catch (e) {
      _isRunning = false;
      _process = null;
      onError('[SYS] 执行失败: $e');
      onComplete(-1);
    }
  }

  /// 终止同步任务
  void cancelSync() {
    if (_process != null) {
      _process!.kill();
      _process = null;
      _isRunning = false;
    }
  }
}
