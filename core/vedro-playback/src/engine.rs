use std::sync::Arc;

use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tracing::{debug, info, warn};
use vedro_stream::inspector::{HdrFormat, InspectedMedia};

use crate::atmos::{resolve_audio_routing, AudioRoutingDecision};
use crate::config::{AudioOutputMode, PlaybackConfig, ToneMappingAlgorithm};
use crate::dovi::{resolve_hdr_pipeline, DolbyVisionDecision};
use crate::mpv_sys::{LibMpv, MpvHandle};

#[derive(Debug, Error)]
pub enum PlaybackError {
    #[error("libmpv is unavailable on this host: {0}")]
    BackendUnavailable(String),

    #[error("libmpv initialization failed (code {0})")]
    InitFailed(i32),

    #[error("playback command failed: {0}")]
    CommandFailed(String),
}

pub type Result<T> = std::result::Result<T, PlaybackError>;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TrackDescriptor {
    pub id: i64,
    pub track_type: String,
    pub codec: Option<String>,
    pub lang: Option<String>,
    pub title: Option<String>,
    pub selected: bool,
    pub external: bool,
}

/// Real-time playback & hardware decoding telemetry for the Nerd Stats HUD (`I`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PlaybackStats {
    pub backend_active: bool,
    pub libmpv_api_version: String,
    pub paused: bool,
    pub position_secs: f64,
    pub duration_secs: f64,
    pub speed: f64,
    pub volume: f64,
    pub video_codec: Option<String>,
    pub hwdec_current: Option<String>,
    pub width: Option<i64>,
    pub height: Option<i64>,
    pub fps: Option<f64>,
    pub dropped_frames: i64,
    pub video_primaries: Option<String>,
    pub video_gamma: Option<String>,
    pub audio_codec: Option<String>,
    pub audio_channels: Option<String>,
    pub audio_sample_rate: Option<i64>,
    pub audio_delay_secs: f64,
    pub sub_delay_secs: f64,
    pub cache_duration_secs: Option<f64>,
    pub hdr_decision: Option<DolbyVisionDecision>,
    pub audio_decision: Option<AudioRoutingDecision>,
}

struct MpvInstance {
    lib: LibMpv,
    handle: *mut MpvHandle,
}

unsafe impl Send for MpvInstance {}

impl Drop for MpvInstance {
    fn drop(&mut self) {
        self.lib.terminate_destroy(self.handle);
    }
}

/// Thread-safe cross-platform hardware playback controller backed by `libmpv` + `libplacebo`.
pub struct PlaybackEngine {
    config: Mutex<PlaybackConfig>,
    mpv: Mutex<Option<MpvInstance>>,
    last_hdr: Mutex<Option<DolbyVisionDecision>>,
    last_audio: Mutex<Option<AudioRoutingDecision>>,
}

impl PlaybackEngine {
    /// Initialize a new `PlaybackEngine` with the given `PlaybackConfig`.
    /// Uses real `libmpv` when available on the host.
    pub fn new(config: PlaybackConfig) -> Result<Arc<Self>> {
        let lib = LibMpv::load().map_err(PlaybackError::BackendUnavailable)?;
        let handle = lib.create_handle().ok_or(PlaybackError::InitFailed(-1))?;

        let init_opts = config.build_mpv_options(&HdrFormat::Sdr, None);
        for (k, v) in &init_opts {
            if let Err(rc) = lib.set_option_string(handle, k, v) {
                // Non-fatal: some options (e.g. d3d11/macvk/gpu-next) depend on host libmpv build
                debug!(option = %k, value = %v, rc, "skipping unsupported libmpv option");
            }
        }
        lib.initialize(handle).map_err(PlaybackError::InitFailed)?;
        let (maj, min) = lib.api_version();
        info!(api_version = %format!("{maj}.{min}"), "initialized libmpv playback engine");

        Ok(Arc::new(Self {
            config: Mutex::new(config),
            mpv: Mutex::new(Some(MpvInstance { lib, handle })),
            last_hdr: Mutex::new(None),
            last_audio: Mutex::new(None),
        }))
    }

    /// Attach a platform native window handle (`wid`: `HWND`, `NSView*`, `UIView*`, `ANativeWindow*`, X11 window ID).
    pub fn attach_window_id(&self, wid: i64) -> Result<()> {
        self.set_property("wid", &wid.to_string())
    }

    /// Load a media URL (typically the local `vedro-stream` proxy URL) and apply optimal
    /// Dolby Vision / HDR and Dolby Atmos routing based on `inspected` stream metadata.
    pub fn load_media(
        &self,
        url: &str,
        start_secs: Option<f64>,
        inspected: Option<&InspectedMedia>,
    ) -> Result<(DolbyVisionDecision, AudioRoutingDecision)> {
        let cfg = self.config.lock().clone();
        let hdr = inspected
            .and_then(|i| i.hdr_format.clone())
            .unwrap_or(HdrFormat::Sdr);
        let spatial = inspected.and_then(|i| i.spatial_audio.clone());

        let hdr_decision = resolve_hdr_pipeline(
            cfg.platform,
            &cfg.display,
            &hdr,
            cfg.prefer_native_dolby_vision,
            cfg.tone_mapping,
        );
        let audio_decision = resolve_audio_routing(
            cfg.platform,
            cfg.audio_mode,
            spatial.as_ref(),
            cfg.night_mode,
            cfg.dialogue_boost,
        );

        // Apply dynamic HDR/DoVi & Atmos properties before loading
        let _ = self.set_property(
            "target-colorspace-hint",
            if hdr_decision.target_colorspace_hint {
                "yes"
            } else {
                "no"
            },
        );
        let _ = self.set_property(
            "hdr-compute-peak",
            if hdr_decision.hdr_compute_peak {
                "yes"
            } else {
                "no"
            },
        );
        let _ = self.set_property("tone-mapping", hdr_decision.tone_mapping.mpv_value());
        if !cfg.headless_null_vo {
            if !audio_decision.audio_spdif.is_empty() {
                let _ = self.set_property("audio-spdif", &audio_decision.audio_spdif);
            }
            if let Some(af) = &audio_decision.audio_filter {
                let _ = self.set_property("af", af);
            } else {
                let _ = self.set_property("af", "");
            }
        }

        if let Some(start) = start_secs.filter(|s| *s > 1.0) {
            let _ = self.set_property("start", &format!("{start:.2}"));
        } else {
            let _ = self.set_property("start", "none");
        }

        self.run_command(&["loadfile", url, "replace"])?;
        *self.last_hdr.lock() = Some(hdr_decision.clone());
        *self.last_audio.lock() = Some(audio_decision.clone());
        Ok((hdr_decision, audio_decision))
    }

    pub fn set_paused(&self, paused: bool) -> Result<()> {
        self.set_property("pause", if paused { "yes" } else { "no" })
    }

    pub fn toggle_pause(&self) -> Result<()> {
        self.run_command(&["cycle", "pause"])
    }

    pub fn seek_absolute(&self, seconds: f64) -> Result<()> {
        self.run_command(&["seek", &format!("{:.3}", seconds.max(0.0)), "absolute"])
    }

    pub fn seek_relative(&self, delta_seconds: f64) -> Result<()> {
        self.run_command(&["seek", &format!("{delta_seconds:.3}"), "relative"])
    }

    pub fn set_speed(&self, speed: f64) -> Result<()> {
        let clamped = speed.clamp(0.25, 4.0);
        self.set_property("speed", &format!("{clamped:.2}"))
    }

    pub fn set_volume(&self, volume: f64) -> Result<()> {
        let clamped = volume.clamp(0.0, 150.0);
        self.set_property("volume", &format!("{clamped:.1}"))
    }

    pub fn set_audio_track(&self, track_id: i64) -> Result<()> {
        if track_id <= 0 {
            self.set_property("aid", "no")
        } else {
            self.set_property("aid", &track_id.to_string())
        }
    }

    pub fn set_subtitle_track(&self, track_id: i64) -> Result<()> {
        if track_id <= 0 {
            self.set_property("sid", "no")
        } else {
            self.set_property("sid", &track_id.to_string())
        }
    }

    pub fn add_external_subtitle(
        &self,
        url_or_path: &str,
        title: Option<&str>,
        lang: Option<&str>,
    ) -> Result<()> {
        let mut args = vec!["sub-add", url_or_path, "select"];
        let t_str;
        let l_str;
        if let Some(t) = title {
            t_str = t.to_string();
            args.push(&t_str);
            if let Some(l) = lang {
                l_str = l.to_string();
                args.push(&l_str);
            }
        }
        self.run_command(&args)
    }

    pub fn set_subtitle_delay(&self, delay_secs: f64) -> Result<()> {
        self.set_property("sub-delay", &format!("{delay_secs:.3}"))
    }

    pub fn set_audio_delay(&self, delay_secs: f64) -> Result<()> {
        self.set_property("audio-delay", &format!("{delay_secs:.3}"))
    }

    pub fn set_tone_mapping(&self, algo: ToneMappingAlgorithm) -> Result<()> {
        self.config.lock().tone_mapping = algo;
        self.set_property("tone-mapping", algo.mpv_value())
    }

    pub fn set_audio_mode(
        &self,
        mode: AudioOutputMode,
        night_mode: bool,
        dialogue_boost: bool,
    ) -> Result<AudioRoutingDecision> {
        let platform = {
            let mut cfg = self.config.lock();
            cfg.audio_mode = mode;
            cfg.night_mode = night_mode;
            cfg.dialogue_boost = dialogue_boost;
            cfg.platform
        };
        let dec = resolve_audio_routing(platform, mode, None, night_mode, dialogue_boost);
        let _ = self.set_property("audio-spdif", &dec.audio_spdif);
        let _ = self.set_property("audio-channels", &dec.audio_channels);
        let _ = self.set_property("af", dec.audio_filter.as_deref().unwrap_or(""));
        *self.last_audio.lock() = Some(dec.clone());
        Ok(dec)
    }

    pub fn stop(&self) -> Result<()> {
        self.run_command(&["stop"])
    }

    pub fn poll_events(&self) -> Vec<i32> {
        let guard = self.mpv.lock();
        match guard.as_ref() {
            Some(inst) => inst.lib.drain_events(inst.handle),
            None => Vec::new(),
        }
    }

    pub fn stats_snapshot(&self) -> PlaybackStats {
        let guard = self.mpv.lock();
        let Some(inst) = guard.as_ref() else {
            return PlaybackStats::default();
        };
        let (maj, min) = inst.lib.api_version();
        PlaybackStats {
            backend_active: true,
            libmpv_api_version: format!("{maj}.{min}"),
            paused: inst
                .lib
                .get_property_bool(inst.handle, "pause")
                .unwrap_or(true),
            position_secs: inst
                .lib
                .get_property_f64(inst.handle, "time-pos")
                .unwrap_or(0.0),
            duration_secs: inst
                .lib
                .get_property_f64(inst.handle, "duration")
                .unwrap_or(0.0),
            speed: inst
                .lib
                .get_property_f64(inst.handle, "speed")
                .unwrap_or(1.0),
            volume: inst
                .lib
                .get_property_f64(inst.handle, "volume")
                .unwrap_or(100.0),
            video_codec: inst.lib.get_property_string(inst.handle, "video-codec"),
            hwdec_current: inst.lib.get_property_string(inst.handle, "hwdec-current"),
            width: inst.lib.get_property_i64(inst.handle, "width"),
            height: inst.lib.get_property_i64(inst.handle, "height"),
            fps: inst.lib.get_property_f64(inst.handle, "estimated-vf-fps"),
            dropped_frames: inst
                .lib
                .get_property_i64(inst.handle, "frame-drop-count")
                .unwrap_or(0),
            video_primaries: inst
                .lib
                .get_property_string(inst.handle, "video-params/primaries"),
            video_gamma: inst
                .lib
                .get_property_string(inst.handle, "video-params/gamma"),
            audio_codec: inst
                .lib
                .get_property_string(inst.handle, "audio-codec-name"),
            audio_channels: inst
                .lib
                .get_property_string(inst.handle, "audio-params/channels"),
            audio_sample_rate: inst
                .lib
                .get_property_i64(inst.handle, "audio-params/samplerate"),
            audio_delay_secs: inst
                .lib
                .get_property_f64(inst.handle, "audio-delay")
                .unwrap_or(0.0),
            sub_delay_secs: inst
                .lib
                .get_property_f64(inst.handle, "sub-delay")
                .unwrap_or(0.0),
            cache_duration_secs: inst
                .lib
                .get_property_f64(inst.handle, "demuxer-cache-duration"),
            hdr_decision: self.last_hdr.lock().clone(),
            audio_decision: self.last_audio.lock().clone(),
        }
    }

    pub fn set_property(&self, name: &str, value: &str) -> Result<()> {
        let guard = self.mpv.lock();
        let inst = guard
            .as_ref()
            .ok_or_else(|| PlaybackError::BackendUnavailable("engine shut down".into()))?;
        inst.lib
            .set_property_string(inst.handle, name, value)
            .map_err(|rc| {
                warn!(property = %name, value = %value, rc, "mpv set_property failed");
                PlaybackError::CommandFailed(format!("set_property({name}={value}) returned {rc}"))
            })
    }

    pub fn run_command(&self, args: &[&str]) -> Result<()> {
        let guard = self.mpv.lock();
        let inst = guard
            .as_ref()
            .ok_or_else(|| PlaybackError::BackendUnavailable("engine shut down".into()))?;
        inst.lib
            .command(inst.handle, args)
            .map_err(|rc| PlaybackError::CommandFailed(format!("command({args:?}) returned {rc}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initializes_real_libmpv_headless_and_queries_stats() {
        let cfg = PlaybackConfig {
            headless_null_vo: true,
            ..Default::default()
        };
        let engine = PlaybackEngine::new(cfg).expect("libmpv should initialize in headless mode");
        let stats = engine.stats_snapshot();
        assert!(stats.backend_active);
        assert!(!stats.libmpv_api_version.is_empty());
        engine.set_volume(80.0).unwrap();
        engine.set_speed(1.25).unwrap();
        let updated = engine.stats_snapshot();
        assert!((updated.volume - 80.0).abs() < 1.0);
        assert!((updated.speed - 1.25).abs() < 0.01);
    }
}
