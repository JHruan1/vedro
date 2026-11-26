use serde::{Deserialize, Deserializer, Serialize};
use std::collections::HashMap;

/// Emby uses 100-nanosecond ticks: 10,000,000 ticks == 1 second.
pub const TICKS_PER_SECOND: i64 = 10_000_000;

/// Deserializes either a JSON string or integer/unsigned integer into a `String`.
/// Crucial for compatibility with embygo (which emits numeric facet/person IDs for
/// SenPlayer compatibility) as well as Emby/Jellyfin string/hex/UUID IDs.
pub fn deserialize_string_or_int<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Value {
        Str(String),
        Int(i64),
        Uint(u64),
        Float(f64),
        Null,
    }
    match Value::deserialize(deserializer)? {
        Value::Str(s) => Ok(s),
        Value::Int(i) => Ok(i.to_string()),
        Value::Uint(u) => Ok(u.to_string()),
        Value::Float(f) => Ok((f as i64).to_string()),
        Value::Null => Ok(String::new()),
    }
}

pub fn deserialize_opt_string_or_int<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Value {
        Str(String),
        Int(i64),
        Uint(u64),
        Null,
    }
    match Option::<Value>::deserialize(deserializer)? {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s)),
        Some(Value::Int(i)) => Ok(Some(i.to_string())),
        Some(Value::Uint(u)) => Ok(Some(u.to_string())),
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct PublicSystemInfo {
    #[serde(default)]
    pub local_address: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub product_name: Option<String>,
    #[serde(default)]
    pub operating_system: Option<String>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub id: Option<String>,
}

/// embygo-specific administrator health & scan telemetry (`GET /emby-compat/status`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EmbyGoStatus {
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub advertised_server_version: Option<String>,
    #[serde(default)]
    pub postgres_catalog: Option<bool>,
    #[serde(default)]
    pub postgres_auth_sessions: Option<bool>,
    #[serde(default)]
    pub postgres_playback_progress: Option<bool>,
    #[serde(default)]
    pub transcoding_enabled: Option<bool>,
    #[serde(default)]
    pub built_at: Option<String>,
    #[serde(default)]
    pub files: Option<u64>,
    #[serde(default)]
    pub items: Option<u64>,
    #[serde(default)]
    pub subtitle_files: Option<u64>,
    #[serde(default)]
    pub retained_previous_snapshot: Option<bool>,
    #[serde(default)]
    pub last_scan_attempt_at: Option<String>,
    #[serde(default)]
    pub last_scan_published: Option<bool>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ItemCounts {
    #[serde(default)]
    pub movie_count: u64,
    #[serde(default)]
    pub series_count: u64,
    #[serde(default)]
    pub episode_count: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UserPolicy {
    #[serde(default)]
    pub is_administrator: bool,
    #[serde(default)]
    pub is_hidden: bool,
    #[serde(default)]
    pub is_disabled: bool,
    #[serde(default)]
    pub enable_all_folders: bool,
    #[serde(default)]
    pub enabled_folders: Vec<String>,
    #[serde(default)]
    pub enable_content_downloading: bool,
    #[serde(default)]
    pub max_active_sessions: Option<i64>,
    #[serde(default)]
    pub max_devices: Option<i64>,
    #[serde(default)]
    pub max_stream_connections: Option<i64>,
    #[serde(default)]
    pub remote_client_bitrate_limit: Option<i64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UserDto {
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub has_password: bool,
    #[serde(default)]
    pub primary_image_tag: Option<String>,
    #[serde(default)]
    pub policy: Option<UserPolicy>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct AuthResponse {
    #[serde(default)]
    pub access_token: String,
    #[serde(default)]
    pub server_id: Option<String>,
    #[serde(default)]
    pub user: UserDto,
    #[serde(default)]
    pub session_info: Option<SessionInfoDto>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UserItemDataDto {
    #[serde(default)]
    pub played: bool,
    #[serde(default)]
    pub played_percentage: Option<f64>,
    #[serde(default)]
    pub playback_position_ticks: i64,
    #[serde(default)]
    pub play_count: i64,
    #[serde(default)]
    pub unplayed_item_count: Option<i64>,
    #[serde(default)]
    pub is_favorite: bool,
    #[serde(default)]
    pub last_played_date: Option<String>,
    #[serde(default)]
    pub key: Option<String>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub item_id: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct NameIdPair {
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub id: String,
    #[serde(default)]
    pub name: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct PersonCredit {
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default, rename = "Type")]
    pub credit_type: Option<String>,
    #[serde(default)]
    pub primary_image_tag: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MediaStream {
    #[serde(default)]
    pub index: i32,
    #[serde(default, rename = "Type")]
    pub stream_type: String,
    #[serde(default)]
    pub codec: Option<String>,
    #[serde(default)]
    pub profile: Option<String>,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub display_title: Option<String>,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default)]
    pub is_forced: bool,
    #[serde(default)]
    pub is_external: bool,
    #[serde(default)]
    pub is_text_subtitle_stream: bool,
    #[serde(default)]
    pub delivery_url: Option<String>,
    #[serde(default)]
    pub width: Option<u32>,
    #[serde(default)]
    pub height: Option<u32>,
    #[serde(default)]
    pub bit_depth: Option<u32>,
    #[serde(default)]
    pub bit_rate: Option<u64>,
    #[serde(default)]
    pub channels: Option<u32>,
    #[serde(default)]
    pub channel_layout: Option<String>,
    #[serde(default)]
    pub sample_rate: Option<u32>,
    #[serde(default)]
    pub video_range: Option<String>,
    #[serde(default)]
    pub video_range_type: Option<String>,
    #[serde(default)]
    pub video_do_vi_title: Option<String>,
    #[serde(default)]
    pub dv_profile: Option<u32>,
    #[serde(default)]
    pub color_space: Option<String>,
    #[serde(default)]
    pub color_transfer: Option<String>,
    #[serde(default)]
    pub color_primaries: Option<String>,
    #[serde(default)]
    pub real_frame_rate: Option<f64>,
    #[serde(default)]
    pub average_frame_rate: Option<f64>,
    #[serde(default)]
    pub pixel_format: Option<String>,
    #[serde(default)]
    pub aspect_ratio: Option<String>,
    #[serde(default)]
    pub level: Option<f64>,
}

/// High-level technical badges extracted from `MediaStreams` and/or filename heuristics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MediaBadges {
    pub resolution: Option<String>,
    pub video_codec: Option<String>,
    pub hdr_format: Option<String>,
    pub dolby_vision_profile: Option<u8>,
    pub audio_codec: Option<String>,
    pub is_dolby_atmos: bool,
    pub is_dts_x: bool,
    pub is_remux: bool,
    pub source_tier: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MediaSourceInfo {
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub id: String,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub item_id: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub path: Option<String>,
    #[serde(default)]
    pub container: Option<String>,
    #[serde(default)]
    pub size: Option<u64>,
    #[serde(default)]
    pub bitrate: Option<u64>,
    #[serde(default)]
    pub run_time_ticks: Option<i64>,
    #[serde(default, rename = "ETag")]
    pub etag: Option<String>,
    #[serde(default)]
    pub direct_stream_url: Option<String>,
    #[serde(default)]
    pub supports_direct_play: bool,
    #[serde(default)]
    pub supports_direct_stream: bool,
    #[serde(default)]
    pub supports_transcoding: bool,
    #[serde(default)]
    pub add_api_key_to_direct_stream_url: Option<bool>,
    #[serde(default)]
    pub default_audio_stream_index: Option<i32>,
    #[serde(default)]
    pub default_subtitle_stream_index: Option<i32>,
    #[serde(default)]
    pub media_streams: Vec<MediaStream>,
}

impl MediaSourceInfo {
    /// Infer technical media badges (4K, Dolby Vision, HDR10+, Dolby Atmos, TrueHD, DTS:X, Remux)
    /// combining server-provided `MediaStreams` with structured filename fallback (crucial for
    /// `embygo`, which intentionally skips probing unplayed files).
    pub fn infer_badges(&self) -> MediaBadges {
        let mut badges = MediaBadges::default();
        let hay = format!(
            "{} {}",
            self.name.as_deref().unwrap_or(""),
            self.path.as_deref().unwrap_or("")
        )
        .to_lowercase();

        // 1. Inspect structured MediaStreams first (authoritative when present)
        for s in &self.media_streams {
            match s.stream_type.to_lowercase().as_str() {
                "video" => {
                    if let Some(h) = s.height {
                        badges.resolution = Some(if h >= 2000 {
                            "4K".into()
                        } else if h >= 1000 {
                            "1080p".into()
                        } else if h >= 700 {
                            "720p".into()
                        } else {
                            format!("{h}p")
                        });
                    }
                    if let Some(c) = &s.codec {
                        badges.video_codec = Some(c.to_uppercase());
                    }
                    if let Some(p) = s.dv_profile {
                        badges.dolby_vision_profile = Some(p as u8);
                        badges.hdr_format = Some(format!("Dolby Vision P{p}"));
                    } else if s.video_do_vi_title.is_some()
                        || s.video_range_type
                            .as_deref()
                            .unwrap_or("")
                            .to_lowercase()
                            .contains("dovi")
                    {
                        badges.hdr_format = Some("Dolby Vision".into());
                    } else if let Some(vrt) = &s.video_range_type {
                        let lower = vrt.to_lowercase();
                        if lower.contains("hdr10+") || lower.contains("hdr10plus") {
                            badges.hdr_format = Some("HDR10+".into());
                        } else if lower.contains("hlg") {
                            badges.hdr_format = Some("HLG".into());
                        } else if lower.contains("hdr") {
                            badges.hdr_format = Some("HDR10".into());
                        }
                    } else if s
                        .video_range
                        .as_deref()
                        .map(|r| r.eq_ignore_ascii_case("HDR"))
                        .unwrap_or(false)
                    {
                        badges.hdr_format = Some("HDR10".into());
                    }
                }
                "audio" => {
                    let codec = s.codec.as_deref().unwrap_or("").to_lowercase();
                    let title = format!(
                        "{} {} {}",
                        s.title.as_deref().unwrap_or(""),
                        s.display_title.as_deref().unwrap_or(""),
                        s.profile.as_deref().unwrap_or("")
                    )
                    .to_lowercase();
                    if title.contains("atmos") || title.contains("joc") {
                        badges.is_dolby_atmos = true;
                    }
                    if title.contains("dts:x") || title.contains("dtsx") {
                        badges.is_dts_x = true;
                    }
                    if badges.audio_codec.is_none() && !codec.is_empty() {
                        badges.audio_codec = Some(match codec.as_str() {
                            "truehd" => "TrueHD".into(),
                            "eac3" | "ec-3" => "E-AC-3".into(),
                            "ac3" => "AC-3".into(),
                            "dts" => "DTS".into(),
                            "flac" => "FLAC".into(),
                            "aac" => "AAC".into(),
                            "opus" => "Opus".into(),
                            other => other.to_uppercase(),
                        });
                    }
                }
                _ => {}
            }
        }

        // 2. Filename heuristics fallback for unprobed embygo sources
        if badges.resolution.is_none() {
            if hay.contains("2160p") || hay.contains("4k") || hay.contains("uhd") {
                badges.resolution = Some("4K".into());
            } else if hay.contains("1080p") {
                badges.resolution = Some("1080p".into());
            } else if hay.contains("720p") {
                badges.resolution = Some("720p".into());
            }
        }
        if badges.hdr_format.is_none() {
            if hay.contains("dovi")
                || hay.contains(".dv.")
                || hay.contains(" dv ")
                || hay.contains("[dv]")
                || hay.contains("dolby.vision")
                || hay.contains("dolby vision")
            {
                badges.hdr_format = Some("Dolby Vision".into());
            } else if hay.contains("hdr10+") || hay.contains("hdr10plus") {
                badges.hdr_format = Some("HDR10+".into());
            } else if hay.contains("hlg") {
                badges.hdr_format = Some("HLG".into());
            } else if hay.contains("hdr10") || hay.contains(".hdr.") || hay.contains(" hdr ") {
                badges.hdr_format = Some("HDR10".into());
            }
        }
        if badges.video_codec.is_none() {
            if hay.contains("av1") {
                badges.video_codec = Some("AV1".into());
            } else if hay.contains("hevc")
                || hay.contains("x265")
                || hay.contains("h265")
                || hay.contains("h.265")
            {
                badges.video_codec = Some("HEVC".into());
            } else if hay.contains("x264")
                || hay.contains("h264")
                || hay.contains("h.264")
                || hay.contains("avc")
            {
                badges.video_codec = Some("H.264".into());
            }
        }
        if !badges.is_dolby_atmos && hay.contains("atmos") {
            badges.is_dolby_atmos = true;
        }
        if !badges.is_dts_x
            && (hay.contains("dts-x") || hay.contains("dts:x") || hay.contains("dtsx"))
        {
            badges.is_dts_x = true;
        }
        if badges.audio_codec.is_none() {
            if hay.contains("truehd") {
                badges.audio_codec = Some("TrueHD".into());
            } else if hay.contains("ddp") || hay.contains("eac3") || hay.contains("e-ac-3") {
                badges.audio_codec = Some("E-AC-3".into());
            } else if hay.contains("dts-hd") || hay.contains("dtshd") {
                badges.audio_codec = Some("DTS-HD MA".into());
            } else if hay.contains("dts") {
                badges.audio_codec = Some("DTS".into());
            } else if hay.contains("flac") {
                badges.audio_codec = Some("FLAC".into());
            }
        }
        if hay.contains("remux") {
            badges.is_remux = true;
        }
        badges
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ExternalUrl {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub url: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ChapterInfo {
    #[serde(default)]
    pub start_position_ticks: i64,
    #[serde(default)]
    pub name: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct BaseItemDto {
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub sort_name: Option<String>,
    #[serde(default)]
    pub original_title: Option<String>,
    #[serde(default, rename = "Type")]
    pub item_type: String,
    #[serde(default)]
    pub collection_type: Option<String>,
    #[serde(default)]
    pub is_folder: bool,
    #[serde(default)]
    pub overview: Option<String>,
    #[serde(default)]
    pub taglines: Vec<String>,
    #[serde(default)]
    pub production_year: Option<i32>,
    #[serde(default)]
    pub premiere_date: Option<String>,
    #[serde(default)]
    pub end_date: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub date_created: Option<String>,
    #[serde(default)]
    pub path: Option<String>,
    #[serde(default)]
    pub air_time: Option<String>,
    #[serde(default)]
    pub air_days: Vec<String>,
    #[serde(default)]
    pub production_locations: Vec<String>,
    #[serde(default)]
    pub external_urls: Vec<ExternalUrl>,
    #[serde(default)]
    pub remote_trailers: Vec<ExternalUrl>,
    #[serde(default)]
    pub chapters: Vec<ChapterInfo>,
    #[serde(default)]
    pub aspect_ratio: Option<String>,
    #[serde(default)]
    pub custom_rating: Option<String>,
    #[serde(default)]
    pub budget: Option<u64>,
    #[serde(default)]
    pub revenue: Option<u64>,
    #[serde(default)]
    pub award_summary: Option<String>,
    #[serde(default)]
    pub airs_before_season_number: Option<i32>,
    #[serde(default)]
    pub airs_before_episode_number: Option<i32>,
    #[serde(default)]
    pub community_rating: Option<f64>,
    #[serde(default)]
    pub critic_rating: Option<f64>,
    #[serde(default)]
    pub official_rating: Option<String>,
    #[serde(default)]
    pub run_time_ticks: Option<i64>,
    #[serde(default)]
    pub primary_image_aspect_ratio: Option<f64>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub parent_id: Option<String>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub series_id: Option<String>,
    #[serde(default)]
    pub series_name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub season_id: Option<String>,
    #[serde(default)]
    pub season_name: Option<String>,
    #[serde(default)]
    pub parent_index_number: Option<i32>,
    #[serde(default)]
    pub season_number: Option<i32>,
    #[serde(default)]
    pub index_number: Option<i32>,
    #[serde(default)]
    pub index_number_end: Option<i32>,
    #[serde(default)]
    pub child_count: Option<i32>,
    #[serde(default)]
    pub recursive_item_count: Option<i32>,
    #[serde(default)]
    pub source_folder_count: Option<i32>,
    #[serde(default)]
    pub media_source_count: Option<i32>,
    #[serde(default)]
    pub container: Option<String>,
    #[serde(default)]
    pub size: Option<u64>,
    #[serde(default)]
    pub genres: Vec<String>,
    #[serde(default)]
    pub genre_items: Vec<NameIdPair>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub tag_items: Vec<NameIdPair>,
    #[serde(default)]
    pub studios: Vec<NameIdPair>,
    #[serde(default)]
    pub people: Vec<PersonCredit>,
    #[serde(default)]
    pub provider_ids: HashMap<String, String>,
    #[serde(default)]
    pub image_tags: HashMap<String, String>,
    #[serde(default)]
    pub backdrop_image_tags: Vec<String>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub parent_primary_image_item_id: Option<String>,
    #[serde(default)]
    pub parent_primary_image_tag: Option<String>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub parent_thumb_item_id: Option<String>,
    #[serde(default)]
    pub parent_thumb_image_tag: Option<String>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub parent_logo_item_id: Option<String>,
    #[serde(default)]
    pub parent_logo_image_tag: Option<String>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub parent_backdrop_item_id: Option<String>,
    #[serde(default)]
    pub parent_backdrop_image_tags: Vec<String>,
    #[serde(default)]
    pub series_primary_image_tag: Option<String>,
    #[serde(default)]
    pub user_data: Option<UserItemDataDto>,
    #[serde(default)]
    pub media_sources: Vec<MediaSourceInfo>,
    #[serde(default)]
    pub can_download: Option<bool>,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub playlist_item_id: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ItemsResult<T = BaseItemDto> {
    #[serde(default)]
    pub items: Vec<T>,
    #[serde(default)]
    pub total_record_count: u64,
    #[serde(default)]
    pub start_index: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct DirectPlayProfile {
    #[serde(rename = "Type")]
    pub media_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub container: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub video_codec: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio_codec: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct DeviceProfile {
    pub name: String,
    pub max_streaming_bitrate: u64,
    pub direct_play_profiles: Vec<DirectPlayProfile>,
}

impl DeviceProfile {
    /// Universal direct-play profile for Vedro (libmpv + FFmpeg + libplacebo).
    /// Supports virtually every modern container, video codec (including DoVi/HEVC/AV1/VP9/H264/VC1/MPEG2),
    /// and lossless/object audio codec (TrueHD Atmos, E-AC-3 JOC, DTS-HD MA/DTS:X, FLAC, PCM, Opus, AAC).
    pub fn vedro_universal() -> Self {
        Self {
            name: "Vedro DirectPlay".to_string(),
            max_streaming_bitrate: 200_000_000,
            direct_play_profiles: vec![DirectPlayProfile {
                media_type: "Video".to_string(),
                container: Some(
                    "mkv,mp4,m4v,mov,ts,m2ts,webm,avi,flv,wmv,mpg,mpeg,ogm,vob,iso,strm"
                        .to_string(),
                ),
                video_codec: Some(
                    "hevc,h265,h264,avc,av1,vp9,vp8,mpeg2video,mpeg4,vc1,prores,dvhe,dvh1"
                        .to_string(),
                ),
                audio_codec: Some(
                    "truehd,eac3,ac3,dts,dca,flac,aac,opus,vorbis,mp3,pcm,alac,mlp".to_string(),
                ),
            }],
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct PlaybackInfoRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub media_source_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio_stream_index: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subtitle_stream_index: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enable_direct_play: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enable_direct_stream: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enable_transcoding: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enable_media_probe: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_profile: Option<DeviceProfile>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct PlaybackInfoResponse {
    #[serde(default)]
    pub media_sources: Vec<MediaSourceInfo>,
    #[serde(default)]
    pub play_session_id: String,
    #[serde(default)]
    pub error_code: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct PlaybackProgressPayload {
    pub item_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub media_source_id: Option<String>,
    pub play_session_id: String,
    pub position_ticks: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub run_time_ticks: Option<i64>,
    pub is_paused: bool,
    pub play_method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio_stream_index: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subtitle_stream_index: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub can_seek: Option<bool>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct SessionPlayStateDto {
    #[serde(default)]
    pub position_ticks: Option<i64>,
    #[serde(default)]
    pub is_paused: bool,
    #[serde(default)]
    pub play_method: Option<String>,
    #[serde(default)]
    pub media_source_id: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct SessionInfoDto {
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub id: String,
    #[serde(default, deserialize_with = "deserialize_opt_string_or_int")]
    pub user_id: Option<String>,
    #[serde(default)]
    pub user_name: Option<String>,
    #[serde(default)]
    pub device_id: Option<String>,
    #[serde(default)]
    pub device_name: Option<String>,
    #[serde(default)]
    pub client: Option<String>,
    #[serde(default)]
    pub application_version: Option<String>,
    #[serde(default)]
    pub last_activity_date: Option<String>,
    #[serde(default)]
    pub now_playing_item: Option<BaseItemDto>,
    #[serde(default)]
    pub play_state: Option<SessionPlayStateDto>,
    #[serde(default)]
    pub stream_route: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ClientCapabilitiesPayload {
    pub playable_media_types: Vec<String>,
    pub supported_commands: Vec<String>,
    pub supports_media_control: bool,
    pub supports_persistent_identifier: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_profile: Option<DeviceProfile>,
}

impl Default for ClientCapabilitiesPayload {
    fn default() -> Self {
        Self {
            playable_media_types: vec!["Video".into(), "Audio".into()],
            supported_commands: vec![
                "Play".into(),
                "Playstate".into(),
                "DisplayMessage".into(),
                "SetVolume".into(),
                "Mute".into(),
                "Unmute".into(),
                "ToggleMute".into(),
                "SetAudioStreamIndex".into(),
                "SetSubtitleStreamIndex".into(),
            ],
            supports_media_control: true,
            supports_persistent_identifier: true,
            device_profile: Some(DeviceProfile::vedro_universal()),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct SearchHint {
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub item_id: String,
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default, rename = "Type")]
    pub item_type: String,
    #[serde(default)]
    pub production_year: Option<i32>,
    #[serde(default)]
    pub primary_image_tag: Option<String>,
    #[serde(default)]
    pub series: Option<String>,
    #[serde(default)]
    pub run_time_ticks: Option<i64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct SearchHintsResult {
    #[serde(default)]
    pub search_hints: Vec<SearchHint>,
    #[serde(default)]
    pub total_record_count: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct Filters2Result {
    #[serde(default)]
    pub genres: Vec<NameIdPair>,
    #[serde(default)]
    pub tags: Vec<NameIdPair>,
    #[serde(default)]
    pub official_ratings: Vec<String>,
    #[serde(default)]
    pub years: Vec<i32>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MediaSegment {
    #[serde(default)]
    pub id: String,
    #[serde(default, rename = "Type")]
    pub segment_type: String,
    #[serde(default)]
    pub start_ticks: i64,
    #[serde(default)]
    pub end_ticks: i64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MediaSegmentsResult {
    #[serde(default)]
    pub items: Vec<MediaSegment>,
    #[serde(default)]
    pub total_record_count: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct PlaylistCreated {
    #[serde(default, deserialize_with = "deserialize_string_or_int")]
    pub id: String,
    #[serde(default)]
    pub name: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ItemsQuery {
    pub parent_id: Option<String>,
    pub include_item_types: Option<String>,
    pub recursive: Option<bool>,
    pub sort_by: Option<String>,
    pub sort_order: Option<String>,
    pub start_index: Option<u64>,
    pub limit: Option<u64>,
    pub search_term: Option<String>,
    pub genre_ids: Option<String>,
    pub genres: Option<String>,
    pub studio_ids: Option<String>,
    pub tag_ids: Option<String>,
    pub tags: Option<String>,
    pub years: Option<String>,
    pub official_ratings: Option<String>,
    pub person_ids: Option<String>,
    pub is_played: Option<bool>,
    pub is_favorite: Option<bool>,
    pub is_resumable: Option<bool>,
    pub filters: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscoveredServer {
    pub id: String,
    pub name: String,
    pub address: String,
    pub endpoint_address: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserializes_both_numeric_and_string_ids() {
        let json_num = r#"{"Id": 1033623341234579, "Name": "肥皂剧"}"#;
        let pair: NameIdPair = serde_json::from_str(json_num).unwrap();
        assert_eq!(pair.id, "1033623341234579");
        assert_eq!(pair.name, "肥皂剧");

        let json_str = r#"{"Id": "abc-123", "Name": "Sci-Fi"}"#;
        let pair2: NameIdPair = serde_json::from_str(json_str).unwrap();
        assert_eq!(pair2.id, "abc-123");
    }

    #[test]
    fn infers_dovi_and_atmos_badges_from_filename_and_streams() {
        let src = MediaSourceInfo {
            id: "v1".into(),
            name: Some(
                "Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR10+.TrueHD.Atmos.7.1.HEVC.mkv"
                    .into(),
            ),
            ..Default::default()
        };
        let b = src.infer_badges();
        assert_eq!(b.resolution.as_deref(), Some("4K"));
        assert_eq!(b.hdr_format.as_deref(), Some("Dolby Vision"));
        assert_eq!(b.video_codec.as_deref(), Some("HEVC"));
        assert_eq!(b.audio_codec.as_deref(), Some("TrueHD"));
        assert!(b.is_dolby_atmos);
        assert!(b.is_remux);
    }
}
