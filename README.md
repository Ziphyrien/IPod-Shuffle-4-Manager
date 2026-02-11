# IPod Shuffle 4 Manager

用于为较新一代 iPod Shuffle 构建曲目和播放列表数据库的 Rust 原生工具。
从 [nims11/IPod-Shuffle-4g](https://github.com/nims11/IPod-Shuffle-4g) 分支，使用 Rust 完全重写。

只需将您的音频文件放入 iPod 的大容量存储中，`ipod-shuffle-4g` 将完成剩下的工作。

```text
$ ipod-shuffle-4g --help
用于为较新一代 iPod Shuffle 构建曲目和播放列表数据库的工具。版本 1.6.0

Usage: ipod-shuffle-4g [OPTIONS] <PATH>

Arguments:
  <PATH>  iPod 根目录的路径

Options:
  -t, --track-voiceover
          启用曲目旁白功能
  -p, --playlist-voiceover
          启用播放列表旁白功能
  -u, --rename-unicode
          重命名导致 Unicode 错误的文件
  -g, --track-gain <TRACK_GAIN>
          指定所有曲目的音量增益 (0-99) [default: 0]
      --auto-track-gain
          自动音量均衡
  -d, --auto-dir-playlists [<AUTO_DIR_PLAYLISTS>]
          为 "iPod_Control/Music/" 内的每个文件夹递归生成自动播放列表。
          可选限制深度: 0=根目录, 1=艺术家, 2=专辑, n=子文件夹, 默认=-1 (无限制)
  -i, --auto-id3-playlists [<AUTO_ID3_PLAYLISTS>]
          根据 ID3 标签生成自动播放列表。可指定模板字符串，如
          '{artist} - {album}' 按艺术家+专辑分组，'{genre}' 按流派分组。
          默认模板: '{artist}'
  -v, --verbose
          显示详细输出
  -h, --help
          Print help
  -V, --version
          Print version
```

## 构建

需要 [Rust 工具链](https://rustup.rs/)：

```bash
cargo build --release
```

编译后的二进制文件位于 `target/release/ipod-shuffle-4g`。

所有依赖均为 Rust crate，由 Cargo 自动管理，无需额外安装：

* **symphonia** — 音频解码（FLAC/MP3 等）
* **mp3lame-encoder** — FLAC→MP3 编码（320kbps）
* **lofty** — ID3 标签读写
* **msedge-tts** — Edge TTS 中文语音合成（无需 Python）
* **rayon** — 并发 FLAC 转换与响度分析
* **hound** — WAV 文件写入

## 功能特性

* **FLAC 自动转换**: 自动将 FLAC 文件并发转换为 320kbps MP3，保留元数据并删除源文件
* **中文语音旁白**: 使用 Edge TTS 原生 crate 生成高质量中文语音（无需 Python）
* **自动音量均衡**: 直接解码分析音频内容并写入 `volume_gain`
* **并发处理**: 使用 Rayon 并行处理 FLAC 转换和响度分析
* **跨平台**: 原生编译，支持 Windows/Linux/macOS
* **零运行时依赖**: 单个二进制文件，无需安装 Python 或其他运行时

## 自动音量均衡说明

启用 `--auto-track-gain` 后，程序会直接解码音频并估算每首歌的响度（不依赖 ReplayGain 标签）。

* 估算失败的曲目会回退到 `--track-gain` 指定值。
* 计算结果按相对响度映射到 `0-99`，并写入 `TrackX.volume_gain`。
* `volume_gain` 字段定义遵循 `docs/iTunesSD3gen.md`。

## 初始参考数据

仓库中的 `iPod_Control/` 目录作为 **初始数据与结构参考** 保留。

* 其用途是为开发、调试和对比数据库生成结果提供基线。
* 该目录不是一次性产物，不应默认删除或忽略。
* 当设备实际同步后导致该目录变化时，建议单独提交并在提交信息中说明变更来源。

## 提示和技巧

### 禁用 IPod 的回收站

为了避免 linux 将删除的文件移入回收站，您可以创建一个空文件 `.Trash-1000`。
这强制 linux 永久删除文件，而不是将其移动到回收站。
当然，您也可以使用 `shift + delete` 永久删除文件，而无需此技巧。
该文件可以在 [extras](extras) 文件夹中找到。

### 压缩/转换您的音乐文件

([#11](https://github.com/nims11/IPod-Shuffle-4g/issues/11)) Shuffle 的存储空间有限，您可能希望通过牺牲一些比特率来挤入更多的收藏。在极少数情况下，您可能还拥有 ipod 不支持的格式的音乐。虽然 `ffmpeg` 几乎可以满足您的所有需求，但如果您正在寻找一个友好的替代品，请尝试 [Soundconverter](http://soundconverter.org/)。

### 使用 Rhythmbox 管理您的音乐和播放列表

如[博客文章](https://nims11.wordpress.com/2013/10/12/ipod-shuffle-4g-under-linux/)中所述
您可以使用 Rythmbox 将您的个人音乐库同步到您的 IPod
但仍然利用此脚本提供的附加功能（如旁白）。

只需在您的 IPod 根目录中放置一个名为 `.is_audio_player` 的文件，并添加以下内容：

```text
name=&quot;Name's IPOD&quot;
audio_folders=iPod_Control/Music/
```

该文件可以在 [extras](extras) 文件夹中找到。

现在禁用 Rhythmbox 的 IPod 插件并启用 MTP 插件。
您现在可以使用 Rythmbox 生成播放列表并将它们同步到您的 IPod。
脚本将识别 .pls 播放列表并生成正确的 iTunesSD 文件。

#### 已知的 Rhythmbox 同步问题

* 创建名为 `K.I.Z.` 的播放列表将失败，因为 FAT 文件系统不支持目录/文件末尾有从点 `.`。
* 有时错误的 ID3 标签也会导致播放列表损坏。

在所有情况下，您都可以尝试更新 Rythmbox 到最新版本，再次同步或自行修复错误的文件名。

#### 将脚本随 IPod 携带

如果您想在不同的计算机上使用此脚本，那么
只需将脚本复制到 IPod 的根目录中即可。

#### 格式化/恢复/还原 IPod

([#41](https://github.com/nims11/IPod-Shuffle-4g/issues/41)) 如果您错误地格式化了 IPod 并丢失了所有数据，您仍然可以恢复它。
重要的是 **不要使用 MBR/GPT**。您需要直接创建 **Fat16 文件系统**:

```bash
sudo mkfs.vfat -I -F 16 -n IPOD /dev/sdX
```

运行此脚本以生成新数据库。所有丢失的声音文件应在下次使用时由 IPod 重新生成。
您的 IPod 现在应该可以工作并再次播放音乐了。

## 待办事项

* 前端

## 额外阅读

* [shuffle3db 规范](docs/iTunesSD3gen.md)
* [使用 shuffle.py 和 Rhythmbox 轻松同步播放列表和歌曲](http://nims11.wordpress.com/2013/10/12/ipod-shuffle-4g-under-linux/)
* [gtkpod](http://www.gtkpod.org/wiki/Home)
* [德国 Ubuntu IPod 教程](https://wiki.ubuntuusers.de/iPod/)
* [IPod 管理应用程序](https://wiki.archlinux.org/index.php/IPod#iPod_management_apps)

最初的 shuffle3db 网站已下线。此存储库在 `docs` 文件夹中包含信息的副本。
原始数据可以通过 [wayback machine](https://web.archive.org/web/20131016014401/http://shuffle3db.wikispaces.com/iTunesSD3gen) 找到。

## 版本历史

```text
1.6.0 Release (11.02.2026)
* 使用 Rust 完全重写，单二进制文件，零运行时依赖
* 替换 TTS 引擎为 msedge-tts Rust crate（无需 Python edge-tts）
* FLAC→MP3 (320kbps) 自动转换：使用 symphonia 解码 + LAME 编码
* 并发 FLAC 转换与响度分析（Rayon）
* 自动音量均衡：直接分析音频内容写入增益
* 播放列表解析兼容性修复（BOM 处理、编码容错）
* 路径判断与隐藏目录过滤优化，提升跨平台稳定性
* 模块化代码架构

由 Ziphyrien Fork 并重写
---

1.5 Release (09.06.2020)
* Port Script to Python3
* Mutagen support is now optional

1.4 Release (27.08.2016)
* Catch "no space left" error #30
* Renamed --voiceover to --track-voiceover
* Added optional --verbose output
* Renamed script from shuffle.py to ipod-shuffle-4g.py
* Added files to `extras` folder
* Ignore hidden filenames
* Do not force playlist voiceover with auto playlists
* Added shortcut parameters (-p, -t, -d, etc.)
* Fix UnicodeEncodeError for non-ascii playlist names (#35)

1.3 Release (08.06.2016)
* Directory based auto playlist building (--auto-dir-playlists) (#13)
* ID3 tags based auto playlist building (--auto-id3-playlists)
* Added short program description
* Fix hyphen in filename #4
* Fixed mutagen bug #5
* Voiceover disabled by default #26 (Playlist voiceover enabled with auto playlist generation)
* Differentiate track and playlist voiceover #26

1.2 Release (04.02.2016)
* Additional fixes from NicoHood
* Fixed "All Songs" and "Playlist N" sounds when voiceover is disabled #17
* Better handle broken playlist paths #16
* Skip existing voiceover files with the same name (e.g. "Track 1.mp3")
* Only use voiceover if dependencies are installed
* Added Path help entry
* Made help message lower case
* Improved Readme
* Improved docs
* Added MIT License
* Added this changelog

1.1 Release (11.10.2013 - 23.01.2016)
* Fixes from nims11 fork
* Option to disable voiceover
* Initialize the IPod Directory tree
* Using the --rename-unicode flag
  filenames with strange characters and different language are renamed
  which avoids the script to crash with a Unicode Error
* Other small fixes

1.0 Release (15.08.2012 - 17.10.2012)
* Original release by ikelos
```
