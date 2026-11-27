use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::Duration;

use serde::Deserialize;
use tokio::net::UdpSocket;

use crate::error::{ProtocolError, Result};
use crate::models::DiscoveredServer;

const DISCOVERY_PORT: u16 = 7359;
const EMBY_PROBE: &[u8] = b"who is EmbyServer?";
const JELLYFIN_PROBE: &[u8] = b"who is JellyfinServer?";

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct DiscoveryPacket {
    #[serde(default)]
    id: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    address: String,
    #[serde(default)]
    endpoint_address: Option<String>,
}

/// Broadcast UDP port 7359 LAN discovery probes for `embygo`, `Emby`, and `Jellyfin` servers.
pub async fn discover_lan_servers(timeout: Duration) -> Result<Vec<DiscoveredServer>> {
    let socket = UdpSocket::bind("0.0.0.0:0")
        .await
        .map_err(|e| ProtocolError::Discovery(e.to_string()))?;
    socket
        .set_broadcast(true)
        .map_err(|e| ProtocolError::Discovery(e.to_string()))?;

    let target: SocketAddr = format!("255.255.255.255:{DISCOVERY_PORT}")
        .parse()
        .map_err(|e: std::net::AddrParseError| ProtocolError::Discovery(e.to_string()))?;

    let _ = socket.send_to(EMBY_PROBE, target).await;
    let _ = socket.send_to(JELLYFIN_PROBE, target).await;

    let mut found: HashMap<String, DiscoveredServer> = HashMap::new();
    let mut buf = [0u8; 4096];
    let deadline = tokio::time::Instant::now() + timeout;

    loop {
        let now = tokio::time::Instant::now();
        if now >= deadline {
            break;
        }
        let remaining = deadline - now;
        match tokio::time::timeout(remaining, socket.recv_from(&mut buf)).await {
            Ok(Ok((n, peer))) => {
                if found.len() >= 64 {
                    break;
                }
                if let Ok(pkt) = serde_json::from_slice::<DiscoveryPacket>(&buf[..n]) {
                    let addr = pkt.address.trim();
                    let valid_http = url::Url::parse(addr)
                        .map(|u| matches!(u.scheme(), "http" | "https") && u.host_str().is_some())
                        .unwrap_or(false);
                    if valid_http {
                        let key = if pkt.id.is_empty() {
                            addr.to_string()
                        } else {
                            pkt.id.clone()
                        };
                        found.entry(key).or_insert(DiscoveredServer {
                            id: pkt.id,
                            name: if pkt.name.trim().is_empty() {
                                peer.ip().to_string()
                            } else {
                                pkt.name.trim().to_string()
                            },
                            address: addr.to_string(),
                            endpoint_address: pkt.endpoint_address,
                        });
                    }
                }
            }
            Ok(Err(_)) | Err(_) => break,
        }
    }

    Ok(found.into_values().collect())
}
