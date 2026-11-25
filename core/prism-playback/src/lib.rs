pub mod atmos;
pub mod config;
pub mod dovi;
pub mod engine;
pub mod mpv_sys;

pub use atmos::{resolve_audio_routing, AudioRoutingDecision};
pub use config::{
    AudioOutputMode, HardwareDecodeMode, PlaybackConfig, ShaderPreset, TargetPlatform,
    ToneMappingAlgorithm,
};
pub use dovi::{
    resolve_hdr_pipeline, DisplayCapabilities, DolbyVisionDecision, VideoPipelineBackend,
};
pub use engine::{PlaybackEngine, PlaybackError, PlaybackStats, TrackDescriptor};
