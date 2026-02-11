use lofty::prelude::*;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

use crate::cli::MUSIC_EXT;
use crate::utils::{ext_lower, validate_unicode};

#[derive(Clone)]
pub enum PlaylistSource {
    File(PathBuf),
    Directory(PathBuf),
    Grouped(String, Vec<PathBuf>),
}

pub fn populate_directory_playlist(dir: &Path) -> Vec<PathBuf> {
    let mut tracks = Vec::new();
    for entry in WalkDir::new(dir).sort_by_file_name().into_iter().filter_map(|e| e.ok()) {
        if entry.file_type().is_file() {
            let p = entry.path();
            if p.file_name().map(|f| f.to_string_lossy().starts_with('.')).unwrap_or(false) {
                continue;
            }
            let rel = p.strip_prefix(dir).unwrap_or(p);
            let has_hidden = rel.components().any(|c| {
                c.as_os_str().to_string_lossy().starts_with('.')
            });
            if has_hidden { continue; }
            if MUSIC_EXT.contains(&ext_lower(p).as_str()) {
                tracks.push(fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf()));
            }
        }
    }
    tracks
}

pub fn parse_m3u(data: &str, rename: bool) -> Vec<String> {
    data.lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .map(|l| {
            let path = l.trim().to_string();
            if rename { validate_unicode(&path) } else { path }
        })
        .collect()
}

pub fn parse_pls(data: &str, rename: bool) -> Vec<String> {
    let mut sort_tracks: Vec<(i32, String)> = Vec::new();
    for line in data.lines() {
        let parts: Vec<&str> = line.trim().splitn(2, '=').collect();
        if parts.len() == 2 && parts[0].to_lowercase().starts_with("file") {
            if let Ok(num) = parts[0][4..].parse::<i32>() {
                let mut filename = percent_encoding::percent_decode_str(parts[1].trim())
                    .decode_utf8_lossy()
                    .to_string();
                if filename.to_lowercase().starts_with("file://") {
                    filename = filename[7..].to_string();
                }
                if rename {
                    filename = validate_unicode(&filename);
                }
                sort_tracks.push((num, filename));
            }
        }
    }
    sort_tracks.sort_by_key(|(n, _)| *n);
    sort_tracks.into_iter().map(|(_, f)| f).collect()
}

pub fn resolve_playlist_tracks(
    source: &PlaylistSource, base: &Path, rename: bool,
    track_positions: &HashMap<PathBuf, usize>,
) -> (String, Vec<u32>) {
    match source {
        PlaylistSource::Directory(dir) => {
            let name = dir.file_stem().unwrap_or_default().to_string_lossy().to_string();
            let files = populate_directory_playlist(dir);
            let indices: Vec<u32> = files.iter()
                .filter_map(|f| track_positions.get(f).map(|&i| i as u32))
                .collect();
            (name, indices)
        }
        PlaylistSource::File(filepath) => {
            let name = filepath.file_stem().unwrap_or_default().to_string_lossy().to_string();
            let raw = fs::read_to_string(filepath).unwrap_or_default();
            let data = raw.strip_prefix('\u{feff}').unwrap_or(&raw);
            let ext = ext_lower(filepath);
            let raw_paths = if ext == ".pls" {
                parse_pls(data, rename)
            } else {
                parse_m3u(data, rename)
            };
            let playlist_dir = filepath.parent().unwrap_or(base);
            let indices: Vec<u32> = raw_paths.iter().filter_map(|rel| {
                let p = if Path::new(rel).exists() {
                    PathBuf::from(rel)
                } else {
                    playlist_dir.join(rel)
                };
                let canon = fs::canonicalize(&p).unwrap_or(p);
                match track_positions.get(&canon) {
                    Some(&i) => Some(i as u32),
                    None => {
                        eprintln!("错误: 无法找到曲目 \"{}\"。跳过。", canon.display());
                        None
                    }
                }
            }).collect();
            (name, indices)
        }
        PlaylistSource::Grouped(name, files) => {
            let indices: Vec<u32> = files.iter()
                .filter_map(|f| track_positions.get(f).map(|&i| i as u32))
                .collect();
            (name.clone(), indices)
        }
    }
}

pub fn group_tracks_by_id3_template(tracks: &[PathBuf], template: &str) -> Vec<(String, Vec<PathBuf>)> {
    let re = regex::Regex::new(r"\{.*?\}").unwrap();
    let template_vars: Vec<String> = re.find_iter(template).map(|m| m.as_str().to_string()).collect();
    let mut grouped: HashMap<String, Vec<PathBuf>> = HashMap::new();
    for track in tracks {
        let tag_map: HashMap<String, String> = if let Ok(tagged) = lofty::read_from_path(track) {
            if let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) {
                let mut m = HashMap::new();
                if let Some(v) = tag.title() { m.insert("title".into(), v.to_string()); }
                if let Some(v) = tag.artist() { m.insert("artist".into(), v.to_string()); }
                if let Some(v) = tag.album() { m.insert("album".into(), v.to_string()); }
                if let Some(v) = tag.genre() { m.insert("genre".into(), v.to_string()); }
                m
            } else { HashMap::new() }
        } else { HashMap::new() };
        let mut key = template.to_string();
        let mut any_present = false;
        for var in &template_vars {
            let field = &var[1..var.len()-1];
            let val = tag_map.get(field).cloned().unwrap_or_default();
            if !val.is_empty() { any_present = true; }
            key = key.replace(var.as_str(), &val);
        }
        if any_present {
            grouped.entry(key).or_default().push(track.clone());
        }
    }
    let mut result: Vec<(String, Vec<PathBuf>)> = grouped.into_iter().collect();
    result.sort_by(|a, b| a.0.cmp(&b.0));
    result
}
