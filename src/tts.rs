use crate::vprintln;
use std::io;
use std::path::Path;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

// ─── Text-to-Speech (Edge TTS via msedge-tts crate) ─────────────────────────

const TTS_VOICE: &str = "zh-CN-XiaoxiaoNeural";

/// 为给定文本生成语音 WAV 文件（如果文件已存在则跳过）
pub fn text_to_speech_file(out_wav_path: &Path, text: &str) -> bool {
    if out_wav_path.exists() {
        vprintln!("使用现有的 {}", out_wav_path.display());
        return true;
    }

    let text = if text.is_empty() { "unknown" } else { text };

    match generate_tts_wav(out_wav_path, text) {
        Ok(_) => true,
        Err(e) => {
            eprintln!("语音生成失败: {}", e);
            false
        }
    }
}

fn generate_tts_wav(out_wav_path: &Path, text: &str) -> Result<(), Box<dyn std::error::Error>> {
    use msedge_tts::tts::client::connect;
    use msedge_tts::tts::SpeechConfig;

    let config = SpeechConfig::from(&msedge_tts::voice::Voice {
        name: TTS_VOICE.to_string(),
        short_name: Some(TTS_VOICE.to_string()),
        gender: Some(String::new()),
        locale: Some("zh-CN".to_string()),
        suggested_codec: Some("audio-24khz-48kbitrate-mono-mp3".to_string()),
        friendly_name: Some(String::new()),
        status: Some(String::new()),
        voice_tag: None,
    });

    let mut tts = connect()?;
    let audio = tts.synthesize(text, &config)?;
    let mp3_bytes = audio.audio_bytes;

    // Decode MP3 bytes to WAV using symphonia + hound
    let cursor = io::Cursor::new(mp3_bytes);
    let mss = MediaSourceStream::new(Box::new(cursor), Default::default());
    let mut hint = Hint::new();
    hint.with_extension("mp3");

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())?;

    let mut format = probed.format;
    let track = format.default_track().ok_or("no audio track")?.clone();
    let codec_params = track.codec_params.clone();
    let sample_rate = codec_params.sample_rate.unwrap_or(24000);
    let channels = codec_params.channels.map(|c| c.count()).unwrap_or(1) as u16;

    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())?;

    let spec = hound::WavSpec {
        channels,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = hound::WavWriter::create(out_wav_path, spec)?;

    while let Ok(packet) = format.next_packet() {
        if packet.track_id() != track.id { continue; }

        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(_) => continue,
        };

        let dspec = *decoded.spec();
        let num_frames = decoded.frames();
        let mut sample_buf = SampleBuffer::<f32>::new(num_frames as u64, dspec);
        sample_buf.copy_interleaved_ref(decoded);

        for &s in sample_buf.samples() {
            let val = (s * 32767.0).clamp(-32768.0, 32767.0) as i16;
            writer.write_sample(val)?;
        }
    }

    writer.finalize()?;
    Ok(())
}
