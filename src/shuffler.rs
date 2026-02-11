use crate::vprintln;
use rayon::prelude::*;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use walkdir::WalkDir;

use crate::cli::{Cli, LIST_EXT, MUSIC_EXT};
use crate::audio::estimate_track_loudness_db;
use crate::convert::convert_flac_to_mp3;
use crate::database::{build_itunes_sd, build_track_info, BuildContext};
use crate::playlist::{
    group_tracks_by_id3_template, resolve_playlist_tracks, PlaylistSource,
};
use crate::utils::{ext_lower, is_subpath};

pub fn run_shuffler(cli: &Cli) {
    let base = PathBuf::from(&cli.path);
    let base = fs::canonicalize(&base).unwrap_or(base);

    let track_voiceover = cli.track_voiceover;
    let playlist_voiceover = cli.playlist_voiceover;
    let rename = cli.rename_unicode;
    let trackgain = cli.track_gain;

    // Initialize directories
    for dirname in &["iPod_Control/Speakable/Playlists", "iPod_Control/Speakable/Tracks"] {
        let p = base.join(dirname);
        let _ = fs::remove_dir_all(&p);
    }
    for dirname in &[
        "iPod_Control/iTunes", "iPod_Control/Music",
        "iPod_Control/Speakable/Playlists", "iPod_Control/Speakable/Tracks",
    ] {
        let _ = fs::create_dir_all(base.join(dirname));
    }

    let speakable_root = base.join("iPod_Control").join("Speakable");
    let music_root = base.join("iPod_Control").join("Music");

    // Collect files
    let mut flac_files: Vec<PathBuf> = Vec::new();
    let mut other_audio_files: Vec<PathBuf> = Vec::new();
    let mut playlist_sources: Vec<PlaylistSource> = Vec::new();

    for entry in WalkDir::new(&base).sort_by_file_name().into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        if let Some(name) = path.file_name() {
            if name.to_string_lossy().starts_with('.') && path != base.as_path() {
                continue;
            }
        }
        let rel = path.strip_prefix(&base).unwrap_or(path);
        let has_hidden = rel.components().any(|c| {
            let s = c.as_os_str().to_string_lossy();
            s.starts_with('.') && s != "."
        });
        if has_hidden { continue; }
        if is_subpath(path, &speakable_root) { continue; }

        if entry.file_type().is_file() {
            let ext = ext_lower(path);
            let full = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
            if ext == ".flac" {
                flac_files.push(full);
            } else if MUSIC_EXT.contains(&ext.as_str()) {
                other_audio_files.push(full);
            } else if LIST_EXT.contains(&ext.as_str()) {
                playlist_sources.push(PlaylistSource::File(full));
            }
        }

        if let Some(max_depth) = cli.auto_dir_playlists {
            if entry.file_type().is_dir()
                && is_subpath(path, &music_root)
                && path != music_root.as_path()
            {
                let depth = path.strip_prefix(&music_root)
                    .map(|r| r.components().count() as i32)
                    .unwrap_or(0);
                if max_depth < 0 || depth <= max_depth {
                    playlist_sources.push(PlaylistSource::Directory(
                        fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
                    ));
                }
            }
        }
    }

    // FLAC conversion
    let mut tracks: Vec<PathBuf> = Vec::new();
    let mut track_set: HashSet<PathBuf> = HashSet::new();

    if !flac_files.is_empty() {
        println!("发现 {} 个 FLAC 文件，开始并发转换...", flac_files.len());
        let total = flac_files.len();
        let completed = AtomicUsize::new(0);
        let converted: Mutex<Vec<PathBuf>> = Mutex::new(Vec::new());

        flac_files.par_iter().for_each(|flac_path| {
            if let Some(mp3) = convert_flac_to_mp3(flac_path) {
                converted.lock().unwrap().push(mp3);
            }
            let done = completed.fetch_add(1, Ordering::Relaxed) + 1;
            let pct = done as f64 / total as f64 * 100.0;
            eprint!("\r正在转换: [{}/{}] {:.1}%", done, total, pct);
        });
        eprintln!();
        println!("FLAC 转换完成！");

        for mp3 in converted.into_inner().unwrap() {
            if track_set.insert(mp3.clone()) {
                tracks.push(mp3);
            }
        }
    }

    // Add other audio files
    for full in other_audio_files {
        if ext_lower(&full) == ".mp3" {
            let flac_source = full.with_extension("flac");
            if flac_source.exists() { continue; }
        }
        if track_set.insert(full.clone()) {
            tracks.push(full);
        }
    }

    tracks.sort_by(|a, b| {
        a.to_string_lossy().to_lowercase().cmp(&b.to_string_lossy().to_lowercase())
    });

    // Auto track gain
    let mut track_gain_overrides: HashMap<PathBuf, u32> = HashMap::new();
    if cli.auto_track_gain && !tracks.is_empty() {
        println!("正在分析曲目响度并计算自动增益...");
        let total = tracks.len();
        let completed = AtomicUsize::new(0);
        let loudness_map: Mutex<HashMap<PathBuf, f64>> = Mutex::new(HashMap::new());

        tracks.par_iter().for_each(|track| {
            if let Some(db) = estimate_track_loudness_db(track, 45.0) {
                loudness_map.lock().unwrap().insert(track.clone(), db);
            }
            let done = completed.fetch_add(1, Ordering::Relaxed) + 1;
            let pct = done as f64 / total as f64 * 100.0;
            eprint!("\r正在分析: [{}/{}] {:.1}%", done, total, pct);
        });
        eprintln!();

        let lmap = loudness_map.into_inner().unwrap();
        if lmap.is_empty() {
            println!("警告: 未能分析任何曲目的响度，自动音量均衡已跳过。");
        } else {
            let reference = lmap.values().cloned().fold(f64::NEG_INFINITY, f64::max);
            for (track, db) in &lmap {
                let gain = ((reference - db).round() as u32).clamp(0, 99);
                track_gain_overrides.insert(track.clone(), gain);
            }
            println!("自动音量均衡完成: 已为 {}/{} 首曲目写入增益（参考响度 {:.2} dBFS）。",
                track_gain_overrides.len(), tracks.len(), reference);
        }
    }

    // ID3 auto playlists
    if let Some(ref tmpl) = cli.auto_id3_playlists {
        let grouped = group_tracks_by_id3_template(&tracks, tmpl);
        for (name, files) in grouped {
            playlist_sources.push(PlaylistSource::Grouped(name, files));
        }
    }

    // Build track position map
    let track_positions: HashMap<PathBuf, usize> = tracks.iter()
        .enumerate()
        .map(|(i, t)| (t.clone(), i))
        .collect();

    // Build track infos
    let mut albums: Vec<String> = Vec::new();
    let mut album_index: HashMap<String, u32> = HashMap::new();
    let mut artists: Vec<String> = Vec::new();
    let mut artist_index: HashMap<String, u32> = HashMap::new();

    let mut track_infos = Vec::new();
    let mut ctx = BuildContext {
        base: &base,
        trackgain,
        track_gain_overrides: &track_gain_overrides,
        albums: &mut albums,
        album_index: &mut album_index,
        artists: &mut artists,
        artist_index: &mut artist_index,
        track_voiceover,
        playlist_voiceover,
    };
    for t in &tracks {
        vprintln!("[*] 添加曲目 {}", t.display());
        let info = build_track_info(t, &mut ctx);
        track_infos.push(info);
    }

    // Build playlists
    let master_indices: Vec<u32> = (0..tracks.len() as u32).collect();
    let mut all_playlists: Vec<(String, Vec<u32>)> = vec![
        ("__master__".to_string(), master_indices),
    ];

    for src in &playlist_sources {
        let (name, indices) = resolve_playlist_tracks(src, &base, rename, &track_positions);
        if indices.is_empty() {
            eprintln!("错误: 播放列表 \"{}\" 不包含任何曲目。跳过。", name);
        } else {
            vprintln!("[+] 添加播放列表 {}", name);
            all_playlists.push((name, indices));
        }
    }

    // Build and write database
    println!("正在写入数据库。这可能需要一段时间...");
    let db = build_itunes_sd(
        &track_infos, &all_playlists,
        track_voiceover, playlist_voiceover, &base,
    );

    let db_path = base.join("iPod_Control").join("iTunes").join("iTunesSD");
    match fs::write(&db_path, &db) {
        Ok(_) => {
            println!("数据库写入成功:");
            println!("曲目 {}", tracks.len());
            println!("专辑 {}", albums.len());
            println!("艺术家 {}", artists.len());
            println!("播放列表 {}", all_playlists.len());
        }
        Err(e) => {
            eprintln!("I/O 错误: {}", e);
            eprintln!("错误: 写入 iPod 数据库失败。");
            std::process::exit(1);
        }
    }
}
