use serde::{Deserialize, Serialize};
use vedro_playback::{AudioRoutingDecision, DolbyVisionDecision, PlaybackStats};
use vedro_protocol::{MediaBadges, MediaSourceInfo};
use vedro_stream::{InspectedMedia, StreamProxyStats};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreparedPlayback {
    pub item_id: String,
    pub media_source_id: String,
    pub play_session_id: String,
    pub stream_id: String,
    pub proxy_url: String,
    pub upstream_url: String,
    pub uses_stream_ticket: bool,
    pub media_source: MediaSourceInfo,
    pub badges: MediaBadges,
    pub inspected: Option<InspectedMedia>,
    pub hdr_decision: DolbyVisionDecision,
    pub audio_decision: AudioRoutingDecision,
    pub mpv_options: Vec<(String, String)>,
    pub external_subtitles: Vec<ExternalSubtitle>,
    #[serde(default)]
    pub text_subtitles: Vec<ExternalSubtitle>,
    pub all_sources: Vec<MediaSourceInfo>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExternalSubtitle {
    pub index: i32,
    pub language: Option<String>,
    pub title: String,
    pub codec: String,
    pub is_default: bool,
    pub is_forced: bool,
    #[serde(default = "default_true")]
    pub is_external: bool,
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CombinedPlayerStats {
    pub playback: PlaybackStats,
    pub proxy: StreamProxyStats,
}

pub(crate) struct ActivePlaybackSession {
    pub(crate) item_id: String,
    pub(crate) media_source_id: String,
    pub(crate) play_session_id: String,
    pub(crate) stream_id: String,
    pub(crate) run_time_ticks: Option<i64>,
    pub(crate) audio_stream_index: Option<i32>,
    pub(crate) subtitle_stream_index: Option<i32>,
}
