use crate::vprintln;
use lofty::prelude::*;
use std::fs;
use std::io;
use std::mem::MaybeUninit;
use std::path::{Path, PathBuf};
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// 从 MaybeUninit 缓冲区的前 `len` 个元素中安全地收集已初始化字节
///
/// # Safety
/// 调用者必须保证 `buf[..len]` 中的元素已经被正确初始化
fn collect_initialized_bytes(buf: &[MaybeUninit<u8>], len: usize) -> Vec<u8> {
    buf[..len]
        .iter()
        .map(|item| unsafe { item.assume_init() })
        .collect()
}

/// 将 FLAC 文件转换为 MP3，成功后返回 MP3 路径，并删除源 FLAC 文件
pub fn convert_flac_to_mp3(flac_path: &Path) -> Option<PathBuf> {
    let mp3_path = flac_path.with_extension("mp3");

    if mp3_path.exists() {
        if flac_path.exists() {
            vprintln!("MP3 已存在，删除源文件: {}", flac_path.file_name().unwrap_or_default().to_string_lossy());
            let _ = fs::remove_file(flac_path);
        }
        return Some(mp3_path);
    }

    vprintln!("转换 FLAC -> MP3: {}", flac_path.file_name().unwrap_or_default().to_string_lossy());

    let file = match fs::File::open(flac_path) {
        Ok(f) => f,
        Err(e) => { eprintln!("转换失败: 无法打开文件: {}", e); return None; }
    };
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    hint.with_extension("flac");

    let probed = match symphonia::default::get_probe().format(
        &hint, mss, &FormatOptions::default(), &MetadataOptions::default(),
    ) {
        Ok(p) => p,
        Err(e) => { eprintln!("转换失败: 无法探测格式: {}", e); return None; }
    };

    let mut format = probed.format;
    let track = match format.default_track() {
        Some(t) => t.clone(),
        None => { eprintln!("转换失败: 无音频轨道"); return None; }
    };

    let codec_params = track.codec_params.clone();
    let sample_rate = codec_params.sample_rate.unwrap_or(44100);
    let channels = codec_params.channels.map(|c| c.count()).unwrap_or(2);

    let mut decoder = match symphonia::default::get_codecs().make(&codec_params, &DecoderOptions::default()) {
        Ok(d) => d,
        Err(e) => { eprintln!("转换失败: 无法创建解码器: {}", e); return None; }
    };

    // 使用源文件实际采样率，LAME 不会自动重采样
    let mut lame = mp3lame_encoder::Builder::new().expect("lame builder");
    lame.set_sample_rate(sample_rate).expect("set sample rate");
    lame.set_num_channels(if channels >= 2 { 2 } else { 1 }).expect("set channels");
    lame.set_brate(mp3lame_encoder::Bitrate::Kbps320).expect("set bitrate");
    lame.set_quality(mp3lame_encoder::Quality::Best).expect("set quality");
    let mut encoder = lame.build().expect("build lame encoder");

    let mut mp3_data: Vec<u8> = Vec::new();

    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(symphonia::core::errors::Error::IoError(ref e))
                if e.kind() == io::ErrorKind::UnexpectedEof => break,
            Err(_) => break,
        };
        if packet.track_id() != track.id { continue; }

        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(_) => continue,
        };

        let spec = *decoded.spec();
        let num_frames = decoded.frames();
        let mut sample_buf = SampleBuffer::<f32>::new(num_frames as u64, spec);
        sample_buf.copy_interleaved_ref(decoded);
        let samples = sample_buf.samples();

        let actual_ch = spec.channels.count().min(2);
        if actual_ch >= 2 {
            let frame_count = samples.len() / actual_ch;
            let mut left = Vec::with_capacity(frame_count);
            let mut right = Vec::with_capacity(frame_count);
            for i in 0..frame_count {
                left.push(samples[i * actual_ch]);
                right.push(samples[i * actual_ch + 1]);
            }
            let input = mp3lame_encoder::DualPcm { left: &left, right: &right };
            let mut buf = vec![MaybeUninit::uninit(); mp3lame_encoder::max_required_buffer_size(frame_count)];
            let written = encoder.encode(input, &mut buf).unwrap_or(0);
            mp3_data.extend_from_slice(&collect_initialized_bytes(&buf, written));
        } else {
            let input = mp3lame_encoder::MonoPcm(samples);
            let mut buf = vec![MaybeUninit::uninit(); mp3lame_encoder::max_required_buffer_size(samples.len())];
            let written = encoder.encode(input, &mut buf).unwrap_or(0);
            mp3_data.extend_from_slice(&collect_initialized_bytes(&buf, written));
        }
    }

    // Flush LAME
    let mut flush_buf = vec![MaybeUninit::uninit(); 7200];
    let flushed = encoder.flush::<mp3lame_encoder::FlushNoGap>(&mut flush_buf).unwrap_or(0);
    mp3_data.extend_from_slice(&collect_initialized_bytes(&flush_buf, flushed));

    if let Err(e) = fs::write(&mp3_path, &mp3_data) {
        eprintln!("转换失败: 写入 MP3 失败: {}", e);
        let _ = fs::remove_file(&mp3_path);
        return None;
    }

    // Copy tags using lofty
    copy_tags(flac_path, &mp3_path);

    // Delete source FLAC
    if flac_path.exists() {
        vprintln!("删除源文件: {}", flac_path.display());
        if let Err(e) = fs::remove_file(flac_path) {
            eprintln!("删除源文件失败: {}", e);
        }
    }

    Some(mp3_path)
}

/// 将源文件的 ID3 标签复制到目标文件
pub fn copy_tags(src: &Path, dest: &Path) {
    let src_tagged = match lofty::read_from_path(src) {
        Ok(t) => t,
        Err(_) => return,
    };
    let src_tag = match src_tagged.primary_tag().or_else(|| src_tagged.first_tag()) {
        Some(t) => t,
        None => return,
    };

    let mut dest_tagged = match lofty::read_from_path(dest) {
        Ok(t) => t,
        Err(_) => return,
    };

    let dest_tag = if dest_tagged.primary_tag().is_some() {
        dest_tagged.primary_tag_mut().unwrap()
    } else {
        dest_tagged.insert_tag(lofty::tag::Tag::new(lofty::tag::TagType::Id3v2));
        dest_tagged.primary_tag_mut().unwrap()
    };

    if let Some(v) = src_tag.title() { dest_tag.set_title(v.to_string()); }
    if let Some(v) = src_tag.artist() { dest_tag.set_artist(v.to_string()); }
    if let Some(v) = src_tag.album() { dest_tag.set_album(v.to_string()); }
    if let Some(v) = src_tag.genre() { dest_tag.set_genre(v.to_string()); }
    if let Some(v) = src_tag.track() { dest_tag.set_track(v); }
    if let Some(v) = src_tag.disk() { dest_tag.set_disk(v); }

    let _ = dest_tagged.save_to_path(dest, lofty::config::WriteOptions::default());
    vprintln!("已复制标签");
}
