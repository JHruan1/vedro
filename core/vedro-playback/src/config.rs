use serde::{Deserialize, Serialize};
use vedro_stream::inspector::{HdrFormat, SpatialAudioFormat};

use crate::atmos::resolve_audio_routing;
use crate::dovi::{resolve_hdr_pipeline, DisplayCapabilities};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TargetPlatform {
    Android,
    Ios,
    MacOs,
    Windows,
    Linux,
}

impl TargetPlatform {
    pub fn current() -> Self {
        match std::env::consts::OS {
            "android" => Self::Android,
            "ios" => Self::Ios,
            "macos" => Self::MacOs,
            "windows" => Self::Windows,
            _ => Self::Linux,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum HardwareDecodeMode {
    /// Zero-copy platform-optimal hardware decoding (`videotoolbox`, `d3d11va`, `mediacodec`, `vaapi`).
    #[default]
    AutoZeroCopy,
    /// Copy-back hardware decoding (enables CPU filters like deinterlace/svp while still using HW decode).
    AutoCopy,
    /// Pure software multi-threaded FFmpeg decoding.
    Software,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ToneMappingAlgorithm {
    #[default]
    Bt2446a,
    Spline,
    St2094_40,
    Reinhard,
    Hable,
    Clip,
}

impl ToneMappingAlgorithm {
    pub fn mpv_value(&self) -> &'static str {
        match self {
            Self::Bt2446a => "bt.2446a",
            Self::Spline => "spline",
            Self::St2094_40 => "st2094-40",
            Self::Reinhard => "reinhard",
            Self::Hable => "hable",
            Self::Clip => "clip",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum AudioOutputMode {
    #[default]
    Auto,
    PassthroughBitstream,
    SpatialAudio,
    HeadphoneBinaural,
    PcmStereo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ShaderPreset {
    #[default]
    None,
    Deband,
    Anime4kFast,
    Anime4kQuality,
    FsrcnnxSharpen,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlaybackConfig {
    pub platform: TargetPlatform,
    pub hwdec: HardwareDecodeMode,
    pub prefer_native_dolby_vision: bool,
    pub tone_mapping: ToneMappingAlgorithm,
    pub audio_mode: AudioOutputMode,
    pub night_mode: bool,
    pub dialogue_boost: bool,
    pub shader_preset: ShaderPreset,
    pub display: DisplayCapabilities,
    pub demuxer_cache_mb: u32,
    pub deband: bool,
    pub frame_interpolation: bool,
    pub subtitle_font_size: u32,
    pub subtitle_scale: f32,
    pub preferred_audio_langs: Vec<String>,
    pub preferred_subtitle_langs: Vec<String>,
    pub headless_null_vo: bool,
}

impl Default for PlaybackConfig {
    fn default() -> Self {
        Self {
            platform: TargetPlatform::current(),
            hwdec: HardwareDecodeMode::AutoZeroCopy,
            prefer_native_dolby_vision: true,
            tone_mapping: ToneMappingAlgorithm::Bt2446a,
            audio_mode: AudioOutputMode::Auto,
            night_mode: false,
            dialogue_boost: false,
            shader_preset: ShaderPreset::None,
            display: DisplayCapabilities::default(),
            demuxer_cache_mb: 128,
            deband: false,
            frame_interpolation: false,
            subtitle_font_size: 46,
            subtitle_scale: 1.0,
            preferred_audio_langs: vec![
                "chi".into(),
                "zho".into(),
                "zh".into(),
                "eng".into(),
                "jpn".into(),
            ],
            preferred_subtitle_langs: vec![
                "chi".into(),
                "zho".into(),
                "zh".into(),
                "chs".into(),
                "cht".into(),
                "eng".into(),
            ],
            headless_null_vo: false,
        }
    }
}

impl PlaybackConfig {
    /// Generate the exact `libmpv` + `libplacebo` option table tuned for the platform,
    /// hardware decoder, Dolby Vision profile, HDR display, and Dolby Atmos routing.
    pub fn build_mpv_options(
        &self,
        hdr: &HdrFormat,
        spatial_audio: Option<&SpatialAudioFormat>,
    ) -> Vec<(String, String)> {
        let mut opts: Vec<(String, String)> = Vec::new();
        let mut set = |k: &str, v: &str| opts.push((k.to_string(), v.to_string()));

        // 1. Video Output & GPU Renderer (libplacebo gpu-next for true DoVi RPU + HDR10+)
        if self.headless_null_vo {
            set("vo", "null");
            set("ao", "null");
        } else {
            set("vo", "gpu-next");
            match self.platform {
                TargetPlatform::Windows => {
                    set("gpu-api", "d3d11");
                    set(
                        "d3d11-output-csp",
                        if self.display.supports_hdr10 {
                            "pq"
                        } else {
                            "auto"
                        },
                    );
                }
                TargetPlatform::MacOs => {
                    set("gpu-api", "vulkan");
                    set("gpu-context", "macvk");
                }
                TargetPlatform::Ios => {
                    set("gpu-api", "vulkan");
                }
                TargetPlatform::Android => {
                    set("gpu-api", "vulkan");
                    set("gpu-context", "android");
                }
                TargetPlatform::Linux => {
                    set("gpu-api", "vulkan");
                }
            }
        }

        // 2. Best-in-class Hardware Decoding per platform
        let hwdec_val = match (self.platform, self.hwdec) {
            (_, HardwareDecodeMode::Software) => "no",
            (TargetPlatform::Ios | TargetPlatform::MacOs, HardwareDecodeMode::AutoZeroCopy) => {
                "videotoolbox"
            }
            (TargetPlatform::Ios | TargetPlatform::MacOs, HardwareDecodeMode::AutoCopy) => {
                "videotoolbox-copy"
            }
            (TargetPlatform::Windows, HardwareDecodeMode::AutoZeroCopy) => {
                "d3d11va,nvdec,auto-safe"
            }
            (TargetPlatform::Windows, HardwareDecodeMode::AutoCopy) => {
                "d3d11va-copy,nvdec-copy,auto-copy"
            }
            (TargetPlatform::Android, HardwareDecodeMode::AutoZeroCopy) => "mediacodec",
            (TargetPlatform::Android, HardwareDecodeMode::AutoCopy) => "mediacodec-copy",
            (TargetPlatform::Linux, HardwareDecodeMode::AutoZeroCopy) => {
                "vaapi,vulkan,nvdec,auto-safe"
            }
            (TargetPlatform::Linux, HardwareDecodeMode::AutoCopy) => "vaapi-copy,auto-copy",
        };
        set("hwdec", hwdec_val);
        set("hwdec-codecs", "all");
        let is_mobile = matches!(self.platform, TargetPlatform::Android | TargetPlatform::Ios);
        if is_mobile {
            set("vd-lavc-threads", "4");
        }
        set("framedrop", "vo");
        set("gpu-shader-cache", "yes");
        set("volume-max", "150");

        // 3. Dolby Vision RPU & HDR10/HDR10+/HLG Pipeline
        let hdr_decision = resolve_hdr_pipeline(
            self.platform,
            &self.display,
            hdr,
            self.prefer_native_dolby_vision,
            self.tone_mapping,
        );
        set(
            "target-colorspace-hint",
            if hdr_decision.target_colorspace_hint {
                "yes"
            } else {
                "no"
            },
        );
        // On mobile SoCs, per-frame 4K compute-shader peak detection (`hdr-compute-peak=yes`)
        // drives heavy GPU heat & battery drain; rely on static/dynamic metadata on phones.
        set(
            "hdr-compute-peak",
            if hdr_decision.hdr_compute_peak && !is_mobile {
                "yes"
            } else {
                "no"
            },
        );
        set("tone-mapping", hdr_decision.tone_mapping.mpv_value());
        set("gamut-mapping-mode", "perceptual");
        if let Some(peak) = hdr_decision.target_peak_nits {
            set("target-peak", &peak.to_string());
        }

        // 4. Dolby Atmos / DTS:X / Spatial Audio Pipeline
        if !self.headless_null_vo {
            let audio_decision = resolve_audio_routing(
                self.platform,
                self.audio_mode,
                spatial_audio,
                self.night_mode,
                self.dialogue_boost,
            );
            set("ao", &audio_decision.mpv_ao);
            if !audio_decision.audio_spdif.is_empty() {
                set("audio-spdif", &audio_decision.audio_spdif);
            }
            set(
                "audio-exclusive",
                if audio_decision.audio_exclusive {
                    "yes"
                } else {
                    "no"
                },
            );
            set("audio-channels", &audio_decision.audio_channels);
            set("audio-normalize-downmix", "yes");
            if let Some(af) = audio_decision.audio_filter {
                set("af", &af);
            }
        }

        // 5. High-quality video processing & sync (thermally tuned on mobile!)
        if is_mobile && !self.frame_interpolation {
            set("video-sync", "audio");
            if self.shader_preset == ShaderPreset::None && !self.deband {
                set("scale", "bilinear");
                set("cscale", "bilinear");
                set("dscale", "bilinear");
                set("dither-depth", "no");
            }
        } else {
            set("video-sync", "display-resample");
        }
        if self.frame_interpolation {
            set("interpolation", "yes");
            set("tscale", "oversample");
        }
        if self.deband || self.shader_preset == ShaderPreset::Deband {
            set("deband", "yes");
            set("deband-iterations", "2");
            set("deband-threshold", "35");
        }

        // 6. Subtitles (libass full ASS/SSA anime rendering + crisp SRT/VTT)
        set("sub-auto", "no");
        set("sub-ass-override", "no");
        set("sub-font-size", &self.subtitle_font_size.to_string());
        let safe_sub_scale = if self.subtitle_scale.is_finite() {
            self.subtitle_scale.clamp(0.4, 3.0)
        } else {
            1.0
        };
        set("sub-scale", &format!("{safe_sub_scale:.2}"));
        set("blend-subtitles", "no");

        if !self.preferred_audio_langs.is_empty() {
            set("alang", &self.preferred_audio_langs.join(","));
        }
        if !self.preferred_subtitle_langs.is_empty() {
            set("slang", &self.preferred_subtitle_langs.join(","));
        }

        // 7. Streaming demuxer cache tuned for 4K Remuxes (leaner RAM/wakeups on mobile)
        let max_mb = if is_mobile {
            self.demuxer_cache_mb.clamp(32, 96)
        } else {
            self.demuxer_cache_mb.clamp(32, 512)
        };
        let cache_bytes = (max_mb as u64) * 1024 * 1024;
        set("cache", "yes");
        set("demuxer-max-bytes", &cache_bytes.to_string());
        set("demuxer-max-back-bytes", &(cache_bytes / 4).to_string());
        set(
            "demuxer-readahead-secs",
            if is_mobile { "12" } else { "20" },
        );
        set("network-timeout", "30");
        set("keep-open", "yes");

        opts
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use vedro_stream::inspector::DolbyVisionInfo;

    #[test]
    fn builds_platform_specific_hwdec_dovi_and_atmos_options() {
        let cfg = PlaybackConfig {
            platform: TargetPlatform::Windows,
            audio_mode: AudioOutputMode::PassthroughBitstream,
            ..Default::default()
        };
        let dv = DolbyVisionInfo {
            dv_version_major: 1,
            dv_version_minor: 0,
            dv_profile: 8,
            dv_level: 6,
            rpu_present: true,
            el_present: false,
            bl_present: true,
            bl_signal_compatibility_id: 1,
        };
        let opts = cfg.build_mpv_options(
            &HdrFormat::DolbyVision(dv),
            Some(&SpatialAudioFormat::DolbyAtmosTrueHd),
        );
        let find = |k: &str| {
            opts.iter()
                .find(|(key, _)| key == k)
                .map(|(_, v)| v.as_str())
        };
        assert_eq!(find("vo"), Some("gpu-next"));
        assert_eq!(find("gpu-api"), Some("d3d11"));
        assert_eq!(find("hwdec"), Some("d3d11va,nvdec,auto-safe"));
        assert_eq!(find("target-colorspace-hint"), Some("yes"));
        assert_eq!(find("ao"), Some("wasapi"));
        assert_eq!(find("audio-exclusive"), Some("yes"));
        assert!(find("audio-spdif").unwrap().contains("truehd"));
    }

    #[test]
    fn tunes_mobile_mpv_pipeline_for_low_heat_and_power() {
        let cfg = PlaybackConfig {
            platform: TargetPlatform::Android,
            demuxer_cache_mb: 256,
            ..Default::default()
        };
        let opts = cfg.build_mpv_options(&HdrFormat::Hdr10, None);
        let find = |k: &str| {
            opts.iter()
                .find(|(key, _)| key == k)
                .map(|(_, v)| v.as_str())
        };
        assert_eq!(find("hwdec"), Some("mediacodec"));
        assert_eq!(find("video-sync"), Some("audio"));
        assert_eq!(find("hdr-compute-peak"), Some("no"));
        assert_eq!(find("scale"), Some("bilinear"));
        assert_eq!(find("dither-depth"), Some("no"));
        assert_eq!(find("demuxer-readahead-secs"), Some("12"));
        assert_eq!(
            find("demuxer-max-bytes"),
            Some((96u64 * 1024 * 1024).to_string().as_str())
        );
    }
}
