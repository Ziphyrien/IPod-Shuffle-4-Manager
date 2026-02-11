use byteorder::{LittleEndian, WriteBytesExt};
use lofty::prelude::*;
use md5::{Digest, Md5};
use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::tts::text_to_speech_file;
use crate::utils::{ext_lower, path_to_ipod};

// ─── iTunesSD binary database construction ───────────────────────────────────

pub fn make_dbid(text: &[u8]) -> [u8; 8] {
    let mut hasher = Md5::new();
    hasher.update(text);
    let digest = hasher.finalize();
    let mut dbid = [0u8; 8];
    dbid.copy_from_slice(&digest[..8]);
    dbid
}

pub fn dbid_to_filename(dbid: &[u8; 8]) -> String {
    dbid.iter().rev().map(|b| format!("{:02x}", b)).collect()
}

pub fn do_text_to_speech(
    text: &str, dbid: &[u8; 8], is_playlist: bool,
    base: &Path, track_voiceover: bool, playlist_voiceover: bool,
) {
    let should_speak = if is_playlist { playlist_voiceover } else { track_voiceover };
    if !should_speak { return; }

    let fn_name = dbid_to_filename(dbid);
    let subdir = if is_playlist { "Playlists" } else { "Tracks" };
    let wav_path = base.join("iPod_Control").join("Speakable").join(subdir).join(format!("{}.wav", fn_name));
    text_to_speech_file(&wav_path, text);
}

pub struct TrackInfo {
    pub filename: String,       // iPod-relative path
    pub filetype: u32,          // 1=mp3, 2=aac
    pub stop_at_pos_ms: u32,
    pub volume_gain: u32,
    pub album_id: u32,
    pub artist_id: u32,
    pub track_num: u16,
    pub disc_num: u16,
    pub dbid: [u8; 8],
}

/// 构建曲目信息所需的上下文
pub struct BuildContext<'a> {
    pub base: &'a Path,
    pub trackgain: u32,
    pub track_gain_overrides: &'a HashMap<PathBuf, u32>,
    pub albums: &'a mut Vec<String>,
    pub album_index: &'a mut HashMap<String, u32>,
    pub artists: &'a mut Vec<String>,
    pub artist_index: &'a mut HashMap<String, u32>,
    pub track_voiceover: bool,
    pub playlist_voiceover: bool,
}

pub fn build_track_info(
    filepath: &Path, ctx: &mut BuildContext<'_>,
) -> TrackInfo {
    let ipod_path = path_to_ipod(filepath, ctx.base).unwrap_or_else(|_| "/unknown".into());

    let ext = ext_lower(filepath);
    let filetype = if [".m4a", ".m4b", ".m4p", ".aa"].contains(&ext.as_str()) { 2u32 } else { 1u32 };

    let mut volume_gain = ctx.trackgain;
    if let Some(&g) = ctx.track_gain_overrides.get(filepath) {
        volume_gain = g;
    }

    let stem = filepath.file_stem().unwrap_or_default().to_string_lossy().to_string();
    let mut text = stem.clone();
    let mut stop_at_pos_ms = 0u32;
    let mut album_id = 0u32;
    let mut artist_id = 0u32;
    let mut track_num = 1u16;
    let mut disc_num = 0u16;

    // Try reading tags with lofty
    if let Ok(tagged) = lofty::read_from_path(filepath) {
        if let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) {
            if let Ok(props) = u32::try_from(tagged.properties().duration().as_millis()) {
                stop_at_pos_ms = props;
            }

            let artist_name = tag.artist().map(|s| s.to_string()).unwrap_or_else(|| "Unknown".into());
            let idx = ctx.artist_index.get(&artist_name).copied().unwrap_or_else(|| {
                let idx = ctx.artists.len() as u32;
                ctx.artist_index.insert(artist_name.clone(), idx);
                ctx.artists.push(artist_name.clone());
                idx
            });
            artist_id = idx;

            let album_name = tag.album().map(|s| s.to_string()).unwrap_or_else(|| "Unknown".into());
            let idx = ctx.album_index.get(&album_name).copied().unwrap_or_else(|| {
                let idx = ctx.albums.len() as u32;
                ctx.album_index.insert(album_name.clone(), idx);
                ctx.albums.push(album_name.clone());
                idx
            });
            album_id = idx;

            if let Some(t) = tag.track() { track_num = t as u16; }
            if let Some(d) = tag.disk() { disc_num = d as u16; }

            let title = tag.title().map(|s| s.to_string()).unwrap_or_default();
            let artist_str = tag.artist().map(|s| s.to_string()).unwrap_or_default();
            if !title.is_empty() && !artist_str.is_empty() {
                text = format!("{} - {}", title, artist_str);
            }
        }
    }

    let text_bytes = text.as_bytes();
    let dbid = make_dbid(text_bytes);
    do_text_to_speech(&text, &dbid, false, ctx.base, ctx.track_voiceover, ctx.playlist_voiceover);

    TrackInfo {
        filename: ipod_path,
        filetype,
        stop_at_pos_ms,
        volume_gain,
        album_id,
        artist_id,
        track_num,
        disc_num,
        dbid,
    }
}

pub fn write_track_record(track: &TrackInfo) -> Vec<u8> {
    let mut buf = Vec::with_capacity(0x174);
    buf.write_all(b"rths").unwrap();                          // header_id
    buf.write_u32::<LittleEndian>(0x174).unwrap();            // header_length
    buf.write_u32::<LittleEndian>(0).unwrap();                // start_at_pos_ms
    buf.write_u32::<LittleEndian>(track.stop_at_pos_ms).unwrap(); // stop_at_pos_ms
    buf.write_u32::<LittleEndian>(track.volume_gain).unwrap(); // volume_gain
    buf.write_u32::<LittleEndian>(track.filetype).unwrap();   // filetype

    // filename: 256 bytes, utf-8, zero-padded
    let fname_bytes = track.filename.as_bytes();
    let mut fname_buf = [0u8; 256];
    let copy_len = fname_bytes.len().min(256);
    fname_buf[..copy_len].copy_from_slice(&fname_bytes[..copy_len]);
    buf.write_all(&fname_buf).unwrap();

    buf.write_u32::<LittleEndian>(0).unwrap();                // bookmark
    buf.write_u8(1).unwrap();                                 // dontskip
    buf.write_u8(0).unwrap();                                 // remember
    buf.write_u8(0).unwrap();                                 // unintalbum
    buf.write_u8(0).unwrap();                                 // unknown
    buf.write_u32::<LittleEndian>(0x200).unwrap();            // pregap
    buf.write_u32::<LittleEndian>(0x200).unwrap();            // postgap
    buf.write_u32::<LittleEndian>(0).unwrap();                // numsamples
    buf.write_u32::<LittleEndian>(0).unwrap();                // unknown2
    buf.write_u32::<LittleEndian>(0).unwrap();                // gapless
    buf.write_u32::<LittleEndian>(0).unwrap();                // unknown3
    buf.write_u32::<LittleEndian>(track.album_id).unwrap();   // albumid
    buf.write_u16::<LittleEndian>(track.track_num).unwrap();  // track
    buf.write_u16::<LittleEndian>(track.disc_num).unwrap();   // disc
    buf.write_u64::<LittleEndian>(0).unwrap();                // unknown4
    buf.write_all(&track.dbid).unwrap();                      // dbid (8 bytes)
    buf.write_u32::<LittleEndian>(track.artist_id).unwrap();  // artistid
    buf.write_all(&[0u8; 32]).unwrap();                       // unknown5

    buf
}

pub fn build_track_header(tracks: &[TrackInfo], base_offset: u32) -> Vec<u8> {
    let num_tracks = tracks.len() as u32;
    let header_len = 20 + (num_tracks * 4);

    // Build individual track records first
    let mut track_chunks: Vec<Vec<u8>> = Vec::new();
    for t in tracks {
        track_chunks.push(write_track_record(t));
    }

    // Header
    let mut buf = Vec::new();
    buf.write_all(b"hths").unwrap();                          // header_id
    buf.write_u32::<LittleEndian>(header_len).unwrap();       // total_length
    buf.write_u32::<LittleEndian>(num_tracks).unwrap();       // number_of_tracks
    buf.write_u64::<LittleEndian>(0).unwrap();                // unknown1

    // Offsets
    let mut chunk_offset = 0u32;
    for tc in &track_chunks {
        buf.write_u32::<LittleEndian>(base_offset + header_len + chunk_offset).unwrap();
        chunk_offset += tc.len() as u32;
    }

    // Track data
    for tc in &track_chunks {
        buf.write_all(tc).unwrap();
    }

    buf
}

pub fn write_playlist_record(
    dbid: &[u8; 8], listtype: u32, track_indices: &[u32],
) -> Vec<u8> {
    let num_songs = track_indices.len() as u32;
    let total_length = 44 + (4 * num_songs);

    let mut buf = Vec::new();
    buf.write_all(b"lphs").unwrap();                          // header_id  (shpl)
    buf.write_u32::<LittleEndian>(total_length).unwrap();     // total_length
    buf.write_u32::<LittleEndian>(num_songs).unwrap();        // number_of_songs
    buf.write_u32::<LittleEndian>(num_songs).unwrap();        // number_of_nonaudio
    buf.write_all(dbid).unwrap();                             // dbid (8 bytes)
    buf.write_u32::<LittleEndian>(listtype).unwrap();         // listtype
    buf.write_all(&[0u8; 16]).unwrap();                       // unknown1

    for &idx in track_indices {
        buf.write_u32::<LittleEndian>(idx).unwrap();
    }

    buf
}

pub fn build_playlist_header(
    playlists: &[(String, Vec<u32>)],
    base_offset: u32,
    base: &Path,
    track_voiceover: bool,
    playlist_voiceover: bool,
) -> Vec<u8> {
    // Build playlist chunks
    let mut chunks: Vec<Vec<u8>> = Vec::new();

    for (name, indices) in playlists {
        let dbid = if name == "__master__" && !playlist_voiceover {
            [0u8; 8]
        } else {
            let text = if name == "__master__" { "masterlist" } else { name.as_str() };
            let d = make_dbid(text.as_bytes());
            let speech_text = if name == "__master__" { "All songs" } else { name.as_str() };
            do_text_to_speech(speech_text, &d, true, base, track_voiceover, playlist_voiceover);
            d
        };

        let listtype = if name == "__master__" { 1u32 } else { 2u32 };
        chunks.push(write_playlist_record(&dbid, listtype, indices));
    }

    let num_playlists = chunks.len() as u32;
    let header_fixed = 0x14u32; // 20 bytes fixed header
    let total_length = header_fixed + (num_playlists * 4);

    let mut buf = Vec::new();
    buf.write_all(b"hphs").unwrap();                                  // header_id (shph)
    buf.write_u32::<LittleEndian>(total_length).unwrap();             // total_length
    buf.write_u32::<LittleEndian>(num_playlists).unwrap();            // number_of_playlists
    buf.write_all(&[0xFF, 0xFF]).unwrap();                            // non_podcast
    buf.write_all(&[0x01, 0x00]).unwrap();                            // master
    buf.write_all(&[0xFF, 0xFF]).unwrap();                            // non_audiobook
    buf.write_all(&[0x00, 0x00]).unwrap();                            // unknown2

    // Offsets for each playlist
    let mut offset = base_offset + total_length;
    for chunk in &chunks {
        buf.write_u32::<LittleEndian>(offset).unwrap();
        offset += chunk.len() as u32;
    }

    // Playlist data
    for chunk in &chunks {
        buf.write_all(chunk).unwrap();
    }

    buf
}

pub fn build_itunes_sd(
    track_infos: &[TrackInfo],
    playlists: &[(String, Vec<u32>)],
    track_voiceover: bool,
    playlist_voiceover: bool,
    base: &Path,
) -> Vec<u8> {
    let db_header_len = 64u32;

    // Build track header
    let track_header = build_track_header(track_infos, db_header_len);
    let playlist_header_offset = db_header_len + track_header.len() as u32;

    // Build playlist header
    let playlist_header = build_playlist_header(
        playlists, playlist_header_offset, base, track_voiceover, playlist_voiceover,
    );

    let num_tracks = track_infos.len() as u32;
    let num_playlists = playlists.len() as u32;

    // Database header (bdhs / shdb)
    let mut buf = Vec::new();
    buf.write_all(b"bdhs").unwrap();                                  // header_id
    buf.write_u32::<LittleEndian>(0x02000003).unwrap();               // unknown1
    buf.write_u32::<LittleEndian>(64).unwrap();                       // total_length
    buf.write_u32::<LittleEndian>(num_tracks).unwrap();               // total_tracks
    buf.write_u32::<LittleEndian>(num_playlists).unwrap();            // total_playlists
    buf.write_u64::<LittleEndian>(0).unwrap();                        // unknown2
    buf.write_u8(0).unwrap();                                         // max_volume
    buf.write_u8(if track_voiceover { 1 } else { 0 }).unwrap();      // voiceover_enabled
    buf.write_u16::<LittleEndian>(0).unwrap();                        // unknown3
    buf.write_u32::<LittleEndian>(num_tracks).unwrap();               // tracks_without_podcasts
    buf.write_u32::<LittleEndian>(64).unwrap();                       // track_header_offset
    buf.write_u32::<LittleEndian>(playlist_header_offset).unwrap();   // playlist_header_offset
    buf.write_all(&[0u8; 20]).unwrap();                               // unknown4

    buf.extend_from_slice(&track_header);
    buf.extend_from_slice(&playlist_header);
    buf
}
