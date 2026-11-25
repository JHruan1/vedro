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
}
