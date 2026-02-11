use std::fs;
use std::path::Path;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

// ─── Loudness estimation ─────────────────────────────────────────────────────

/// 估算音轨的 RMS 响度（dBFS），最多分析 `max_seconds` 秒
pub fn estimate_track_loudness_db(path: &Path, max_seconds: f64) -> Option<f64> {
    let file = fs::File::open(path).ok()?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension() {
        hint.with_extension(&ext.to_string_lossy());
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .ok()?;

    let mut format = probed.format;
    let track = format.default_track()?.clone();
    let codec_params = track.codec_params.clone();
    let sample_rate = codec_params.sample_rate.unwrap_or(44100) as f64;
    let max_samples = (max_seconds * sample_rate * 2.0) as usize;

    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .ok()?;

    let mut sum_squares: f64 = 0.0;
    let mut sample_count: usize = 0;

    while let Ok(packet) = format.next_packet() {
        if packet.track_id() != track.id { continue; }

        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(_) => continue,
        };

        let spec = *decoded.spec();
        let num_frames = decoded.frames();
        let mut sample_buf = SampleBuffer::<f32>::new(num_frames as u64, spec);
        sample_buf.copy_interleaved_ref(decoded);

        for &s in sample_buf.samples() {
            let v = s as f64;
            sum_squares += v * v;
            sample_count += 1;
        }

        if sample_count >= max_samples { break; }
    }

    if sample_count == 0 { return None; }

    let rms = (sum_squares / sample_count as f64).sqrt();
    if rms <= 1e-12 {
        return Some(-120.0);
    }
    Some(20.0 * rms.log10())
}
