use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, info, warn};

use crate::client::EmbyClient;
use crate::models::UserItemDataDto;

/// High-level events pushed by embygo / Emby / Jellyfin over WebSocket.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ServerPushEvent {
    Connected,
    Disconnected {
        reason: String,
    },
    Play {
        item_ids: Vec<String>,
        start_position_ticks: Option<i64>,
        play_command: String,
    },
    Playstate {
        command: String,
        seek_position_ticks: Option<i64>,
    },
    DisplayMessage {
        header: String,
        text: String,
        timeout_ms: Option<u64>,
    },
    GeneralCommand {
        name: String,
        arguments: serde_json::Value,
    },
    UserDataChanged {
        user_id: String,
        items: Vec<UserItemDataDto>,
    },
    ForceKeepAlive {
        interval_secs: u64,
    },
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct WsEnvelope {
    #[serde(default)]
    message_type: String,
    #[serde(default)]
    data: serde_json::Value,
}

/// Manages a resilient WebSocket connection to embygo (`/embywebsocket`) or Jellyfin (`/socket`).
/// Always speaks text frames (matching embygo's text-by-default framing), responds to KeepAlive,
/// and reconnects with bounded exponential backoff.
pub struct WebSocketSession {
    shutdown_tx: Option<mpsc::Sender<()>>,
}

impl WebSocketSession {
    pub fn spawn(client: EmbyClient) -> (Self, mpsc::Receiver<ServerPushEvent>) {
        let (event_tx, event_rx) = mpsc::channel(128);
        let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);

        tokio::spawn(async move {
            let mut backoff = Duration::from_secs(1);
            loop {
                let ws_url = match client.websocket_url() {
                    Ok(u) => u,
                    Err(e) => {
                        let _ = event_tx
                            .send(ServerPushEvent::Disconnected {
                                reason: e.to_string(),
                            })
                            .await;
                        return;
                    }
                };

                debug!(url = %ws_url.host_str().unwrap_or("server"), "connecting websocket");
                match tokio_tungstenite::connect_async(ws_url.as_str()).await {
                    Ok((ws_stream, _)) => {
                        backoff = Duration::from_secs(1);
                        info!("emby websocket connected");
                        let _ = event_tx.send(ServerPushEvent::Connected).await;

                        let (mut write, mut read) = ws_stream.split();
                        let mut ping_interval = tokio::time::interval(Duration::from_secs(30));
                        ping_interval.tick().await;

                        loop {
                            tokio::select! {
                                _ = shutdown_rx.recv() => {
                                    let _ = write.close().await;
                                    return;
                                }
                                _ = ping_interval.tick() => {
                                    let keepalive = serde_json::json!({"MessageType": "KeepAlive"});
                                    if write.send(Message::Text(keepalive.to_string())).await.is_err() {
                                        break;
                                    }
                                }
                                msg = read.next() => {
                                    match msg {
                                        Some(Ok(Message::Text(txt))) => {
                                            if let Some(ev) = parse_ws_message(&txt) {
                                                let _ = event_tx.send(ev).await;
                                            }
                                        }
                                        Some(Ok(Message::Binary(bin))) => {
                                            if let Ok(txt) = std::str::from_utf8(&bin) {
                                                if let Some(ev) = parse_ws_message(txt) {
                                                    let _ = event_tx.send(ev).await;
                                                }
                                            }
                                        }
                                        Some(Ok(Message::Ping(payload))) => {
                                            let _ = write.send(Message::Pong(payload)).await;
                                        }
                                        Some(Ok(Message::Close(_))) | None => break,
                                        Some(Err(e)) => {
                                            warn!(error = %e, "websocket stream error");
                                            break;
                                        }
                                        _ => {}
                                    }
                                }
                            }
                        }

                        let _ = event_tx
                            .send(ServerPushEvent::Disconnected {
                                reason: "connection closed".into(),
                            })
                            .await;
                    }
                    Err(e) => {
                        warn!(error = %e, "websocket connect failed; retrying");
                        let _ = event_tx
                            .send(ServerPushEvent::Disconnected {
                                reason: e.to_string(),
                            })
                            .await;
                    }
                }

                tokio::select! {
                    _ = shutdown_rx.recv() => return,
                    _ = tokio::time::sleep(backoff) => {}
                }
                backoff = (backoff * 2).min(Duration::from_secs(30));
            }
        });

        (
            Self {
                shutdown_tx: Some(shutdown_tx),
            },
            event_rx,
        )
    }

    pub async fn stop(&mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(()).await;
        }
    }
}

pub fn parse_ws_message(raw: &str) -> Option<ServerPushEvent> {
    let env: WsEnvelope = serde_json::from_str(raw).ok()?;
    match env.message_type.as_str() {
        "Play" => {
            let item_ids = env
                .data
                .get("ItemIds")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|x| x.as_str().map(ToString::to_string))
                        .collect()
                })
                .unwrap_or_default();
            let start_position_ticks = env.data.get("StartPositionTicks").and_then(|v| v.as_i64());
            let play_command = env
                .data
                .get("PlayCommand")
                .and_then(|v| v.as_str())
                .unwrap_or("PlayNow")
                .to_string();
            Some(ServerPushEvent::Play {
                item_ids,
                start_position_ticks,
                play_command,
            })
        }
        "Playstate" => {
            let command = env
                .data
                .get("Command")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let seek_position_ticks = env.data.get("SeekPositionTicks").and_then(|v| v.as_i64());
            Some(ServerPushEvent::Playstate {
                command,
                seek_position_ticks,
            })
        }
        "GeneralCommand" => {
            let name = env
                .data
                .get("Name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let args = env
                .data
                .get("Arguments")
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            if name.eq_ignore_ascii_case("DisplayMessage") {
                let header = args
                    .get("Header")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let text = args
                    .get("Text")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let timeout_ms = args.get("TimeoutMs").and_then(|v| v.as_u64());
                return Some(ServerPushEvent::DisplayMessage {
                    header,
                    text,
                    timeout_ms,
                });
            }
            Some(ServerPushEvent::GeneralCommand {
                name,
                arguments: args,
            })
        }
        "UserDataChanged" => {
            let user_id = env
                .data
                .get("UserId")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let items = env
                .data
                .get("UserDataList")
                .and_then(|v| serde_json::from_value::<Vec<UserItemDataDto>>(v.clone()).ok())
                .unwrap_or_default();
            Some(ServerPushEvent::UserDataChanged { user_id, items })
        }
        "ForceKeepAlive" => {
            let secs = env.data.as_u64().unwrap_or(30);
            Some(ServerPushEvent::ForceKeepAlive {
                interval_secs: secs,
            })
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_playstate_and_user_data_changed() {
        let raw = r#"{"MessageType":"Playstate","Data":{"Command":"Seek","SeekPositionTicks":120000000}}"#;
        match parse_ws_message(raw) {
            Some(ServerPushEvent::Playstate {
                command,
                seek_position_ticks,
            }) => {
                assert_eq!(command, "Seek");
                assert_eq!(seek_position_ticks, Some(120_000_000));
            }
            other => panic!("unexpected event: {other:?}"),
        }

        let udc = r#"{"MessageType":"UserDataChanged","Data":{"UserId":"u1","UserDataList":[{"ItemId":"i1","Played":true,"PlaybackPositionTicks":0}]}}"#;
        match parse_ws_message(udc) {
            Some(ServerPushEvent::UserDataChanged { user_id, items }) => {
                assert_eq!(user_id, "u1");
                assert_eq!(items.len(), 1);
                assert!(items[0].played);
            }
            other => panic!("unexpected event: {other:?}"),
        }
    }
}
