use serde::{Deserialize, Serialize};
use vedro_stream::inspector::SpatialAudioFormat;

use crate::config::{AudioOutputMode, TargetPlatform};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioRoutingDecision {
    /// libmpv `ao` driver (e.g. `wasapi`, `coreaudio`, `audiotrack`, `pipewire`).
    pub mpv_ao: String,
    /// `audio-spdif` codec list for IEC61937 bitstream passthrough (TrueHD Atmos, E-AC-3 JOC, DTS:X).
    pub audio_spdif: String,
    /// Exclusive audio mode (WASAPI Exclusive / CoreAudio Hog mode for bit-perfect Atmos).
    pub audio_exclusive: bool,
    /// Channel layout string (`auto-safe`, `stereo`, `7.1`, etc.).
    pub audio_channels: String,
    /// Optional libavfilter chain for headphone spatialization / night mode / dialogue boost.
    pub audio_filter: Option<String>,
    /// Whether Apple AVAudioSession / Android Spatializer native OS Atmos decoding should be engaged.
    pub use_os_spatial_audio: bool,
    pub summary: String,
}

/// Compute the optimal Dolby Atmos / DTS:X / lossless audio routing for the target platform.
pub fn resolve_audio_routing(
    platform: TargetPlatform,
    mode: AudioOutputMode,
    detected: Option<&SpatialAudioFormat>,
    night_mode: bool,
    dialogue_boost: bool,
) -> AudioRoutingDecision {
    let mpv_ao = match platform {
        TargetPlatform::Windows => "wasapi",
        TargetPlatform::MacOs => "coreaudio",
        TargetPlatform::Ios => "audiounit",
        TargetPlatform::Android => "audiotrack",
        TargetPlatform::Linux => "pipewire,pulse,alsa",
    }
    .to_string();

    match mode {
        AudioOutputMode::PassthroughBitstream => {
            let spdif = match platform {
                TargetPlatform::Windows | TargetPlatform::Android | TargetPlatform::Linux => {
                    "ac3,eac3,dts,dts-hd,truehd"
                }
                // macOS CoreAudio supports AC-3 / E-AC-3 / DTS over optical/HDMI; TrueHD requires LPCM or Apple Spatial Audio
                TargetPlatform::MacOs => "ac3,eac3,dts",
                TargetPlatform::Ios => "",
            };
            let exclusive = matches!(platform, TargetPlatform::Windows | TargetPlatform::MacOs);
            AudioRoutingDecision {
                mpv_ao,
                audio_spdif: spdif.to_string(),
                audio_exclusive: exclusive,
                audio_channels: "auto-safe".to_string(),
                audio_filter: None,
                use_os_spatial_audio: false,
                summary: format!(
                    "Bitstream Passthrough ({}) — {:?}",
                    if spdif.is_empty() { "LPCM" } else { spdif },
                    detected.unwrap_or(&SpatialAudioFormat::None)
                ),
            }
        }
        AudioOutputMode::SpatialAudio => {
            let os_spatial = matches!(
                platform,
                TargetPlatform::Ios | TargetPlatform::MacOs | TargetPlatform::Android
            );
            AudioRoutingDecision {
                mpv_ao,
                audio_spdif: String::new(),
                audio_exclusive: false,
                audio_channels: "auto-safe".to_string(),
                audio_filter: build_software_audio_filter(false, night_mode, dialogue_boost),
                use_os_spatial_audio: os_spatial,
                summary: if os_spatial {
                    "OS Native Spatial Audio (Dolby Atmos E-AC-3 JOC / Multichannel)".to_string()
                } else {
                    "Multichannel PCM Spatial Decode".to_string()
                },
            }
        }
        AudioOutputMode::Auto => {
            let is_atmos = matches!(
                detected,
                Some(SpatialAudioFormat::DolbyAtmosTrueHd | SpatialAudioFormat::DolbyAtmosEac3Joc)
            );
            match platform {
                TargetPlatform::Windows => AudioRoutingDecision {
                    mpv_ao,
                    audio_spdif: "ac3,eac3,dts,dts-hd,truehd".to_string(),
                    audio_exclusive: false,
                    audio_channels: "auto-safe".to_string(),
                    audio_filter: None,
                    use_os_spatial_audio: false,
                    summary: if is_atmos {
                        "Windows WASAPI Auto (Atmos Bitstream/PCM)".to_string()
                    } else {
                        "Windows WASAPI Auto".to_string()
                    },
                },
                TargetPlatform::Android => AudioRoutingDecision {
                    mpv_ao,
                    audio_spdif: "ac3,eac3,dts,dts-hd,truehd".to_string(),
                    audio_exclusive: false,
                    audio_channels: "auto-safe".to_string(),
                    audio_filter: None,
                    use_os_spatial_audio: true,
                    summary: "Android AudioTrack IEC61937 Atmos + Spatializer".to_string(),
                },
                TargetPlatform::Ios | TargetPlatform::MacOs => AudioRoutingDecision {
                    mpv_ao,
                    audio_spdif: String::new(),
                    audio_exclusive: false,
                    audio_channels: "auto-safe".to_string(),
                    audio_filter: build_software_audio_filter(false, night_mode, dialogue_boost),
                    use_os_spatial_audio: true,
                    summary: "Apple CoreAudio + Spatial Audio Atmos".to_string(),
                },
                TargetPlatform::Linux => AudioRoutingDecision {
                    mpv_ao,
                    audio_spdif: String::new(),
                    audio_exclusive: false,
                    audio_channels: "auto-safe".to_string(),
                    audio_filter: build_software_audio_filter(false, night_mode, dialogue_boost),
                    use_os_spatial_audio: false,
                    summary: "PipeWire/ALSA 32-bit Float PCM".to_string(),
                },
            }
        }
        AudioOutputMode::HeadphoneBinaural => AudioRoutingDecision {
            mpv_ao,
            audio_spdif: String::new(),
            audio_exclusive: false,
            audio_channels: "stereo".to_string(),
            audio_filter: build_software_audio_filter(true, night_mode, dialogue_boost),
            use_os_spatial_audio: false,
            summary: "Headphone Binaural / Crossfeed + LFE Downmix".to_string(),
        },
        AudioOutputMode::PcmStereo => AudioRoutingDecision {
            mpv_ao,
            audio_spdif: String::new(),
            audio_exclusive: false,
            audio_channels: "stereo".to_string(),
            audio_filter: build_software_audio_filter(false, night_mode, dialogue_boost),
            use_os_spatial_audio: false,
            summary: "Audiophile 32-bit Float Stereo PCM".to_string(),
        },
    }
}

fn build_software_audio_filter(
    binaural: bool,
    night_mode: bool,
    dialogue_boost: bool,
) -> Option<String> {
    let mut filters = Vec::new();
    if binaural {
        // Bauer stereophonic-to-binaural DSP for comfortable headphone spatial imaging
        filters.push("lavfi=[bs2b=fcut=700:feed=45]".to_string());
    }
    if dialogue_boost {
        // Gentle presence boost around human vocal band (1kHz–3.5kHz)
        filters.push("lavfi=[equalizer=f=2200:t=q:w=1.2:g=4.0]".to_string());
    }
    if night_mode {
        // Dynamic range compression so late-night Atmos explosions don't overwhelm dialogue
        filters.push(
            "lavfi=[acompressor=threshold=-20dB:ratio=4:attack=10:release=150:makeup=4dB]"
                .to_string(),
        );
    }
    if filters.is_empty() {
        None
    } else {
        Some(filters.join(","))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_wasapi_exclusive_atmos_bitstream_on_windows() {
        let dec = resolve_audio_routing(
            TargetPlatform::Windows,
            AudioOutputMode::PassthroughBitstream,
            Some(&SpatialAudioFormat::DolbyAtmosTrueHd),
            false,
            false,
        );
        assert_eq!(dec.mpv_ao, "wasapi");
        assert!(dec.audio_exclusive);
        assert!(dec.audio_spdif.contains("truehd"));
        assert!(dec.audio_spdif.contains("eac3"));
    }

    #[test]
    fn generates_apple_spatial_audio_on_ios_and_macos() {
        let dec = resolve_audio_routing(
            TargetPlatform::Ios,
            AudioOutputMode::Auto,
            Some(&SpatialAudioFormat::DolbyAtmosEac3Joc),
            true,
            true,
        );
        assert!(dec.use_os_spatial_audio);
        assert!(dec.audio_filter.as_deref().unwrap().contains("acompressor"));
        assert!(dec.audio_filter.as_deref().unwrap().contains("equalizer"));
    }
}
