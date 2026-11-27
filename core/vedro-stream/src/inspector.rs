use serde::{Deserialize, Serialize};

/// Dolby Vision profile & compatibility information parsed directly from binary container headers
/// (`dvcC`/`dvvC` in MP4/ISOBMFF or MKV `BlockAdditionMapping` `dvcC`/`dvvC` / HEVC RPU).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DolbyVisionInfo {
    pub dv_version_major: u8,
    pub dv_version_minor: u8,
    /// Common profiles:
    /// - 5: Single-layer IPT-PQ-C2 (no HDR10 base layer — requires libplacebo/native DoVi reshaping!)
    /// - 7: UHD Blu-ray Dual-Layer (MEL or FEL) + HDR10 base layer
    /// - 8: Single-layer with cross-compatibility (8.1 = HDR10, 8.2 = SDR, 8.4 = HLG)
    pub dv_profile: u8,
    pub dv_level: u8,
    pub rpu_present: bool,
    pub el_present: bool,
    pub bl_present: bool,
    /// Signal compatibility ID (e.g. 1 = HDR10/BT.2020 PQ, 4 = HLG, 0 = none/Profile 5).
    pub bl_signal_compatibility_id: u8,
}

impl DolbyVisionInfo {
    /// Parse standard 24-byte `dvcC` / `dvvC` Dolby Vision Configuration Record (ISO/IEC 14496-15).
    pub fn parse_dvcc(data: &[u8]) -> Option<Self> {
        if data.len() < 5 {
            return None;
        }
        let dv_version_major = data[0];
        let dv_version_minor = data[1];
        // Bytes 2..4 (16 bits):
        // bits 15..9  (7 bits): dv_profile
        // bits 8..3   (6 bits): dv_level
        // bit  2      (1 bit):  rpu_present_flag
        // bit  1      (1 bit):  el_present_flag
        // bit  0      (1 bit):  bl_present_flag
        let word = u16::from_be_bytes([data[2], data[3]]);
        let dv_profile = ((word >> 9) & 0x7F) as u8;
        let dv_level = ((word >> 3) & 0x3F) as u8;
        let rpu_present = ((word >> 2) & 0x01) != 0;
        let el_present = ((word >> 1) & 0x01) != 0;
        let bl_present = (word & 0x01) != 0;
        let bl_signal_compatibility_id = (data[4] >> 4) & 0x0F;

        // Sanity bounds for real Dolby Vision profiles (0..=10)
        if dv_profile > 20 || dv_version_major > 5 {
            return None;
        }
        Some(Self {
            dv_version_major,
            dv_version_minor,
            dv_profile,
            dv_level,
            rpu_present,
            el_present,
            bl_present,
            bl_signal_compatibility_id,
        })
    }

    pub fn display_label(&self) -> String {
        match (self.dv_profile, self.bl_signal_compatibility_id) {
            (5, _) => "Dolby Vision Profile 5 (IPT-PQ)".to_string(),
            (7, _) if self.el_present => "Dolby Vision Profile 7 (UHD BD Dual-Layer)".to_string(),
            (7, _) => "Dolby Vision Profile 7".to_string(),
            (8, 1) => "Dolby Vision Profile 8.1 (HDR10)".to_string(),
            (8, 4) => "Dolby Vision Profile 8.4 (HLG)".to_string(),
            (p, c) if c > 0 => format!("Dolby Vision Profile {p}.{c}"),
            (p, _) => format!("Dolby Vision Profile {p}"),
        }
    }

    /// True if playing this stream without DoVi RPU reshaping will cause green/purple colors.
    pub fn requires_ipt_reshaping(&self) -> bool {
        self.dv_profile == 5
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HdrFormat {
    Sdr,
    Hdr10,
    Hdr10Plus,
    Hlg,
    DolbyVision(DolbyVisionInfo),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpatialAudioFormat {
    None,
    DolbyAtmosTrueHd,
    DolbyAtmosEac3Joc,
    DtsX,
    DtsHdMa,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct InspectedMedia {
    pub container: String,
    pub video_codecs: Vec<String>,
    pub audio_codecs: Vec<String>,
    pub hdr_format: Option<HdrFormat>,
    pub dolby_vision: Option<DolbyVisionInfo>,
    pub spatial_audio: Option<SpatialAudioFormat>,
    pub has_hdr10_metadata: bool,
    pub has_hlg_transfer: bool,
}

/// Inspect raw container header bytes (first ~256 KiB - 2 MiB of a file or stream)
/// to identify container format, Dolby Vision Profile 5/7/8, HDR10/HLG, and Dolby Atmos/DTS:X
/// locally in pure Rust — critical when streaming from `embygo` without server-side `ffprobe`.
pub fn inspect_media_header(data: &[u8]) -> InspectedMedia {
    let mut info = InspectedMedia::default();
    if data.len() < 16 {
        return info;
    }

    // 1. Detect container magic
    if data.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]) {
        info.container = "matroska".to_string();
        inspect_mkv_bytes(data, &mut info);
    } else if data.len() >= 12 && &data[4..8] == b"ftyp" {
        info.container = "mp4".to_string();
        inspect_mp4_boxes(data, &mut info);
    } else if data[0] == 0x47 && (data.len() >= 189 && data[188] == 0x47) {
        info.container = "mpegts".to_string();
        inspect_mpegts_bytes(data, &mut info);
    } else {
        info.container = "unknown".to_string();
    }

    // Finalize HDR classification
    if let Some(dv) = &info.dolby_vision {
        info.hdr_format = Some(HdrFormat::DolbyVision(dv.clone()));
    } else if info.has_hlg_transfer {
        info.hdr_format = Some(HdrFormat::Hlg);
    } else if info.has_hdr10_metadata {
        info.hdr_format = Some(HdrFormat::Hdr10);
    } else {
        info.hdr_format = Some(HdrFormat::Sdr);
    }

    info
}

fn push_unique(vec: &mut Vec<String>, value: &str) {
    if !vec.iter().any(|v| v == value) {
        vec.push(value.to_string());
    }
}

fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn inspect_mkv_bytes(data: &[u8], info: &mut InspectedMedia) {
    // Restrict EBML metadata scanning to the header/Tracks section BEFORE the first Cluster
    // (0x1F 0x43 0xB6 0x75) so random compressed video frame bytes never trigger false positives.
    let header_slice = match find_subslice(data, &[0x1F, 0x43, 0xB6, 0x75]) {
        Some(cluster_pos) if cluster_pos > 16 => &data[..cluster_pos],
        _ => data,
    };

    // Video CodecID markers inside Matroska Tracks element
    if find_subslice(header_slice, b"V_MPEGH/ISO/HEVC").is_some() {
        push_unique(&mut info.video_codecs, "hevc");
    }
    if find_subslice(header_slice, b"V_MPEG4/ISO/AVC").is_some() {
        push_unique(&mut info.video_codecs, "h264");
    }
    if find_subslice(header_slice, b"V_AV1").is_some() {
        push_unique(&mut info.video_codecs, "av1");
    }
    if find_subslice(header_slice, b"V_VP9").is_some() {
        push_unique(&mut info.video_codecs, "vp9");
    }

    // Audio CodecID markers
    if find_subslice(header_slice, b"A_TRUEHD").is_some() {
        push_unique(&mut info.audio_codecs, "truehd");
        info.spatial_audio = Some(SpatialAudioFormat::DolbyAtmosTrueHd);
    }
    if find_subslice(header_slice, b"A_EAC3").is_some() {
        push_unique(&mut info.audio_codecs, "eac3");
        if info.spatial_audio.is_none() {
            // Check for JOC/Atmos track name hint inside Tracks
            let lower = String::from_utf8_lossy(header_slice).to_lowercase();
            if lower.contains("atmos") || lower.contains("joc") {
                info.spatial_audio = Some(SpatialAudioFormat::DolbyAtmosEac3Joc);
            }
        }
    }
    if find_subslice(header_slice, b"A_AC3").is_some() {
        push_unique(&mut info.audio_codecs, "ac3");
    }
    if find_subslice(header_slice, b"A_DTS").is_some() {
        push_unique(&mut info.audio_codecs, "dts");
        let lower = String::from_utf8_lossy(header_slice).to_lowercase();
        if lower.contains("dts:x") || lower.contains("dts-x") || lower.contains("dtsx") {
            info.spatial_audio = Some(SpatialAudioFormat::DtsX);
        } else if lower.contains("dts-hd") || lower.contains("dtshd") {
            info.spatial_audio = Some(SpatialAudioFormat::DtsHdMa);
        }
    }
    if find_subslice(header_slice, b"A_FLAC").is_some() {
        push_unique(&mut info.audio_codecs, "flac");
    }
    if find_subslice(header_slice, b"A_OPUS").is_some() {
        push_unique(&mut info.audio_codecs, "opus");
    }
    if find_subslice(header_slice, b"A_AAC").is_some() {
        push_unique(&mut info.audio_codecs, "aac");
    }

    // Matroska BlockAdditionMapping for Dolby Vision:
    // BlockAddIDType = 0x64766343 ("dvcC") or 0x64767643 ("dvvC"), followed by
    // BlockAddIDExtraData (element ID 0x41ED) carrying the 24-byte DOVI configuration record!
    for marker in [b"dvcC".as_slice(), b"dvvC".as_slice()] {
        if let Some(pos) = find_subslice(header_slice, marker) {
            // Search nearby (within 64 bytes) for EBML BlockAddIDExtraData 0x41 0xED
            let window_end = (pos + 64).min(header_slice.len());
            if let Some(rel) = find_subslice(&header_slice[pos..window_end], &[0x41, 0xED]) {
                let extra_pos = pos + rel + 2;
                if extra_pos + 2 < header_slice.len() {
                    // VINT size (1-byte VINT for 24 bytes is 0x98 = 0x80 | 24)
                    let vint = header_slice[extra_pos];
                    let payload_start = if (vint & 0x80) != 0 {
                        extra_pos + 1
                    } else {
                        extra_pos + 2
                    };
                    if payload_start + 5 <= header_slice.len() {
                        if let Some(dv) =
                            DolbyVisionInfo::parse_dvcc(&header_slice[payload_start..])
                        {
                            info.dolby_vision = Some(dv);
                            break;
                        }
                    }
                }
            }
        }
    }

    // Matroska Colour element (0x55B0): TransferCharacteristics (0x55BA):
    // 16 = SMPTE ST 2084 (PQ/HDR10), 18 = ARIB STD-B67 (HLG), and MasteringMetadata (0x55D0)
    if let Some(colour_pos) = find_subslice(header_slice, &[0x55, 0xB0]) {
        let colour_end = (colour_pos + 256).min(header_slice.len());
        let colour_slice = &header_slice[colour_pos..colour_end];
        if let Some(pos) = find_subslice(colour_slice, &[0x55, 0xBA, 0x81]) {
            if pos + 3 < colour_slice.len() {
                match colour_slice[pos + 3] {
                    16 => info.has_hdr10_metadata = true,
                    18 => info.has_hlg_transfer = true,
                    _ => {}
                }
            }
        }
        if find_subslice(colour_slice, &[0x55, 0xD0]).is_some() {
            info.has_hdr10_metadata = true;
        }
    }
}

fn inspect_mp4_boxes(data: &[u8], info: &mut InspectedMedia) {
    // Video codec fourccs
    if find_subslice(data, b"hvc1").is_some()
        || find_subslice(data, b"hev1").is_some()
        || find_subslice(data, b"dvh1").is_some()
        || find_subslice(data, b"dvhe").is_some()
    {
        push_unique(&mut info.video_codecs, "hevc");
    }
    if find_subslice(data, b"avc1").is_some() || find_subslice(data, b"avc3").is_some() {
        push_unique(&mut info.video_codecs, "h264");
    }
    if find_subslice(data, b"av01").is_some() || find_subslice(data, b"dav1").is_some() {
        push_unique(&mut info.video_codecs, "av1");
    }

    // Dolby Vision `dvcC` or `dvvC` box: [4-byte size][4-byte 'dvcC'][24-byte payload]
    for box_tag in [b"dvcC".as_slice(), b"dvvC".as_slice()] {
        if let Some(pos) = find_subslice(data, box_tag) {
            let payload_start = pos + 4;
            if payload_start + 5 <= data.len() {
                if let Some(dv) = DolbyVisionInfo::parse_dvcc(&data[payload_start..]) {
                    info.dolby_vision = Some(dv);
                    break;
                }
            }
        }
    }

    // HDR10 boxes (`mdcv` Mastering Display Color Volume, `clli` Content Light Level Info)
    if find_subslice(data, b"mdcv").is_some() || find_subslice(data, b"clli").is_some() {
        info.has_hdr10_metadata = true;
    }

    // Audio codec & Dolby Atmos boxes
    if find_subslice(data, b"mlpa").is_some() {
        push_unique(&mut info.audio_codecs, "truehd");
        info.spatial_audio = Some(SpatialAudioFormat::DolbyAtmosTrueHd);
    }
    if let Some(pos) = find_subslice(data, b"dec3") {
        push_unique(&mut info.audio_codecs, "eac3");
        // In ETSI TS 102 366 EC3SpecificBox, flag_ec3_extension_type_a (JOC/Atmos) sits after substreams
        // Usually signalled via `complexity_index_type_a` > 0 or trailing 0x01 + object count
        let slice_end = (pos + 32).min(data.len());
        if slice_end > pos + 9 {
            let slice = &data[pos + 4..slice_end];
            // Check for JOC Atmos extension marker (flag_ec3_extension_type_a == 1)
            if slice.len() >= 7 && (slice[5] & 0x01) != 0 && slice[6] > 0 {
                info.spatial_audio = Some(SpatialAudioFormat::DolbyAtmosEac3Joc);
            }
        }
    }
    if find_subslice(data, b"ec-3").is_some() {
        push_unique(&mut info.audio_codecs, "eac3");
    }
    if find_subslice(data, b"ac-3").is_some() || find_subslice(data, b"dac3").is_some() {
        push_unique(&mut info.audio_codecs, "ac3");
    }
    if find_subslice(data, b"mp4a").is_some() {
        push_unique(&mut info.audio_codecs, "aac");
    }
    if find_subslice(data, b"fLaC").is_some() {
        push_unique(&mut info.audio_codecs, "flac");
    }
}

fn inspect_mpegts_bytes(data: &[u8], info: &mut InspectedMedia) {
    // Registration descriptors in PMT: "DOVI", "HDMV", "AC-3", "EAC3", "HEVC"
    if find_subslice(data, b"DOVI").is_some() {
        info.dolby_vision = Some(DolbyVisionInfo {
            dv_version_major: 1,
            dv_version_minor: 0,
            dv_profile: 7,
            dv_level: 6,
            rpu_present: true,
            el_present: true,
            bl_present: true,
            bl_signal_compatibility_id: 1,
        });
    }
    if find_subslice(data, b"HEVC").is_some() {
        push_unique(&mut info.video_codecs, "hevc");
    }
    if find_subslice(data, b"HDMV").is_some() {
        push_unique(&mut info.audio_codecs, "truehd");
    }
}

/// Structured embedded track entry parsed directly from Matroska EBML `Tracks` or MP4 `moov/trak`
/// header bytes over HTTP Range without needing server-side `ffprobe`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InspectedTrack {
    pub index: i32,
    /// `"Video"` | `"Audio"` | `"Subtitle"`
    pub stream_type: String,
    pub codec: String,
    pub language: Option<String>,
    pub title: Option<String>,
    pub display_title: String,
    pub is_default: bool,
    pub is_forced: bool,
    pub is_text_subtitle: bool,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub channels: Option<u32>,
    pub video_range: Option<String>,
}

/// Extract the full embedded track table (Video, Audio, Subtitle) from the first ~256-512 KiB
/// of a Matroska/WebM or MP4/M4V/MOV container header.
pub fn inspect_media_tracks(data: &[u8]) -> Vec<InspectedTrack> {
    if data.len() < 16 {
        return Vec::new();
    }
    let header_info = inspect_media_header(data);
    let mut tracks = if data.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]) {
        parse_mkv_tracks(data, &header_info)
    } else if data.len() >= 12 && &data[4..8] == b"ftyp" {
        parse_mp4_tracks(data, &header_info)
    } else {
        Vec::new()
    };
    for (pos, t) in tracks.iter_mut().enumerate() {
        t.index = pos as i32;
    }
    tracks
}

fn read_ebml_id(buf: &[u8]) -> Option<(u32, usize)> {
    let first = *buf.first()?;
    let len = first.leading_zeros() as usize + 1;
    if len > 4 || buf.len() < len {
        return None;
    }
    let mut id = 0u32;
    for &b in &buf[..len] {
        id = (id << 8) | (b as u32);
    }
    Some((id, len))
}

fn read_ebml_size(buf: &[u8]) -> Option<(Option<usize>, usize)> {
    let first = *buf.first()?;
    let len = first.leading_zeros() as usize + 1;
    if len > 8 || buf.len() < len {
        return None;
    }
    let mask = if len == 8 { 0u8 } else { 0xFFu8 >> len };
    let mut val = (first & mask) as u64;
    let mut all_ones = (first & mask) == mask;
    for &b in &buf[1..len] {
        val = (val << 8) | (b as u64);
        all_ones &= b == 0xFF;
    }
    if all_ones {
        Some((None, len))
    } else {
        Some((usize::try_from(val).ok(), len))
    }
}

fn ebml_uint(payload: &[u8]) -> u64 {
    let mut v = 0u64;
    for &b in payload.iter().take(8) {
        v = (v << 8) | (b as u64);
    }
    v
}

fn ebml_utf8(payload: &[u8]) -> Option<String> {
    let end = payload
        .iter()
        .position(|&b| b == 0)
        .unwrap_or(payload.len());
    let s = String::from_utf8_lossy(&payload[..end]).trim().to_string();
    if s.is_empty() || s.eq_ignore_ascii_case("und") {
        None
    } else {
        Some(s)
    }
}

fn map_mkv_codec(codec_id: &str) -> (&'static str, bool) {
    let c = codec_id.trim();
    match c {
        "V_MPEGH/ISO/HEVC" => ("hevc", false),
        "V_MPEG4/ISO/AVC" => ("h264", false),
        "V_AV1" => ("av1", false),
        "V_VP9" => ("vp9", false),
        "V_VP8" => ("vp8", false),
        "V_MPEG2" => ("mpeg2video", false),
        "A_TRUEHD" => ("truehd", false),
        "A_EAC3" => ("eac3", false),
        "A_AC3" => ("ac3", false),
        "A_DTS" => ("dts", false),
        "A_FLAC" => ("flac", false),
        "A_AAC" => ("aac", false),
        "A_OPUS" => ("opus", false),
        "A_VORBIS" => ("vorbis", false),
        "A_MPEG/L3" => ("mp3", false),
        "A_PCM/INT/LIT" | "A_PCM/INT/BIG" | "A_PCM/FLOAT/IEEE" => ("pcm", false),
        "S_TEXT/ASS" => ("ass", true),
        "S_TEXT/SSA" => ("ssa", true),
        "S_TEXT/UTF8" | "S_TEXT/ASCII" => ("srt", true),
        "S_TEXT/WEBVTT" => ("webvtt", true),
        "S_HDMV/PGS" => ("pgssub", false),
        "S_VOBSUB" => ("dvdsub", false),
        "S_DVBSUB" => ("dvbsub", false),
        _ if c.starts_with("A_AAC") => ("aac", false),
        _ if c.starts_with("A_DTS") => ("dts", false),
        _ if c.starts_with("S_TEXT") => ("srt", true),
        _ => ("", false),
    }
}

fn pretty_lang_name(lang: Option<&str>) -> Option<&'static str> {
    let l = lang?.trim().to_lowercase();
    match l.as_str() {
        "chi" | "zho" | "zh" | "chs" | "zh-cn" | "zh-hans" | "cmn" => Some("中文"),
        "cht" | "zh-tw" | "zh-hk" | "zh-hant" => Some("繁体中文"),
        "yue" => Some("粤语"),
        "jpn" | "ja" => Some("日语"),
        "eng" | "en" => Some("英语"),
        "kor" | "ko" => Some("韩语"),
        "fra" | "fre" | "fr" => Some("法语"),
        "deu" | "ger" | "de" => Some("德语"),
        "spa" | "es" => Some("西语"),
        "rus" | "ru" => Some("俄语"),
        _ => None,
    }
}

#[allow(clippy::too_many_arguments)]
fn compose_track_display_title(
    stream_type: &str,
    codec: &str,
    language: Option<&str>,
    title: Option<&str>,
    width: Option<u32>,
    height: Option<u32>,
    channels: Option<u32>,
    video_range: Option<&str>,
    is_forced: bool,
) -> String {
    let mut parts: Vec<String> = Vec::new();
    match stream_type {
        "Video" => {
            if let Some(h) = height {
                if h >= 2000 {
                    parts.push("4K".to_string());
                } else if h > 0 {
                    parts.push(format!("{h}p"));
                } else if let Some(w) = width {
                    if w >= 3600 {
                        parts.push("4K".to_string());
                    }
                }
            }
            if let Some(vr) = video_range {
                if !vr.is_empty() {
                    parts.push(vr.to_string());
                }
            }
            if !codec.is_empty() {
                parts.push(codec.to_uppercase());
            }
        }
        "Audio" => {
            if let Some(t) = title.filter(|s| !s.is_empty()) {
                parts.push(t.to_string());
            } else if let Some(p) = pretty_lang_name(language) {
                parts.push(p.to_string());
            } else if let Some(l) = language.filter(|s| !s.is_empty()) {
                parts.push(l.to_uppercase());
            }
            if !codec.is_empty() {
                parts.push(codec.to_uppercase());
            }
            if let Some(ch) = channels {
                let layout = match ch {
                    1 => "Mono".to_string(),
                    2 => "2.0".to_string(),
                    6 => "5.1".to_string(),
                    8 => "7.1".to_string(),
                    n if n > 0 => format!("{n}ch"),
                    _ => String::new(),
                };
                if !layout.is_empty() {
                    parts.push(layout);
                }
            }
        }
        _ => {
            if let Some(t) = title.filter(|s| !s.is_empty()) {
                parts.push(t.to_string());
            } else if let Some(p) = pretty_lang_name(language) {
                parts.push(p.to_string());
            } else if let Some(l) = language.filter(|s| !s.is_empty()) {
                parts.push(l.to_uppercase());
            }
            if is_forced && !parts.iter().any(|p| p.to_lowercase().contains("forced")) {
                parts.push("Forced".to_string());
            }
            if !codec.is_empty() {
                parts.push(codec.to_uppercase());
            }
        }
    }
    if parts.is_empty() {
        codec.to_uppercase()
    } else {
        parts.join(" · ")
    }
}

fn parse_mkv_tracks(data: &[u8], header_info: &InspectedMedia) -> Vec<InspectedTrack> {
    let header_slice = match find_subslice(data, &[0x1F, 0x43, 0xB6, 0x75]) {
        Some(cluster_pos) if cluster_pos > 16 => &data[..cluster_pos],
        _ => data,
    };
    // Locate Matroska `Tracks` master element: 0x16 0x54 0xAE 0x6B
    let Some(tracks_pos) = find_subslice(header_slice, &[0x16, 0x54, 0xAE, 0x6B]) else {
        return Vec::new();
    };
    let after_id = &header_slice[tracks_pos + 4..];
    let Some((tracks_len_opt, size_bytes)) = read_ebml_size(after_id) else {
        return Vec::new();
    };
    let body_start = tracks_pos.saturating_add(4).saturating_add(size_bytes);
    if body_start >= header_slice.len() {
        return Vec::new();
    }
    let body_end = tracks_len_opt
        .map(|l| body_start.saturating_add(l).min(header_slice.len()))
        .unwrap_or(header_slice.len());
    let mut cursor = &header_slice[body_start..body_end];
    let mut out = Vec::new();

    while cursor.len() >= 3 && out.len() < 128 {
        let Some((id, id_len)) = read_ebml_id(cursor) else {
            break;
        };
        let Some((elem_size_opt, sz_len)) = read_ebml_size(&cursor[id_len..]) else {
            break;
        };
        let hdr_len = id_len + sz_len;
        let Some(elem_size) = elem_size_opt else {
            break;
        };
        let Some(end) = hdr_len.checked_add(elem_size) else {
            break;
        };
        if end > cursor.len() {
            break;
        }
        let payload = &cursor[hdr_len..end];
        cursor = &cursor[end..];

        // 0xAE = TrackEntry
        if id == 0xAE {
            if let Some(track) = parse_mkv_track_entry(payload, header_info) {
                out.push(track);
            }
        }
    }
    out
}

fn parse_mkv_track_entry(entry: &[u8], header_info: &InspectedMedia) -> Option<InspectedTrack> {
    let mut track_type: u64 = 0;
    let mut codec_id = String::new();
    let mut name: Option<String> = None;
    let mut lang: Option<String> = None;
    let mut lang_bcp47: Option<String> = None;
    let mut is_default = true; // Matroska spec defaults FlagDefault to 1 unless explicitly 0
    let mut is_forced = false;
    let mut width: Option<u32> = None;
    let mut height: Option<u32> = None;
    let mut channels: Option<u32> = None;

    let mut cur = entry;
    while cur.len() >= 2 {
        let Some((id, id_len)) = read_ebml_id(cur) else {
            break;
        };
        let Some((Some(sz), sz_len)) = read_ebml_size(&cur[id_len..]) else {
            break;
        };
        let h = id_len + sz_len;
        let Some(end) = h.checked_add(sz) else {
            break;
        };
        if end > cur.len() {
            break;
        }
        let val = &cur[h..end];
        cur = &cur[end..];

        match id {
            0x83 => track_type = ebml_uint(val), // TrackType: 1=video, 2=audio, 17=subtitle
            0x86 => {
                if let Some(s) = ebml_utf8(val) {
                    codec_id = s;
                }
            }
            0x536E => name = ebml_utf8(val),
            0x22B59C => lang = ebml_utf8(val),
            0x22B59D => lang_bcp47 = ebml_utf8(val),
            0x88 => is_default = ebml_uint(val) != 0,
            0x55AA => is_forced = ebml_uint(val) != 0,
            0xE0 => {
                // Video sub-master
                let mut vcur = val;
                while vcur.len() >= 2 {
                    let Some((vid, vid_l)) = read_ebml_id(vcur) else {
                        break;
                    };
                    let Some((Some(vsz), vsz_l)) = read_ebml_size(&vcur[vid_l..]) else {
                        break;
                    };
                    let vh = vid_l + vsz_l;
                    let Some(vend) = vh.checked_add(vsz) else {
                        break;
                    };
                    if vend > vcur.len() {
                        break;
                    }
                    let vval = &vcur[vh..vend];
                    vcur = &vcur[vend..];
                    match vid {
                        0xB0 => width = Some(ebml_uint(vval) as u32),
                        0xBA => height = Some(ebml_uint(vval) as u32),
                        _ => {}
                    }
                }
            }
            0xE1 => {
                // Audio sub-master
                let mut acur = val;
                while acur.len() >= 2 {
                    let Some((aid, aid_l)) = read_ebml_id(acur) else {
                        break;
                    };
                    let Some((Some(asz), asz_l)) = read_ebml_size(&acur[aid_l..]) else {
                        break;
                    };
                    let ah = aid_l + asz_l;
                    let Some(aend) = ah.checked_add(asz) else {
                        break;
                    };
                    if aend > acur.len() {
                        break;
                    }
                    let aval = &acur[ah..aend];
                    acur = &acur[aend..];
                    if aid == 0x9F {
                        channels = Some(ebml_uint(aval) as u32);
                    }
                }
            }
            _ => {}
        }
    }

    let stream_type = match track_type {
        1 => "Video",
        2 => "Audio",
        17 => "Subtitle",
        _ => return None,
    };
    let (mapped_codec, is_text_sub) = map_mkv_codec(&codec_id);
    if mapped_codec.is_empty() {
        return None;
    }
    if stream_type == "Subtitle" {
        // Follow EmbyGo rule: don't force Matroska default=1 onto subtitles blindly
        is_default = false;
    }
    let effective_lang = lang_bcp47.or(lang);
    let video_range = if stream_type == "Video" {
        if header_info.dolby_vision.is_some() {
            Some("Dolby Vision".to_string())
        } else if header_info.has_hdr10_metadata {
            Some("HDR10".to_string())
        } else if header_info.has_hlg_transfer {
            Some("HLG".to_string())
        } else {
            None
        }
    } else {
        None
    };
    let display_title = compose_track_display_title(
        stream_type,
        mapped_codec,
        effective_lang.as_deref(),
        name.as_deref(),
        width,
        height,
        channels,
        video_range.as_deref(),
        is_forced,
    );

    Some(InspectedTrack {
        index: 0,
        stream_type: stream_type.to_string(),
        codec: mapped_codec.to_string(),
        language: effective_lang,
        title: name,
        display_title,
        is_default,
        is_forced,
        is_text_subtitle: is_text_sub,
        width,
        height,
        channels,
        video_range,
    })
}

fn walk_mp4_boxes<'a>(buf: &'a [u8], mut f: impl FnMut(&[u8; 4], &'a [u8])) {
    let mut pos = 0usize;
    while pos.checked_add(8).is_some_and(|e| e <= buf.len()) {
        let size32 =
            u32::from_be_bytes([buf[pos], buf[pos + 1], buf[pos + 2], buf[pos + 3]]) as usize;
        let tag: [u8; 4] = [buf[pos + 4], buf[pos + 5], buf[pos + 6], buf[pos + 7]];
        let (hdr, box_size) = if size32 == 1 {
            if pos.checked_add(16).is_none_or(|e| e > buf.len()) {
                break;
            }
            let sz64 = u64::from_be_bytes([
                buf[pos + 8],
                buf[pos + 9],
                buf[pos + 10],
                buf[pos + 11],
                buf[pos + 12],
                buf[pos + 13],
                buf[pos + 14],
                buf[pos + 15],
            ]);
            let Ok(sz) = usize::try_from(sz64) else {
                break;
            };
            (16usize, sz)
        } else if size32 == 0 {
            (8usize, buf.len() - pos)
        } else {
            (8usize, size32)
        };
        let Some(end) = pos.checked_add(box_size) else {
            break;
        };
        if box_size < hdr || end > buf.len() {
            break;
        }
        f(&tag, &buf[pos + hdr..end]);
        pos = end;
    }
}

fn unpack_mp4_lang(code: u16) -> Option<String> {
    let c1 = (((code >> 10) & 0x1F) as u8).wrapping_add(0x60);
    let c2 = (((code >> 5) & 0x1F) as u8).wrapping_add(0x60);
    let c3 = ((code & 0x1F) as u8).wrapping_add(0x60);
    if !c1.is_ascii_lowercase() || !c2.is_ascii_lowercase() || !c3.is_ascii_lowercase() {
        return None;
    }
    let s = String::from_utf8(vec![c1, c2, c3]).ok()?;
    if s == "und" {
        None
    } else {
        Some(s)
    }
}

fn parse_mp4_tracks(data: &[u8], header_info: &InspectedMedia) -> Vec<InspectedTrack> {
    let mut out = Vec::new();
    walk_mp4_boxes(data, |tag, payload| {
        if tag == b"moov" {
            walk_mp4_boxes(payload, |mtag, mpayload| {
                if mtag == b"trak" && out.len() < 64 {
                    if let Some(t) = parse_mp4_trak(mpayload, header_info) {
                        out.push(t);
                    }
                }
            });
        }
    });
    out
}

fn parse_mp4_trak(trak: &[u8], header_info: &InspectedMedia) -> Option<InspectedTrack> {
    let mut handler = [0u8; 4];
    let mut lang: Option<String> = None;
    let mut codec = String::new();
    let mut width: Option<u32> = None;
    let mut height: Option<u32> = None;
    let mut channels: Option<u32> = None;
    let mut title: Option<String> = None;

    walk_mp4_boxes(trak, |tag, payload| {
        if tag == b"udta" {
            walk_mp4_boxes(payload, |utag, upayload| {
                if utag == b"name" && !upayload.is_empty() {
                    let s = String::from_utf8_lossy(upayload).trim().to_string();
                    if !s.is_empty() {
                        title = Some(s);
                    }
                }
            });
        } else if tag == b"mdia" {
            walk_mp4_boxes(payload, |dtag, dpayload| match dtag {
                b"mdhd" => {
                    if !dpayload.is_empty() {
                        let ver = dpayload[0];
                        let lang_off = if ver == 1 { 28 } else { 16 };
                        if dpayload.len() >= lang_off + 2 {
                            let packed =
                                u16::from_be_bytes([dpayload[lang_off], dpayload[lang_off + 1]]);
                            lang = unpack_mp4_lang(packed);
                        }
                    }
                }
                b"hdlr" => {
                    if dpayload.len() >= 12 {
                        handler.copy_from_slice(&dpayload[8..12]);
                    }
                }
                b"minf" => {
                    walk_mp4_boxes(dpayload, |itag, ipayload| {
                        if itag == b"stbl" {
                            walk_mp4_boxes(ipayload, |stag, spayload| {
                                if stag == b"stsd" && spayload.len() >= 16 {
                                    // [4B ver/flags][4B entry_count][first sample entry box...]
                                    let entries = &spayload[8..];
                                    walk_mp4_boxes(entries, |etag, epayload| {
                                        if !codec.is_empty() {
                                            return;
                                        }
                                        codec = match etag {
                                            b"hvc1" | b"hev1" | b"dvh1" | b"dvhe" => "hevc",
                                            b"avc1" | b"avc3" => "h264",
                                            b"av01" | b"dav1" => "av1",
                                            b"vp09" => "vp9",
                                            b"mp4a" => "aac",
                                            b"ec-3" => "eac3",
                                            b"ac-3" => "ac3",
                                            b"mlpa" => "truehd",
                                            b"fLaC" => "flac",
                                            b"Opus" => "opus",
                                            b"tx3g" | b"text" => "mov_text",
                                            b"wvtt" => "webvtt",
                                            b"stpp" => "ttml",
                                            _ => "",
                                        }
                                        .to_string();
                                        if (&handler == b"vide") && epayload.len() >= 28 {
                                            let w = u16::from_be_bytes([epayload[24], epayload[25]])
                                                as u32;
                                            let h = u16::from_be_bytes([epayload[26], epayload[27]])
                                                as u32;
                                            if w > 0 && h > 0 {
                                                width = Some(w);
                                                height = Some(h);
                                            }
                                        } else if (&handler == b"soun") && epayload.len() >= 18 {
                                            let ch =
                                                u16::from_be_bytes([epayload[16], epayload[17]])
                                                    as u32;
                                            if ch > 0 && ch <= 16 {
                                                channels = Some(ch);
                                            }
                                        }
                                    });
                                }
                            });
                        }
                    });
                }
                _ => {}
            });
        }
    });

    let (stream_type, is_text_sub) = match &handler {
        b"vide" => ("Video", false),
        b"soun" => ("Audio", false),
        b"sbtl" | b"subt" | b"text" => ("Subtitle", true),
        _ => return None,
    };
    if codec.is_empty() {
        return None;
    }
    let video_range = if stream_type == "Video" {
        if header_info.dolby_vision.is_some() {
            Some("Dolby Vision".to_string())
        } else if header_info.has_hdr10_metadata {
            Some("HDR10".to_string())
        } else {
            None
        }
    } else {
        None
    };
    let display_title = compose_track_display_title(
        stream_type,
        &codec,
        lang.as_deref(),
        title.as_deref(),
        width,
        height,
        channels,
        video_range.as_deref(),
        false,
    );

    Some(InspectedTrack {
        index: 0,
        stream_type: stream_type.to_string(),
        codec,
        language: lang,
        title,
        display_title,
        is_default: stream_type != "Subtitle",
        is_forced: false,
        is_text_subtitle: is_text_sub,
        width,
        height,
        channels,
        video_range,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_dolby_vision_profile_5_7_and_8_1_dvcc() {
        // Profile 5: major=1, minor=0, profile=5 (5<<9 = 0x0A00), level=6 (6<<3 = 0x0030), rpu=1, bl=1 => 0x0A35, compat=0
        let p5 = [1u8, 0, 0x0A, 0x35, 0x00, 0, 0, 0];
        let dv5 = DolbyVisionInfo::parse_dvcc(&p5).unwrap();
        assert_eq!(dv5.dv_profile, 5);
        assert_eq!(dv5.dv_level, 6);
        assert!(dv5.rpu_present);
        assert!(!dv5.el_present);
        assert!(dv5.bl_present);
        assert!(dv5.requires_ipt_reshaping());

        // Profile 7 dual-layer: profile=7 (0x0E00), level=6 (0x0030), rpu+el+bl (0x07) => 0x0E37, compat=1 (0x10)
        let p7 = [1u8, 0, 0x0E, 0x37, 0x10, 0, 0, 0];
        let dv7 = DolbyVisionInfo::parse_dvcc(&p7).unwrap();
        assert_eq!(dv7.dv_profile, 7);
        assert!(dv7.el_present);
        assert_eq!(dv7.bl_signal_compatibility_id, 1);

        // Profile 8.1: profile=8 (0x1000), level=6 (0x0030), rpu+bl (0x05) => 0x1035, compat=1 (0x10)
        let p81 = [1u8, 0, 0x10, 0x35, 0x10, 0, 0, 0];
        let dv81 = DolbyVisionInfo::parse_dvcc(&p81).unwrap();
        assert_eq!(dv81.dv_profile, 8);
        assert_eq!(dv81.bl_signal_compatibility_id, 1);
        assert_eq!(dv81.display_label(), "Dolby Vision Profile 8.1 (HDR10)");
    }

    #[test]
    fn inspects_synthetic_mkv_with_dovi_and_truehd_atmos() {
        let mut mkv = vec![0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x00, 0x00, 0x00];
        mkv.extend_from_slice(b"V_MPEGH/ISO/HEVC");
        mkv.extend_from_slice(b"dvcC");
        mkv.extend_from_slice(&[0x41, 0xED, 0x98, 1, 0, 0x10, 0x35, 0x10, 0, 0, 0]);
        mkv.extend_from_slice(b"A_TRUEHD");

        let inspected = inspect_media_header(&mkv);
        assert_eq!(inspected.container, "matroska");
        assert!(inspected.video_codecs.contains(&"hevc".to_string()));
        assert!(inspected.audio_codecs.contains(&"truehd".to_string()));
        assert_eq!(inspected.dolby_vision.as_ref().unwrap().dv_profile, 8);
        assert_eq!(
            inspected.spatial_audio,
            Some(SpatialAudioFormat::DolbyAtmosTrueHd)
        );
    }

    #[test]
    fn inspects_synthetic_mp4_with_dovi_p5() {
        let mut mp4 = vec![0, 0, 0, 20];
        mp4.extend_from_slice(b"ftypmp42");
        mp4.extend_from_slice(b"dvh1");
        mp4.extend_from_slice(b"dvcC");
        mp4.extend_from_slice(&[1, 0, 0x0A, 0x35, 0x00, 0, 0, 0]);
        mp4.extend_from_slice(b"ec-3");

        let inspected = inspect_media_header(&mp4);
        assert_eq!(inspected.container, "mp4");
        assert_eq!(inspected.dolby_vision.as_ref().unwrap().dv_profile, 5);
        assert!(inspected
            .dolby_vision
            .as_ref()
            .unwrap()
            .requires_ipt_reshaping());
    }

    #[test]
    fn parses_ebml_mkv_tracks_with_audio_and_chinese_subtitles() {
        fn vint1(sz: usize) -> u8 {
            0x80 | (sz as u8)
        }
        fn elem(id: &[u8], payload: &[u8]) -> Vec<u8> {
            let mut out = id.to_vec();
            if payload.len() < 127 {
                out.push(vint1(payload.len()));
            } else {
                let s = (0x4000 | payload.len()) as u16;
                out.extend_from_slice(&s.to_be_bytes());
            }
            out.extend_from_slice(payload);
            out
        }

        // Track 1: Video HEVC 3840x2160
        let mut t_vid = Vec::new();
        t_vid.extend(elem(&[0xD7], &[1]));
        t_vid.extend(elem(&[0x83], &[1]));
        t_vid.extend(elem(&[0x86], b"V_MPEGH/ISO/HEVC"));
        let mut vid_sub = Vec::new();
        vid_sub.extend(elem(&[0xB0], &3840u16.to_be_bytes()));
        vid_sub.extend(elem(&[0xBA], &2160u16.to_be_bytes()));
        t_vid.extend(elem(&[0xE0], &vid_sub));

        // Track 2: Audio Mandarin EAC3 6ch
        let mut t_aud1 = Vec::new();
        t_aud1.extend(elem(&[0xD7], &[2]));
        t_aud1.extend(elem(&[0x83], &[2]));
        t_aud1.extend(elem(&[0x86], b"A_EAC3"));
        t_aud1.extend(elem(&[0x22, 0xB5, 0x9C], b"chi"));
        t_aud1.extend(elem(&[0x53, 0x6E], "国语配音".as_bytes()));
        t_aud1.extend(elem(&[0xE1], &elem(&[0x9F], &[6])));

        // Track 3: Subtitle Bilingual ASS
        let mut t_sub = Vec::new();
        t_sub.extend(elem(&[0xD7], &[3]));
        t_sub.extend(elem(&[0x83], &[17]));
        t_sub.extend(elem(&[0x86], b"S_TEXT/ASS"));
        t_sub.extend(elem(&[0x22, 0xB5, 0x9C], b"chi"));
        t_sub.extend(elem(&[0x53, 0x6E], "简英双语特效".as_bytes()));

        let mut tracks_body = Vec::new();
        tracks_body.extend(elem(&[0xAE], &t_vid));
        tracks_body.extend(elem(&[0xAE], &t_aud1));
        tracks_body.extend(elem(&[0xAE], &t_sub));

        let mut mkv = vec![0x1A, 0x45, 0xDF, 0xA3, 0x84, 0, 0, 0, 0];
        mkv.extend(elem(&[0x16, 0x54, 0xAE, 0x6B], &tracks_body));

        let parsed = inspect_media_tracks(&mkv);
        assert_eq!(parsed.len(), 3);
        assert_eq!(parsed[0].stream_type, "Video");
        assert_eq!(parsed[0].height, Some(2160));
        assert_eq!(parsed[1].stream_type, "Audio");
        assert_eq!(parsed[1].title.as_deref(), Some("国语配音"));
        assert!(parsed[1].display_title.contains("国语配音"));
        assert_eq!(parsed[2].stream_type, "Subtitle");
        assert_eq!(parsed[2].codec, "ass");
        assert!(parsed[2].display_title.contains("简英双语特效"));
    }
}
