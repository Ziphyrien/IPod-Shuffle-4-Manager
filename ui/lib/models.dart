/// iPod Shuffle 4G Manager 数据模型

class ShufflerConfig {
  String ipodPath;
  bool trackVoiceover;
  bool playlistVoiceover;
  bool renameUnicode;
  int trackGain; // 0-99
  bool autoTrackGain;
  int? autoDirPlaylists; // null=禁用, -1=无限
  String? autoId3Playlists; // null=禁用
  bool verbose;

  ShufflerConfig({
    this.ipodPath = '',
    this.trackVoiceover = false,
    this.playlistVoiceover = false,
    this.renameUnicode = false,
    this.trackGain = 0,
    this.autoTrackGain = false,
    this.autoDirPlaylists,
    this.autoId3Playlists,
    this.verbose = false,
  });

  /// 生成命令行参数列表
  List<String> toArgs() {
    final args = <String>[];
    if (trackVoiceover) args.add('--track-voiceover');
    if (playlistVoiceover) args.add('--playlist-voiceover');
    if (renameUnicode) args.add('--rename-unicode');
    if (trackGain > 0) {
      args.addAll(['--track-gain', trackGain.toString()]);
    }
    if (autoTrackGain) args.add('--auto-track-gain');
    if (autoDirPlaylists != null) {
      args.addAll(['--auto-dir-playlists', autoDirPlaylists.toString()]);
    }
    if (autoId3Playlists != null) {
      args.addAll(['--auto-id3-playlists', autoId3Playlists!]);
    }
    if (verbose) args.add('--verbose');
    args.add(ipodPath);
    return args;
  }
}

class SyncResult {
  final int tracks;
  final int albums;
  final int artists;
  final int playlists;

  const SyncResult({
    this.tracks = 0,
    this.albums = 0,
    this.artists = 0,
    this.playlists = 0,
  });
}
