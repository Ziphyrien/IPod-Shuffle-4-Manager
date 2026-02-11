use clap::Parser;

// ─── Constants ───────────────────────────────────────────────────────────────

pub const AUDIO_EXT: &[&str] = &[".mp3", ".m4a", ".m4b", ".m4p", ".aa", ".wav", ".flac"];
pub const MUSIC_EXT: &[&str] = &[".mp3", ".m4a", ".m4b", ".m4p", ".aa", ".wav"];
pub const LIST_EXT: &[&str] = &[".pls", ".m3u"];

// ─── CLI ─────────────────────────────────────────────────────────────────────

#[derive(Parser)]
#[command(
    version,
    about = "用于为较新一代 iPod Shuffle 构建曲目和播放列表数据库的工具",
)]
pub struct Cli {
    /// 启用曲目旁白功能
    #[arg(short = 't', long = "track-voiceover")]
    pub track_voiceover: bool,

    /// 启用播放列表旁白功能
    #[arg(short = 'p', long = "playlist-voiceover")]
    pub playlist_voiceover: bool,

    /// 重命名导致 Unicode 错误的文件
    #[arg(short = 'u', long = "rename-unicode")]
    pub rename_unicode: bool,

    /// 指定所有曲目的音量增益 (0-99)
    #[arg(short = 'g', long = "track-gain", default_value_t = 0, value_parser = clap::value_parser!(u32).range(0..=99))]
    pub track_gain: u32,

    /// 自动音量均衡
    #[arg(long = "auto-track-gain")]
    pub auto_track_gain: bool,

    /// 为 "iPod_Control/Music/" 内的每个文件夹递归生成自动播放列表。
    /// 可选限制深度: 0=根目录, 1=艺术家, 2=专辑, n=子文件夹, 默认=-1 (无限制)
    #[arg(short = 'd', long = "auto-dir-playlists", num_args = 0..=1, default_missing_value = "-1")]
    pub auto_dir_playlists: Option<i32>,

    /// 根据 ID3 标签生成自动播放列表。可指定模板字符串，如
    /// '{artist} - {album}' 按艺术家+专辑分组，'{genre}' 按流派分组。
    /// 默认模板: '{artist}'
    #[arg(short = 'i', long = "auto-id3-playlists", num_args = 0..=1, default_missing_value = "{artist}")]
    pub auto_id3_playlists: Option<String>,

    /// 显示详细输出
    #[arg(short = 'v', long = "verbose")]
    pub verbose: bool,

    /// iPod 根目录的路径
    pub path: String,
}
