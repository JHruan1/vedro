use prism_stream::inspector::{DolbyVisionInfo, HdrFormat};
use serde::{Deserialize, Serialize};

use crate::config::{TargetPlatform, ToneMappingAlgorithm};

/// Active video rendering pipeline chosen for a given platform + HDR/Dolby Vision stream.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VideoPipelineBackend {
    /// Universal `libmpv` + `libplacebo` (`vo=gpu-next`) with full Dolby Vision RPU
    /// IPT-PQ-C2 reshaping & dynamic HDR10/HDR10+/HLG tone-mapping on GPU (Metal/Vulkan/D3D11).
    LibmpvGpuNext,
    /// Native Apple `AVSampleBufferDisplayLayer` + `VideoToolbox` HDR/EDR Dolby Vision output
    /// (iOS/macOS displays with native DoVi/EDR panels for Profile 5 & 8.1/8.4).
    AppleNativeSampleBuffer,
    /// Native Android `MediaCodec` Dolby Vision (`video/dolby-vision`) + HDR SurfaceView.
    AndroidNativeMediaCodec,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayCapabilities {
    pub supports_hdr10: bool,
    pub supports_hlg: bool,
    pub supports_native_dolby_vision: bool,
    pub max_luminance_nits: u32,
    pub refresh_rate_hz: f32,
}

impl Default for DisplayCapabilities {
    fn default() -> Self {
        Self {
            supports_hdr10: true,
            supports_hlg: true,
            supports_native_dolby_vision: false,
            max_luminance_nits: 1000,
            refresh_rate_hz: 60.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DolbyVisionDecision {
    pub backend: VideoPipelineBackend,
    pub target_colorspace_hint: bool,
    pub hdr_compute_peak: bool,
    pub tone_mapping: ToneMappingAlgorithm,
    pub target_peak_nits: Option<u32>,
    pub requires_p7_to_p81_rpu_conversion: bool,
    pub explanation: String,
}

/// Choose the highest-fidelity Dolby Vision / HDR rendering pipeline for the current platform,
/// display hardware, and detected stream HDR format.
pub fn resolve_hdr_pipeline(
    platform: TargetPlatform,
    display: &DisplayCapabilities,
    hdr: &HdrFormat,
    prefer_native_dovi: bool,
    user_tone_mapping: ToneMappingAlgorithm,
) -> DolbyVisionDecision {
    match hdr {
        HdrFormat::DolbyVision(dv) => {
            resolve_dovi_profile(platform, display, dv, prefer_native_dovi, user_tone_mapping)
        }
        HdrFormat::Hdr10 | HdrFormat::Hdr10Plus | HdrFormat::Hlg => DolbyVisionDecision {
            backend: VideoPipelineBackend::LibmpvGpuNext,
            target_colorspace_hint: display.supports_hdr10 || display.supports_hlg,
            hdr_compute_peak: true,
            tone_mapping: user_tone_mapping,
            target_peak_nits: if display.supports_hdr10 {
                Some(display.max_luminance_nits)
            } else {
                Some(203)
            },
            requires_p7_to_p81_rpu_conversion: false,
            explanation: if display.supports_hdr10 {
                format!(
                    "HDR passthrough via libplacebo gpu-next (target-colorspace-hint=yes, peak {} nits)",
                    display.max_luminance_nits
                )
            } else {
                format!(
                    "Dynamic HDR-to-SDR tone-mapping via libplacebo ({})",
                    user_tone_mapping.mpv_value()
                )
            },
        },
        HdrFormat::Sdr => DolbyVisionDecision {
            backend: VideoPipelineBackend::LibmpvGpuNext,
            target_colorspace_hint: false,
            hdr_compute_peak: false,
            tone_mapping: user_tone_mapping,
            target_peak_nits: None,
            requires_p7_to_p81_rpu_conversion: false,
            explanation: "Standard SDR BT.709 pipeline via libmpv gpu-next".to_string(),
        },
    }
}

fn resolve_dovi_profile(
    platform: TargetPlatform,
    display: &DisplayCapabilities,
    dv: &DolbyVisionInfo,
    prefer_native_dovi: bool,
    user_tone_mapping: ToneMappingAlgorithm,
) -> DolbyVisionDecision {
    // Native Dolby Vision hardware panels (Apple XDR/iPhone OLED, Android Dolby Vision OLED/TV)
    if prefer_native_dovi && display.supports_native_dolby_vision {
        match platform {
            TargetPlatform::Ios | TargetPlatform::MacOs => {
                // Apple VideoToolbox natively decodes Profile 5 & Profile 8.1/8.4;
                // UHD BD Profile 7 requires stripping EL and converting RPU to Profile 8.1.
                let needs_p7_conv = dv.dv_profile == 7;
                return DolbyVisionDecision {
                    backend: VideoPipelineBackend::AppleNativeSampleBuffer,
                    target_colorspace_hint: true,
                    hdr_compute_peak: false,
                    tone_mapping: user_tone_mapping,
                    target_peak_nits: Some(display.max_luminance_nits),
                    requires_p7_to_p81_rpu_conversion: needs_p7_conv,
                    explanation: format!(
                        "Apple native AVSampleBufferDisplayLayer EDR Dolby Vision ({}{})",
                        dv.display_label(),
                        if needs_p7_conv {
                            ", real-time P7→P8.1 RPU conversion"
                        } else {
                            ""
                        }
                    ),
                };
            }
            TargetPlatform::Android => {
                let needs_p7_conv = dv.dv_profile == 7;
                return DolbyVisionDecision {
                    backend: VideoPipelineBackend::AndroidNativeMediaCodec,
                    target_colorspace_hint: true,
                    hdr_compute_peak: false,
                    tone_mapping: user_tone_mapping,
                    target_peak_nits: Some(display.max_luminance_nits),
                    requires_p7_to_p81_rpu_conversion: needs_p7_conv,
                    explanation: format!(
                        "Android native MediaCodec video/dolby-vision Surface ({})",
                        dv.display_label()
                    ),
                };
            }
            _ => {}
        }
    }

    // Universal libmpv + libplacebo gpu-next Dolby Vision RPU pipeline:
    // Handles Profile 5 IPT-PQ-C2 reshaping (NO green/purple tint!), Profile 7 RPU,
    // and Profile 8.1/8.4 across Windows, macOS, iOS, Android, and Linux!
    DolbyVisionDecision {
        backend: VideoPipelineBackend::LibmpvGpuNext,
        target_colorspace_hint: display.supports_hdr10,
        hdr_compute_peak: true,
        tone_mapping: user_tone_mapping,
        target_peak_nits: if display.supports_hdr10 {
            Some(display.max_luminance_nits)
        } else {
            Some(203)
        },
        requires_p7_to_p81_rpu_conversion: false,
        explanation: format!(
            "libplacebo gpu-next Dolby Vision RPU engine ({}, {} output)",
            dv.display_label(),
            if display.supports_hdr10 {
                "HDR PQ"
            } else {
                "SDR tone-mapped"
            }
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn routes_dovi_profile_5_safely_on_sdr_and_hdr_displays() {
        let dv5 = DolbyVisionInfo {
            dv_version_major: 1,
            dv_version_minor: 0,
            dv_profile: 5,
            dv_level: 6,
            rpu_present: true,
            el_present: false,
            bl_present: true,
            bl_signal_compatibility_id: 0,
        };
        let sdr = DisplayCapabilities {
            supports_hdr10: false,
            supports_hlg: false,
            supports_native_dolby_vision: false,
            max_luminance_nits: 300,
            refresh_rate_hz: 60.0,
        };
        let dec = resolve_hdr_pipeline(
            TargetPlatform::Windows,
            &sdr,
            &HdrFormat::DolbyVision(dv5.clone()),
            true,
            ToneMappingAlgorithm::Bt2446a,
        );
        assert_eq!(dec.backend, VideoPipelineBackend::LibmpvGpuNext);
        assert!(!dec.target_colorspace_hint);
        assert!(dec.hdr_compute_peak);

        let apple_xdr = DisplayCapabilities {
            supports_hdr10: true,
            supports_hlg: true,
            supports_native_dolby_vision: true,
            max_luminance_nits: 1600,
            refresh_rate_hz: 120.0,
        };
        let dec_ios = resolve_hdr_pipeline(
            TargetPlatform::Ios,
            &apple_xdr,
            &HdrFormat::DolbyVision(dv5),
            true,
            ToneMappingAlgorithm::Spline,
        );
        assert_eq!(
            dec_ios.backend,
            VideoPipelineBackend::AppleNativeSampleBuffer
        );
    }
}
