//! Cross-platform pure-Rust audio slice extraction (`symphonia`) + OpenAI-compatible ASR
//! (`Whisper` / `Groq` / `SiliconFlow SenseVoice` / local `faster-whisper-server`) helpers.
//!
//! Enables real-time lookahead speech-to-subtitle generation for videos without subtitle tracks
//! on all 5 platforms (iOS, Android, macOS, Windows, Linux) without requiring bundled ffmpeg.

use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;

use serde_json::Value;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::{FormatOptions, SeekMode, SeekTo};
use symphonia::core::io::{MediaSource, MediaSourceStream};
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::units::Time;

use crate::subtitle::SubtitleCue;

const TARGET_SAMPLE_RATE: u32 = 16_000;
const HTTP_WINDOW_BYTES: u64 = 512 * 1024;

#[derive(Debug, Clone)]
pub enum AudioSliceSource {
    LocalFile(PathBuf),
    HttpUrl {
        url: String,
        headers: reqwest::header::HeaderMap,
    },
}

/// Seekable HTTP Range `MediaSource` backed by our existing async `reqwest::Client`
/// (talking straight to local `StreamProxy` or upstream media URL).
struct HttpRangeMediaSource {
    handle: tokio::runtime::Handle,
    client: reqwest::Client,
    url: String,
    headers: reqwest::header::HeaderMap,
    len: Option<u64>,
    pos: u64,
    buf_start: u64,
    buf: bytes::Bytes,
}

impl HttpRangeMediaSource {
    fn open(
        handle: tokio::runtime::Handle,
        client: reqwest::Client,
        url: String,
        headers: reqwest::header::HeaderMap,
    ) -> Result<Self, String> {
        let mut src = Self {
            handle,
            client,
            url,
            headers,
            len: None,
            pos: 0,
            buf_start: 0,
            buf: bytes::Bytes::new(),
        };
        // Fetch initial header window & discover total size from Content-Range
        src.fill_window(0)
            .map_err(|e| format!("failed to open media stream for ASR: {e}"))?;
        Ok(src)
    }

    fn fill_window(&mut self, offset: u64) -> std::io::Result<()> {
        if let Some(total) = self.len {
            if offset >= total {
                self.buf_start = offset;
                self.buf = bytes::Bytes::new();
                return Ok(());
            }
        }
        let end = match self.len {
            Some(total) => {
                (offset.saturating_add(HTTP_WINDOW_BYTES - 1)).min(total.saturating_sub(1))
            }
            None => offset.saturating_add(HTTP_WINDOW_BYTES - 1),
        };
        let range_header = format!("bytes={offset}-{end}");
        let client = self.client.clone();
        let url = self.url.clone();
        let mut hdrs = self.headers.clone();
        hdrs.insert(
            reqwest::header::RANGE,
            reqwest::header::HeaderValue::from_str(&range_header).map_err(std::io::Error::other)?,
        );

        let (data_bytes, total_len) = self.handle.block_on(async move {
            use futures_util::StreamExt;
            let resp = client
                .get(&url)
                .headers(hdrs)
                .send()
                .await
                .map_err(std::io::Error::other)?;
            let status = resp.status();
            if status == reqwest::StatusCode::RANGE_NOT_SATISFIABLE {
                return Ok::<(bytes::Bytes, Option<u64>), std::io::Error>((
                    bytes::Bytes::new(),
                    None,
                ));
            }
            if !status.is_success() && status != reqwest::StatusCode::PARTIAL_CONTENT {
                return Err(std::io::Error::other(format!(
                    "HTTP {} reading audio range",
                    status.as_u16()
                )));
            }
            if offset > 0 && status == reqwest::StatusCode::OK {
                return Err(std::io::Error::other(
                    "upstream ignored Range header on audio seek",
                ));
            }
            let total = resp
                .headers()
                .get(reqwest::header::CONTENT_RANGE)
                .and_then(|v| v.to_str().ok())
                .and_then(|cr| cr.rsplit_once('/'))
                .and_then(|(_, t)| t.trim().parse::<u64>().ok())
                .or_else(|| {
                    if status == reqwest::StatusCode::OK {
                        resp.content_length()
                    } else {
                        None
                    }
                });
            // Bound read strictly to HTTP_WINDOW_BYTES so a server ignoring Range (returning 200 OK
            // on a multi-GB movie) NEVER causes OOM!
            let max_read = (HTTP_WINDOW_BYTES as usize).min(1024 * 1024);
            let mut out = Vec::with_capacity(max_read.min(256 * 1024));
            let mut stream = resp.bytes_stream();
            while let Some(chunk_res) = stream.next().await {
                let chunk = chunk_res.map_err(std::io::Error::other)?;
                let remaining = max_read.saturating_sub(out.len());
                if remaining == 0 {
                    break;
                }
                out.extend_from_slice(&chunk[..chunk.len().min(remaining)]);
                if out.len() >= max_read {
                    break;
                }
            }
            Ok((bytes::Bytes::from(out), total))
        })?;

        if let Some(t) = total_len {
            self.len = Some(t);
        }
        self.buf_start = offset;
        self.buf = data_bytes;
        Ok(())
    }
}

impl Read for HttpRangeMediaSource {
    fn read(&mut self, out: &mut [u8]) -> std::io::Result<usize> {
        if out.is_empty() {
            return Ok(0);
        }
        let buf_end = self.buf_start.saturating_add(self.buf.len() as u64);
        if self.pos < self.buf_start || self.pos >= buf_end {
            self.fill_window(self.pos)?;
        }
        let available = self.buf_start.saturating_add(self.buf.len() as u64);
        if self.pos >= available {
            return Ok(0);
        }
        let local_off = (self.pos - self.buf_start) as usize;
        let to_copy = out.len().min(self.buf.len() - local_off);
        out[..to_copy].copy_from_slice(&self.buf[local_off..local_off + to_copy]);
        self.pos += to_copy as u64;
        Ok(to_copy)
    }
}

impl Seek for HttpRangeMediaSource {
    fn seek(&mut self, style: SeekFrom) -> std::io::Result<u64> {
        let next: i128 = match style {
            SeekFrom::Start(p) => p as i128,
            SeekFrom::Current(d) => self.pos as i128 + d as i128,
            SeekFrom::End(d) => {
                let total = self.len.ok_or_else(|| {
                    std::io::Error::new(std::io::ErrorKind::Unsupported, "unknown stream length")
                })?;
                total as i128 + d as i128
            }
        };
        if next < 0 || next > u64::MAX as i128 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "invalid seek offset",
            ));
        }
        self.pos = next as u64;
        Ok(self.pos)
    }
}

impl MediaSource for HttpRangeMediaSource {
    fn is_seekable(&self) -> bool {
        self.len.is_some()
    }

    fn byte_len(&self) -> Option<u64> {
        self.len
    }
}

/// Extract a `[start_secs, start_secs + duration_secs]` audio slice and encode it as
/// 16 kHz Mono 16-bit PCM WAV bytes suitable for Whisper / SenseVoice `/audio/transcriptions`.
pub fn extract_audio_slice_wav(
    source: &AudioSliceSource,
    start_secs: f64,
    duration_secs: f64,
    handle: tokio::runtime::Handle,
    http_client: reqwest::Client,
) -> Result<Vec<u8>, String> {
    let start = start_secs.max(0.0);
    let duration = duration_secs.clamp(4.0, 45.0);

    match extract_via_symphonia(source, start, duration, handle, http_client) {
        Ok(wav) if wav.len() > 44 => Ok(wav),
        Err(sym_err) => {
            #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
            if let Ok(wav) = extract_via_ffmpeg_fallback(source, start, duration) {
                if wav.len() > 44 {
                    return Ok(wav);
                }
            }
            Err(sym_err)
        }
        Ok(_) => Err("音频片段为空（可能已到片尾）".to_string()),
    }
}

fn extract_via_symphonia(
    source: &AudioSliceSource,
    start_secs: f64,
    duration_secs: f64,
    handle: tokio::runtime::Handle,
    http_client: reqwest::Client,
) -> Result<Vec<u8>, String> {
    let mut hint = Hint::new();
    let media_source: Box<dyn MediaSource> = match source {
        AudioSliceSource::LocalFile(path) => {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                hint.with_extension(ext);
            }
            let f = std::fs::File::open(path).map_err(|e| format!("无法打开本地视频文件: {e}"))?;
            Box::new(f)
        }
        AudioSliceSource::HttpUrl { url, headers } => {
            if let Some(ext) = url
                .split('?')
                .next()
                .and_then(|p| p.rsplit('.').next())
                .filter(|e| e.len() <= 5)
            {
                hint.with_extension(ext);
            }
            Box::new(HttpRangeMediaSource::open(
                handle,
                http_client,
                url.clone(),
                headers.clone(),
            )?)
        }
    };

    let mss = MediaSourceStream::new(media_source, Default::default());
    let probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map_err(|e| format!("无法解析媒体音轨容器: {e}"))?;

    let mut format = probed.format;
    // Select the first DECODABLE audio track (explicitly skipping video/subtitle tracks & unsupported codecs like AC-3/DTS).
    let codecs = symphonia::default::get_codecs();
    let mut chosen: Option<(
        u32,
        symphonia::core::codecs::CodecParameters,
        Box<dyn symphonia::core::codecs::Decoder>,
    )> = None;
    for t in format.tracks() {
        let cp = &t.codec_params;
        if cp.codec == symphonia::core::codecs::CODEC_TYPE_NULL {
            continue;
        }
        if cp.sample_rate.is_none() && cp.channels.is_none() {
            continue;
        }
        if let Ok(dec) = codecs.make(cp, &DecoderOptions::default()) {
            chosen = Some((t.id, cp.clone(), dec));
            break;
        }
    }
    let (track_id, codec_params, mut decoder) = chosen.ok_or_else(|| {
        "当前视频音轨编码暂不支持纯本地内置解码（如 AC-3/DTS/Opus，需 ffmpeg 或使用 AAC/MP3/FLAC/Vorbis 音轨）".to_string()
    })?;
    let time_base = codec_params.time_base;

    if start_secs >= 0.5 {
        let seek_time = Time::from(start_secs);
        if let Err(seek_err) = format.seek(
            SeekMode::Coarse,
            SeekTo::Time {
                time: seek_time,
                track_id: Some(track_id),
            },
        ) {
            if start_secs >= 2.0 {
                return Err(format!("音频流定位失败，无法快速切片: {seek_err}"));
            }
        }
        decoder.reset();
    }

    let end_secs = start_secs + duration_secs;
    let mut mono_16k: Vec<f32> =
        Vec::with_capacity((duration_secs * TARGET_SAMPLE_RATE as f64) as usize);
    let mut sample_buf: Option<SampleBuffer<f32>> = None;
    let mut mono_scratch: Vec<f32> = Vec::with_capacity(4096);
    let mut decoded_packets: usize = 0;
    let mut total_packets: usize = 0;
    let mut consecutive_errors: usize = 0;

    loop {
        total_packets += 1;
        if total_packets > 50_000 {
            break;
        }
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(SymphoniaError::IoError(ref e))
                if e.kind() == std::io::ErrorKind::UnexpectedEof =>
            {
                break;
            }
            Err(SymphoniaError::ResetRequired) => {
                consecutive_errors += 1;
                if consecutive_errors > 64 {
                    break;
                }
                decoder.reset();
                continue;
            }
            Err(_) => break,
        };

        if packet.track_id() != track_id {
            continue;
        }

        let pkt_secs = time_base.map(|tb| {
            let t = tb.calc_time(packet.ts());
            t.seconds as f64 + t.frac
        });
        if let Some(ts) = pkt_secs {
            if ts > end_secs + 0.25 {
                break;
            }
            if ts + 1.5 < start_secs {
                continue;
            }
        }

        let decoded = match decoder.decode(&packet) {
            Ok(d) => {
                consecutive_errors = 0;
                d
            }
            Err(SymphoniaError::DecodeError(_)) => {
                consecutive_errors += 1;
                if consecutive_errors > 256 {
                    break;
                }
                continue;
            }
            Err(_) => break,
        };
        decoded_packets += 1;
        if decoded_packets > 6000 {
            break;
        }

        let spec = *decoded.spec();
        let channels = spec.channels.count().max(1);
        let src_rate = spec.rate.max(8000);

        if let Some(ts) = pkt_secs {
            if ts + (decoded.frames() as f64 / src_rate as f64) < start_secs {
                continue;
            }
        }

        let frames = decoded.frames();
        if frames == 0 {
            continue;
        }

        let buf = sample_buf
            .get_or_insert_with(|| SampleBuffer::<f32>::new(decoded.capacity() as u64, spec));
        let needed_samples = frames.saturating_mul(channels);
        if buf.capacity() < needed_samples {
            *buf = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
        }
        buf.copy_interleaved_ref(decoded);
        let samples = buf.samples();

        downmix_to_mono_into(samples, channels, &mut mono_scratch);
        resample_linear_into(&mono_scratch, src_rate, TARGET_SAMPLE_RATE, &mut mono_16k);

        let max_samples = (duration_secs * TARGET_SAMPLE_RATE as f64).ceil() as usize;
        if mono_16k.len() >= max_samples {
            mono_16k.truncate(max_samples);
            break;
        }
    }

    if mono_16k.is_empty() {
        return Err("未能提取到有效音频样本".to_string());
    }

    Ok(encode_wav_16k_mono(&mono_16k))
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
fn extract_via_ffmpeg_fallback(
    source: &AudioSliceSource,
    start_secs: f64,
    duration_secs: f64,
) -> Result<Vec<u8>, String> {
    let (input, whitelist, headers_arg) = match source {
        AudioSliceSource::LocalFile(p) => {
            let canon = std::fs::canonicalize(p).map_err(|e| format!("invalid local file: {e}"))?;
            let raw_s = canon.to_string_lossy();
            // On Windows `canonicalize` returns `\\?\C:\...` which ffmpeg's `file:` protocol rejects.
            let cleaned = raw_s.strip_prefix(r"\\?\").unwrap_or(&raw_s);
            (format!("file:{cleaned}"), "file", None)
        }
        AudioSliceSource::HttpUrl { url, headers } => {
            let parsed = url::Url::parse(url).map_err(|e| format!("invalid url: {e}"))?;
            if !matches!(parsed.scheme(), "http" | "https") {
                return Err("unsupported URL scheme for ffmpeg".to_string());
            }
            let mut hdr_lines = String::new();
            for (k, v) in headers.iter() {
                if let Ok(vs) = v.to_str() {
                    if !vs.contains('\r') && !vs.contains('\n') {
                        hdr_lines.push_str(k.as_str());
                        hdr_lines.push_str(": ");
                        hdr_lines.push_str(vs);
                        hdr_lines.push_str("\r\n");
                    }
                }
            }
            (
                parsed.to_string(),
                "http,https,tcp,tls,crypto",
                if hdr_lines.is_empty() {
                    None
                } else {
                    Some(hdr_lines)
                },
            )
        }
    };
    let mut cmd = std::process::Command::new("ffmpeg");
    cmd.args([
        "-nostdin",
        "-loglevel",
        "error",
        "-protocol_whitelist",
        whitelist,
    ]);
    if let Some(ref h) = headers_arg {
        cmd.args(["-headers", h]);
    }
    cmd.args([
        "-ss",
        &format!("{start_secs:.3}"),
        "-t",
        &format!("{duration_secs:.3}"),
        "-i",
        &input,
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        "-f",
        "wav",
        "pipe:1",
    ])
    .stdout(std::process::Stdio::piped())
    // Discard stderr to prevent a 64 KiB OS pipe deadlock on verbose decoder warnings!
    .stderr(std::process::Stdio::null());

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("ffmpeg fallback unavailable: {e}"))?;
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(25);
    let mut stdout_pipe = child.stdout.take();
    let reader_handle = std::thread::spawn(move || {
        let mut out = Vec::new();
        if let Some(ref mut pipe) = stdout_pipe {
            let _ = pipe.take(8 * 1024 * 1024).read_to_end(&mut out);
        }
        out
    });
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let mut stdout_buf = reader_handle.join().unwrap_or_default();
                if !status.success() || stdout_buf.len() <= 44 {
                    return Err("ffmpeg audio slice extraction failed".to_string());
                }
                // Patch non-seekable pipe WAV RIFF & data chunk sizes so cloud Whisper APIs accept it
                if stdout_buf.len() >= 44 && &stdout_buf[0..4] == b"RIFF" {
                    let riff_size =
                        (stdout_buf.len().saturating_sub(8)).min(u32::MAX as usize) as u32;
                    stdout_buf[4..8].copy_from_slice(&riff_size.to_le_bytes());
                    if let Some(pos) = stdout_buf.windows(4).position(|w| w == b"data") {
                        if pos + 8 <= stdout_buf.len() {
                            let data_size = (stdout_buf.len().saturating_sub(pos + 8))
                                .min(u32::MAX as usize)
                                as u32;
                            stdout_buf[pos + 4..pos + 8].copy_from_slice(&data_size.to_le_bytes());
                        }
                    }
                }
                return Ok(stdout_buf);
            }
            Ok(None) => {
                if std::time::Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err("ffmpeg audio slice extraction timed out".to_string());
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("ffmpeg wait error: {e}"));
            }
        }
    }
}

fn downmix_to_mono_into(interleaved: &[f32], channels: usize, out: &mut Vec<f32>) {
    out.clear();
    if channels <= 1 {
        out.extend_from_slice(interleaved);
        return;
    }
    let frames = interleaved.len() / channels;
    out.reserve(frames);
    let inv = 1.0 / channels as f32;
    for f in 0..frames {
        let mut sum = 0.0f32;
        for c in 0..channels {
            sum += interleaved[f * channels + c];
        }
        out.push(sum * inv);
    }
}

#[cfg(test)]
fn downmix_to_mono(interleaved: &[f32], channels: usize) -> Vec<f32> {
    let mut out = Vec::new();
    downmix_to_mono_into(interleaved, channels, &mut out);
    out
}

fn resample_linear_into(src: &[f32], src_rate: u32, dst_rate: u32, out: &mut Vec<f32>) {
    if src.is_empty() {
        return;
    }
    if src_rate == dst_rate {
        out.extend_from_slice(src);
        return;
    }
    let ratio = src_rate as f64 / dst_rate as f64;
    let out_len = ((src.len() as f64) / ratio).floor() as usize;
    out.reserve(out_len);
    for i in 0..out_len {
        let pos = i as f64 * ratio;
        let idx = pos as usize;
        let frac = (pos - idx as f64) as f32;
        let s0 = src[idx.min(src.len() - 1)];
        let s1 = src[(idx + 1).min(src.len() - 1)];
        out.push(s0 + (s1 - s0) * frac);
    }
}

pub fn encode_wav_16k_mono(samples: &[f32]) -> Vec<u8> {
    let data_bytes = (samples.len() * 2) as u32;
    let riff_size = 36 + data_bytes;
    let mut out = Vec::with_capacity(44 + data_bytes as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&riff_size.to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend_from_slice(b"fmt ");
    out.extend_from_slice(&16u32.to_le_bytes()); // PCM chunk size
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM format
    out.extend_from_slice(&1u16.to_le_bytes()); // Mono
    out.extend_from_slice(&TARGET_SAMPLE_RATE.to_le_bytes());
    out.extend_from_slice(&(TARGET_SAMPLE_RATE * 2).to_le_bytes()); // byte rate
    out.extend_from_slice(&2u16.to_le_bytes()); // block align
    out.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_bytes.to_le_bytes());
    for &s in samples {
        let clamped = (s.clamp(-1.0, 1.0) * 32767.0) as i16;
        out.extend_from_slice(&clamped.to_le_bytes());
    }
    out
}

/// Build an RFC 7578 `multipart/form-data` payload for OpenAI / Groq / SiliconFlow /
/// faster-whisper `/audio/transcriptions`.
pub fn build_multipart_wav_body(
    wav_bytes: &[u8],
    model: &str,
    language: Option<&str>,
    prompt: Option<&str>,
    boundary: &str,
) -> Vec<u8> {
    let mut body = Vec::with_capacity(wav_bytes.len() + 1024);

    let mut push_field = |name: &str, val: &str| {
        body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
        body.extend_from_slice(
            format!("Content-Disposition: form-data; name=\"{name}\"\r\n\r\n{val}\r\n").as_bytes(),
        );
    };

    push_field("model", model);
    push_field("response_format", "verbose_json");
    push_field("timestamp_granularities[]", "segment");
    if let Some(lang) = language
        .map(str::trim)
        .filter(|s| !s.is_empty() && !s.eq_ignore_ascii_case("auto"))
    {
        push_field("language", lang);
    }
    if let Some(p) = prompt.map(str::trim).filter(|s| !s.is_empty()) {
        push_field("prompt", p);
    }

    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        b"Content-Disposition: form-data; name=\"file\"; filename=\"slice.wav\"\r\nContent-Type: audio/wav\r\n\r\n",
    );
    body.extend_from_slice(wav_bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

/// Parse Whisper `verbose_json` or plain `{ "text": "..." }` (e.g. SiliconFlow SenseVoiceSmall)
/// into absolute-timestamped `SubtitleCue`s shifted by `slice_start_ms`.
pub fn parse_asr_response(
    body: &Value,
    slice_start_ms: i64,
    slice_duration_ms: i64,
) -> (Vec<SubtitleCue>, Option<String>) {
    let detected_lang = body
        .get("language")
        .and_then(Value::as_str)
        .map(ToString::to_string);

    let mut cues = Vec::new();
    if let Some(segments) = body.get("segments").and_then(Value::as_array) {
        for seg in segments {
            let raw_start = seg.get("start").and_then(Value::as_f64).unwrap_or(0.0);
            let start = if raw_start.is_finite() {
                raw_start.clamp(0.0, 86_400.0)
            } else {
                0.0
            };
            let raw_end = seg
                .get("end")
                .and_then(Value::as_f64)
                .unwrap_or(start + 2.5);
            let end = if raw_end.is_finite() {
                raw_end.clamp(start, 86_400.0)
            } else {
                start + 2.5
            };
            let raw_text = seg.get("text").and_then(Value::as_str).unwrap_or("");
            let text = clean_asr_text(raw_text);
            if text.is_empty() {
                continue;
            }
            let start_ms = slice_start_ms.saturating_add((start * 1000.0).round() as i64);
            let end_ms = slice_start_ms
                .saturating_add((end * 1000.0).round() as i64)
                .max(start_ms.saturating_add(800));
            cues.push(SubtitleCue {
                start_ms,
                end_ms,
                text,
            });
        }
    }

    // Fallback when provider returns `{ "text": "..." }` without `segments` (e.g. SenseVoiceSmall)
    if cues.is_empty() {
        if let Some(raw_text) = body.get("text").and_then(Value::as_str) {
            let cleaned = clean_asr_text(raw_text);
            if !cleaned.is_empty() {
                let parts = split_sentences(&cleaned);
                let total_chars: usize = parts.iter().map(|p| p.chars().count().max(1)).sum();
                let mut cursor_ms = slice_start_ms;
                for (i, part) in parts.iter().enumerate() {
                    let slice_end = slice_start_ms.saturating_add(slice_duration_ms.max(1000));
                    let share = if i + 1 == parts.len() {
                        slice_end.saturating_sub(cursor_ms)
                    } else {
                        ((part.chars().count().max(1) as f64 / total_chars.max(1) as f64)
                            * slice_duration_ms.max(1000) as f64)
                            .round() as i64
                    };
                    let end_ms = cursor_ms.saturating_add(share.max(900)).min(slice_end);
                    cues.push(SubtitleCue {
                        start_ms: cursor_ms,
                        end_ms: end_ms.max(cursor_ms.saturating_add(600)),
                        text: part.clone(),
                    });
                    cursor_ms = end_ms;
                }
            }
        }
    }

    (cues, detected_lang)
}

fn clean_asr_text(raw: &str) -> String {
    // Strip SenseVoice control tokens like `<|ja|>`, `<|NEUTRAL|>`, `<|Speech|>`, `<|woitn|>`
    let mut out = String::with_capacity(raw.len());
    let mut rest = raw;
    while let Some(start) = rest.find("<|") {
        out.push_str(&rest[..start]);
        if let Some(end) = rest[start + 2..].find("|>") {
            rest = &rest[start + 2 + end + 2..];
        } else {
            out.push_str(&rest[start..]);
            rest = "";
            break;
        }
    }
    out.push_str(rest);
    out.trim().to_string()
}

fn split_sentences(text: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut current = String::new();
    for ch in text.chars() {
        current.push(ch);
        if matches!(ch, '。' | '！' | '？' | '.' | '!' | '?' | '\n') {
            let trimmed = current.trim();
            if !trimmed.is_empty() {
                parts.push(trimmed.to_string());
            }
            current.clear();
        }
    }
    let tail = current.trim();
    if !tail.is_empty() {
        parts.push(tail.to_string());
    }
    if parts.is_empty() && !text.trim().is_empty() {
        parts.push(text.trim().to_string());
    }
    parts
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn encodes_valid_16k_wav_and_resamples_stereo() {
        let stereo_48k: Vec<f32> = (0..480 * 2)
            .map(|i| if i % 2 == 0 { 0.5 } else { -0.5 })
            .collect();
        let mono = downmix_to_mono(&stereo_48k, 2);
        assert_eq!(mono.len(), 480);
        let mut resampled = Vec::new();
        resample_linear_into(&mono, 48_000, 16_000, &mut resampled);
        assert_eq!(resampled.len(), 160);

        let wav = encode_wav_16k_mono(&resampled);
        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(&wav[8..12], b"WAVE");
        assert_eq!(wav.len(), 44 + 160 * 2);
    }

    #[test]
    fn parses_whisper_verbose_json_and_sensevoice_fallback() {
        let whisper = json!({
            "language": "ja",
            "segments": [
                { "start": 0.5, "end": 3.2, "text": " おはようございます " },
                { "start": 3.5, "end": 6.0, "text": " 今日もよろしくお願いします " }
            ]
        });
        let (cues, lang) = parse_asr_response(&whisper, 30_000, 25_000);
        assert_eq!(lang.as_deref(), Some("ja"));
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0].start_ms, 30_500);
        assert_eq!(cues[0].end_ms, 33_200);
        assert_eq!(cues[0].text, "おはようございます");

        let sensevoice = json!({
            "text": "<|ja|><|NEUTRAL|><|Speech|><|woitn|>すごいね！本当にありがとう。"
        });
        let (sv_cues, _) = parse_asr_response(&sensevoice, 10_000, 10_000);
        assert_eq!(sv_cues.len(), 2);
        assert_eq!(sv_cues[0].text, "すごいね！");
        assert_eq!(sv_cues[1].text, "本当にありがとう。");
        assert_eq!(sv_cues[0].start_ms, 10_000);
        assert_eq!(sv_cues[1].end_ms, 20_000);
    }

    #[test]
    fn builds_valid_multipart_body() {
        let wav = encode_wav_16k_mono(&[0.0, 0.25, -0.25]);
        let body = build_multipart_wav_body(
            &wav,
            "whisper-large-v3-turbo",
            Some("ja"),
            Some("前文"),
            "VedroBoundary123",
        );
        let text = String::from_utf8_lossy(&body);
        assert!(text.contains("--VedroBoundary123\r\n"));
        assert!(text.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo"));
        assert!(text.contains("name=\"language\"\r\n\r\nja"));
        assert!(text.contains("filename=\"slice.wav\""));
        assert!(text.ends_with("--VedroBoundary123--\r\n"));
    }
}
