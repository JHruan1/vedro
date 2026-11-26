//! In-process native multi-protocol proxy engine (`127.0.0.1:0` local SOCKS5 + HTTP CONNECT).
//!
//! Runs 100% inside `libvedro_ffi` without spawning any external child binary (`sing-box` / `.exe`),
//! so proxy subscription nodes work natively on **Android 10–16 (W^X SELinux)**, **iOS Sandbox**,
//! **macOS**, **Windows**, and **Linux** — while touching ZERO OS VPN / TUN slots.
//!
//! Supported outbound protocols:
//! - `vless` (standard VLESS v0 over TCP / TLS / WS / WSS / HTTPUpgrade)
//! - `trojan` (SHA-224 Trojan over TLS / TCP / WS / WSS / HTTPUpgrade)
//! - `shadowsocks` / `ss` (`aes-128-gcm`, `aes-256-gcm`, `chacha20-ietf-poly1305`, `none`)
//! - `vmess` (VMess AEAD with `aes-128-gcm`, `chacha20-poly1305`, `auto`, `none` over TCP / TLS / WS / WSS / HTTPUpgrade)
//! - `socks` / `http`

use std::io;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use aes::cipher::{BlockEncrypt, KeyInit};
use aes::Aes128;
use futures_util::{Sink, Stream};
use md5::{Digest as Md5Digest, Md5};
use ring::aead::{self, Aad, LessSafeKey, Nonce, UnboundKey};
use ring::hkdf;
use ring::rand::{SecureRandom, SystemRandom};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{ClientConfig, DigitallySignedStruct, RootCertStore, SignatureScheme};
use serde_json::Value;
use sha2::{Sha224, Sha256};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tokio_rustls::TlsConnector;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::protocol::Message;
use tokio_tungstenite::WebSocketStream;

pub trait AsyncStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> AsyncStream for T {}
pub type BoxStream = Pin<Box<dyn AsyncStream>>;

/// Handle to a live in-process local mixed proxy server (`127.0.0.1:<listen_port>`).
/// Dropping this handle cleanly shuts down the listener and background accept loop.
pub struct InProcessProxyHandle {
    pub listen_port: u16,
    shutdown_tx: watch::Sender<bool>,
    accept_task: JoinHandle<()>,
}

impl Drop for InProcessProxyHandle {
    fn drop(&mut self) {
        let _ = self.shutdown_tx.send(true);
        self.accept_task.abort();
    }
}

/// Returns `true` when `ob` (a sing-box style outbound JSON object produced by `proxy_sub`)
/// can be executed natively in-process without any external `sing-box` binary.
pub fn can_handle_outbound(ob: &Value) -> bool {
    let proto = ob
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_ascii_lowercase();
    let server = ob.get("server").and_then(Value::as_str).unwrap_or("");
    let port = ob.get("server_port").and_then(Value::as_u64).unwrap_or(0);
    if server.trim().is_empty() || port == 0 || port > 65535 {
        return false;
    }

    // Reality requires X25519 uTLS ClientHello impersonation
    if ob
        .pointer("/tls/reality/enabled")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        return false;
    }

    let transport = ob
        .pointer("/transport/type")
        .and_then(Value::as_str)
        .unwrap_or("tcp")
        .to_ascii_lowercase();
    if !matches!(
        transport.as_str(),
        "" | "tcp" | "ws" | "websocket" | "httpupgrade"
    ) {
        return false;
    }

    match proto.as_str() {
        "vless" => {
            let flow = ob.get("flow").and_then(Value::as_str).unwrap_or("").trim();
            if !flow.is_empty() {
                return false;
            }
            ob.get("uuid")
                .and_then(Value::as_str)
                .and_then(|u| uuid::Uuid::parse_str(u.trim()).ok())
                .is_some()
        }
        "trojan" => ob
            .get("password")
            .and_then(Value::as_str)
            .is_some_and(|p| !p.is_empty()),
        "shadowsocks" | "ss" => {
            let method = ob
                .get("method")
                .and_then(Value::as_str)
                .unwrap_or("aes-256-gcm")
                .to_ascii_lowercase();
            matches!(
                method.as_str(),
                "aes-128-gcm"
                    | "aes-256-gcm"
                    | "chacha20-ietf-poly1305"
                    | "chacha20-poly1305"
                    | "none"
                    | "plain"
            )
        }
        "vmess" => {
            let sec = ob
                .get("security")
                .and_then(Value::as_str)
                .unwrap_or("auto")
                .to_ascii_lowercase();
            let valid_uuid = ob
                .get("uuid")
                .and_then(Value::as_str)
                .and_then(|u| uuid::Uuid::parse_str(u.trim()).ok())
                .is_some();
            valid_uuid
                && matches!(
                    sec.as_str(),
                    "" | "auto" | "aes-128-gcm" | "chacha20-poly1305" | "none" | "zero"
                )
        }
        "socks" | "http" => true,
        _ => false,
    }
}

#[derive(Debug, Clone)]
enum TargetAddr {
    Ipv4(Ipv4Addr, u16),
    Ipv6(Ipv6Addr, u16),
    Domain(String, u16),
}

impl TargetAddr {
    fn port(&self) -> u16 {
        match self {
            Self::Ipv4(_, p) | Self::Ipv6(_, p) | Self::Domain(_, p) => *p,
        }
    }

    fn from_host_port(host: &str, port: u16) -> Self {
        let trimmed = host.trim().trim_matches(['[', ']']);
        if let Ok(ip) = trimmed.parse::<IpAddr>() {
            match ip {
                IpAddr::V4(v4) => Self::Ipv4(v4, port),
                IpAddr::V6(v6) => Self::Ipv6(v6, port),
            }
        } else {
            Self::Domain(trimmed.to_string(), port)
        }
    }

    fn encode_socks5(&self, out: &mut Vec<u8>) {
        match self {
            Self::Ipv4(ip, port) => {
                out.push(0x01);
                out.extend_from_slice(&ip.octets());
                out.extend_from_slice(&port.to_be_bytes());
            }
            Self::Domain(domain, port) => {
                let bytes = domain.as_bytes();
                let len = bytes.len().min(255);
                out.push(0x03);
                out.push(len as u8);
                out.extend_from_slice(&bytes[..len]);
                out.extend_from_slice(&port.to_be_bytes());
            }
            Self::Ipv6(ip, port) => {
                out.push(0x04);
                out.extend_from_slice(&ip.octets());
                out.extend_from_slice(&port.to_be_bytes());
            }
        }
    }

    /// VLESS & VMess address encoding: port comes BEFORE address type, and
    /// `1 = IPv4`, `2 = Domain`, `3 = IPv6`.
    fn encode_v2ray_port_addr(&self, out: &mut Vec<u8>) {
        out.extend_from_slice(&self.port().to_be_bytes());
        match self {
            Self::Ipv4(ip, _) => {
                out.push(0x01);
                out.extend_from_slice(&ip.octets());
            }
            Self::Domain(domain, _) => {
                let bytes = domain.as_bytes();
                let len = bytes.len().min(255);
                out.push(0x02);
                out.push(len as u8);
                out.extend_from_slice(&bytes[..len]);
            }
            Self::Ipv6(ip, _) => {
                out.push(0x03);
                out.extend_from_slice(&ip.octets());
            }
        }
    }

    fn host_port_string(&self) -> String {
        match self {
            Self::Ipv4(ip, p) => format!("{ip}:{p}"),
            Self::Ipv6(ip, p) => format!("[{ip}]:{p}"),
            Self::Domain(d, p) => format!("{d}:{p}"),
        }
    }
}

/// Starts a local mixed SOCKS5 + HTTP proxy listener on `127.0.0.1:0` forwarding through `outbound`.
pub async fn start_local_proxy(outbound: Value) -> Result<InProcessProxyHandle, String> {
    if !can_handle_outbound(&outbound) {
        return Err("当前节点协议暂不支持免内核直连".into());
    }
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| format!("无法绑定本地回环代理端口: {e}"))?;
    let listen_port = listener
        .local_addr()
        .map_err(|e| format!("读取回环端口失败: {e}"))?
        .port();

    let (shutdown_tx, mut shutdown_rx) = watch::channel(false);
    let ob_arc = Arc::new(outbound);

    let accept_task = tokio::spawn(async move {
        loop {
            tokio::select! {
                changed = shutdown_rx.changed() => {
                    if changed.is_err() || *shutdown_rx.borrow() {
                        break;
                    }
                }
                accepted = listener.accept() => {
                    let Ok((inbound, _)) = accepted else {
                        continue;
                    };
                    let _ = inbound.set_nodelay(true);
                    let ob = Arc::clone(&ob_arc);
                    let mut conn_shutdown = shutdown_rx.clone();
                    tokio::spawn(async move {
                        tokio::select! {
                            _ = handle_inbound_client(inbound, ob) => {}
                            _ = conn_shutdown.changed() => {}
                        }
                    });
                }
            }
        }
    });

    Ok(InProcessProxyHandle {
        listen_port,
        shutdown_tx,
        accept_task,
    })
}

async fn handle_inbound_client(mut client: TcpStream, outbound: Arc<Value>) -> io::Result<()> {
    let mut first = [0u8; 1];
    tokio::time::timeout(Duration::from_secs(10), client.read_exact(&mut first))
        .await
        .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "inbound handshake timeout"))??;

    if first[0] == 0x05 {
        handle_socks5_inbound(client, &outbound).await
    } else {
        handle_http_inbound(client, first[0], &outbound).await
    }
}

async fn handle_socks5_inbound(mut client: TcpStream, outbound: &Value) -> io::Result<()> {
    let mut nmethods_buf = [0u8; 1];
    client.read_exact(&mut nmethods_buf).await?;
    let mut methods = vec![0u8; nmethods_buf[0] as usize];
    client.read_exact(&mut methods).await?;
    // Respond: SOCKS5, NO AUTHENTICATION REQUIRED (0x00)
    client.write_all(&[0x05, 0x00]).await?;

    let mut hdr = [0u8; 4];
    client.read_exact(&mut hdr).await?;
    if hdr[0] != 0x05 || hdr[1] != 0x01 {
        let _ = client
            .write_all(&[0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
            .await;
        return Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "only SOCKS5 CONNECT supported",
        ));
    }

    let target = match hdr[3] {
        0x01 => {
            let mut ip = [0u8; 4];
            let mut port = [0u8; 2];
            client.read_exact(&mut ip).await?;
            client.read_exact(&mut port).await?;
            TargetAddr::Ipv4(Ipv4Addr::from(ip), u16::from_be_bytes(port))
        }
        0x03 => {
            let mut len = [0u8; 1];
            client.read_exact(&mut len).await?;
            let mut dom = vec![0u8; len[0] as usize];
            let mut port = [0u8; 2];
            client.read_exact(&mut dom).await?;
            client.read_exact(&mut port).await?;
            let host = String::from_utf8_lossy(&dom).into_owned();
            TargetAddr::from_host_port(&host, u16::from_be_bytes(port))
        }
        0x04 => {
            let mut ip = [0u8; 16];
            let mut port = [0u8; 2];
            client.read_exact(&mut ip).await?;
            client.read_exact(&mut port).await?;
            TargetAddr::Ipv6(Ipv6Addr::from(ip), u16::from_be_bytes(port))
        }
        _ => {
            let _ = client
                .write_all(&[0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                .await;
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "unknown SOCKS5 ATYP",
            ));
        }
    };

    let mut remote = match connect_outbound(outbound, &target).await {
        Ok(s) => s,
        Err(e) => {
            let _ = client
                .write_all(&[0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                .await;
            return Err(e);
        }
    };

    client
        .write_all(&[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
        .await?;
    let _ = tokio::io::copy_bidirectional(&mut client, &mut remote).await;
    Ok(())
}

async fn handle_http_inbound(
    mut client: TcpStream,
    first_byte: u8,
    outbound: &Value,
) -> io::Result<()> {
    let mut req_buf = vec![first_byte];
    let mut scratch = [0u8; 2048];
    let header_end = loop {
        if let Some(pos) = find_double_crlf(&req_buf) {
            break pos;
        }
        if req_buf.len() > 16 * 1024 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "HTTP proxy header too large",
            ));
        }
        let n = client.read(&mut scratch).await?;
        if n == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "EOF in HTTP header",
            ));
        }
        req_buf.extend_from_slice(&scratch[..n]);
    };

    let header_str = String::from_utf8_lossy(&req_buf[..header_end]);
    let mut lines = header_str.split("\r\n");
    let first_line = lines.next().unwrap_or("");
    let mut parts = first_line.split_whitespace();
    let method = parts.next().unwrap_or("");
    let raw_target = parts.next().unwrap_or("");
    let version = parts.next().unwrap_or("HTTP/1.1");

    if method.eq_ignore_ascii_case("CONNECT") {
        let (host, port) = parse_authority_host_port(raw_target, 443)?;
        let target = TargetAddr::from_host_port(&host, port);
        let mut remote = connect_outbound(outbound, &target).await?;
        client
            .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            .await?;
        if header_end < req_buf.len() {
            remote.write_all(&req_buf[header_end..]).await?;
        }
        let _ = tokio::io::copy_bidirectional(&mut client, &mut remote).await;
        Ok(())
    } else {
        let parsed = url::Url::parse(raw_target)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e.to_string()))?;
        let host = parsed
            .host_str()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "missing host"))?;
        let port = parsed.port_or_known_default().unwrap_or(80);
        let target = TargetAddr::from_host_port(host, port);
        let mut remote = connect_outbound(outbound, &target).await?;

        let mut rel = parsed.path().to_string();
        if rel.is_empty() {
            rel.push('/');
        }
        if let Some(q) = parsed.query() {
            rel.push('?');
            rel.push_str(q);
        }
        let mut rewritten = format!("{method} {rel} {version}\r\n");
        for line in lines {
            if line.is_empty() {
                continue;
            }
            if line
                .get(..16)
                .is_some_and(|p| p.to_ascii_lowercase().starts_with("proxy-connection"))
            {
                continue;
            }
            rewritten.push_str(line);
            rewritten.push_str("\r\n");
        }
        rewritten.push_str("\r\n");
        remote.write_all(rewritten.as_bytes()).await?;
        if header_end < req_buf.len() {
            remote.write_all(&req_buf[header_end..]).await?;
        }
        let _ = tokio::io::copy_bidirectional(&mut client, &mut remote).await;
        Ok(())
    }
}

fn find_double_crlf(buf: &[u8]) -> Option<usize> {
    buf.windows(4)
        .position(|w| w == b"\r\n\r\n")
        .map(|idx| idx + 4)
}

fn parse_authority_host_port(raw: &str, default_port: u16) -> io::Result<(String, u16)> {
    if let Some(rest) = raw.strip_prefix('[') {
        if let Some((v6, after)) = rest.split_once(']') {
            let port = after
                .strip_prefix(':')
                .and_then(|p| p.parse::<u16>().ok())
                .unwrap_or(default_port);
            return Ok((v6.to_string(), port));
        }
    }
    if let Some((h, p)) = raw.rsplit_once(':') {
        if let Ok(port) = p.parse::<u16>() {
            return Ok((h.to_string(), port));
        }
    }
    Ok((raw.to_string(), default_port))
}

// ============================================================================
// Transport Dialer: TCP -> Optional Rustls TLS -> Optional WS / HTTPUpgrade
// ============================================================================

#[derive(Debug)]
struct InsecureCertVerifier;

impl ServerCertVerifier for InsecureCertVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

async fn dial_transport(outbound: &Value) -> io::Result<BoxStream> {
    let server = outbound
        .get("server")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    let port = outbound
        .get("server_port")
        .and_then(Value::as_u64)
        .unwrap_or(0) as u16;
    if server.is_empty() || port == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid server/port",
        ));
    }

    let tcp = tokio::time::timeout(Duration::from_secs(10), TcpStream::connect((server, port)))
        .await
        .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "upstream TCP connect timeout"))??;
    let _ = tcp.set_nodelay(true);

    let transport_type = outbound
        .pointer("/transport/type")
        .and_then(Value::as_str)
        .unwrap_or("tcp")
        .to_ascii_lowercase();
    let is_ws_like = matches!(transport_type.as_str(), "ws" | "websocket" | "httpupgrade");

    let tls_enabled = outbound
        .pointer("/tls/enabled")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let mut stream: BoxStream = if tls_enabled {
        let insecure = outbound
            .pointer("/tls/insecure")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let sni = outbound
            .pointer("/tls/server_name")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or(server);

        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let builder = ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .map_err(|e| io::Error::other(e.to_string()))?;

        let mut tls_cfg = if insecure {
            builder
                .dangerous()
                .with_custom_certificate_verifier(Arc::new(InsecureCertVerifier))
                .with_no_client_auth()
        } else {
            let mut roots = RootCertStore::empty();
            roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
            builder.with_root_certificates(roots).with_no_client_auth()
        };

        if let Some(alpn_arr) = outbound.pointer("/tls/alpn").and_then(Value::as_array) {
            let mut alpn: Vec<Vec<u8>> = alpn_arr
                .iter()
                .filter_map(Value::as_str)
                .filter(|a| !(is_ws_like && a.eq_ignore_ascii_case("h2")))
                .map(|a| a.as_bytes().to_vec())
                .collect();
            if is_ws_like && alpn.is_empty() {
                alpn.push(b"http/1.1".to_vec());
            }
            tls_cfg.alpn_protocols = alpn;
        } else if is_ws_like {
            tls_cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
        }

        let server_name = ServerName::try_from(sni.to_string())
            .or_else(|_| ServerName::try_from(server.to_string()))
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e.to_string()))?;

        let connector = TlsConnector::from(Arc::new(tls_cfg));
        let tls_stream =
            tokio::time::timeout(Duration::from_secs(10), connector.connect(server_name, tcp))
                .await
                .map_err(|_| {
                    io::Error::new(io::ErrorKind::TimedOut, "upstream TLS handshake timeout")
                })??;
        Box::pin(tls_stream)
    } else {
        Box::pin(tcp)
    };

    match transport_type.as_str() {
        "ws" | "websocket" => {
            let raw_path = outbound
                .pointer("/transport/path")
                .and_then(Value::as_str)
                .unwrap_or("/");
            let clean_path = sanitize_ws_path(raw_path);
            let host = outbound
                .pointer("/transport/headers/Host")
                .or_else(|| outbound.pointer("/transport/headers/host"))
                .or_else(|| outbound.pointer("/transport/host"))
                .or_else(|| outbound.pointer("/tls/server_name"))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .unwrap_or(server);

            let ws_uri = format!("ws://{host}{clean_path}");
            let mut req = ws_uri
                .into_client_request()
                .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e.to_string()))?;
            if let Ok(hv) = http::HeaderValue::from_str(host) {
                req.headers_mut().insert(http::header::HOST, hv);
            }
            if let Ok(ua) = http::HeaderValue::from_str("Mozilla/5.0") {
                req.headers_mut().insert(http::header::USER_AGENT, ua);
            }
            if let Some(hdrs) = outbound
                .pointer("/transport/headers")
                .and_then(Value::as_object)
            {
                for (k, v) in hdrs {
                    if let (Ok(hn), Some(Ok(hv))) = (
                        http::header::HeaderName::from_bytes(k.as_bytes()),
                        v.as_str().map(http::HeaderValue::from_str),
                    ) {
                        req.headers_mut().insert(hn, hv);
                    }
                }
            }

            let (ws_stream, _) = tokio::time::timeout(
                Duration::from_secs(10),
                tokio_tungstenite::client_async(req, stream),
            )
            .await
            .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "WS upgrade timeout"))?
            .map_err(|e| io::Error::other(format!("WS handshake failed: {e}")))?;
            Ok(Box::pin(WsByteStream::new(ws_stream)))
        }
        "httpupgrade" => {
            let raw_path = outbound
                .pointer("/transport/path")
                .and_then(Value::as_str)
                .unwrap_or("/");
            let clean_path = sanitize_ws_path(raw_path);
            let host = outbound
                .pointer("/transport/host")
                .or_else(|| outbound.pointer("/transport/headers/Host"))
                .or_else(|| outbound.pointer("/tls/server_name"))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .unwrap_or(server);
            let upgrade_req = format!(
                "GET {clean_path} HTTP/1.1\r\nHost: {host}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nUser-Agent: Mozilla/5.0\r\n\r\n"
            );
            stream.write_all(upgrade_req.as_bytes()).await?;
            stream.flush().await?;

            let mut resp = Vec::with_capacity(512);
            let mut buf = [0u8; 512];
            let end = loop {
                if let Some(pos) = find_double_crlf(&resp) {
                    break pos;
                }
                if resp.len() > 8192 {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "httpupgrade response too large",
                    ));
                }
                let n = stream.read(&mut buf).await?;
                if n == 0 {
                    return Err(io::Error::new(
                        io::ErrorKind::UnexpectedEof,
                        "httpupgrade closed",
                    ));
                }
                resp.extend_from_slice(&buf[..n]);
            };
            let status_line = String::from_utf8_lossy(&resp[..end]);
            if !status_line.starts_with("HTTP/1.1 101") && !status_line.starts_with("HTTP/1.0 101")
            {
                return Err(io::Error::other("httpupgrade non-101 status"));
            }
            let leftover = resp[end..].to_vec();
            Ok(Box::pin(PrefixedStream {
                inner: stream,
                read_prefix: leftover,
                prefix_pos: 0,
            }))
        }
        _ => Ok(stream),
    }
}

/// Strips V2Ray `?ed=2048` early-data hint query parameters while preserving path & normal queries.
fn sanitize_ws_path(raw: &str) -> String {
    let p = if raw.starts_with('/') {
        raw.to_string()
    } else {
        format!("/{raw}")
    };
    let Some((path_only, query)) = p.split_once('?') else {
        return p;
    };
    let kept: Vec<&str> = query
        .split('&')
        .filter(|kv| !kv.is_empty() && !kv.starts_with("ed="))
        .collect();
    if kept.is_empty() {
        path_only.to_string()
    } else {
        format!("{path_only}?{}", kept.join("&"))
    }
}

struct PrefixedStream {
    inner: BoxStream,
    read_prefix: Vec<u8>,
    prefix_pos: usize,
}

impl AsyncRead for PrefixedStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if self.prefix_pos < self.read_prefix.len() {
            let avail = &self.read_prefix[self.prefix_pos..];
            let n = avail.len().min(buf.remaining());
            buf.put_slice(&avail[..n]);
            self.prefix_pos += n;
            if self.prefix_pos >= self.read_prefix.len() {
                self.read_prefix.clear();
                self.prefix_pos = 0;
            }
            return Poll::Ready(Ok(()));
        }
        self.inner.as_mut().poll_read(cx, buf)
    }
}

impl AsyncWrite for PrefixedStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        self.inner.as_mut().poll_write(cx, buf)
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.inner.as_mut().poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.inner.as_mut().poll_shutdown(cx)
    }
}

/// Adapts a `WebSocketStream<BoxStream>` into a clean `AsyncRead + AsyncWrite` byte stream.
struct WsByteStream {
    ws: WebSocketStream<BoxStream>,
    rx_buf: Vec<u8>,
    rx_pos: usize,
    pending_send: Option<Message>,
}

impl WsByteStream {
    fn new(ws: WebSocketStream<BoxStream>) -> Self {
        Self {
            ws,
            rx_buf: Vec::new(),
            rx_pos: 0,
            pending_send: None,
        }
    }
}

impl AsyncRead for WsByteStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        loop {
            if self.rx_pos < self.rx_buf.len() {
                let avail = &self.rx_buf[self.rx_pos..];
                let n = avail.len().min(buf.remaining());
                buf.put_slice(&avail[..n]);
                self.rx_pos += n;
                if self.rx_pos >= self.rx_buf.len() {
                    self.rx_buf.clear();
                    self.rx_pos = 0;
                }
                return Poll::Ready(Ok(()));
            }
            match Pin::new(&mut self.ws).poll_next(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(None) => return Poll::Ready(Ok(())),
                Poll::Ready(Some(Err(e))) => {
                    return Poll::Ready(Err(io::Error::other(e.to_string())));
                }
                Poll::Ready(Some(Ok(msg))) => match msg {
                    Message::Binary(b) if !b.is_empty() => {
                        self.rx_buf = b;
                        self.rx_pos = 0;
                    }
                    Message::Text(t) if !t.is_empty() => {
                        self.rx_buf = t.as_bytes().to_vec();
                        self.rx_pos = 0;
                    }
                    Message::Close(_) => return Poll::Ready(Ok(())),
                    _ => continue,
                },
            }
        }
    }
}

impl AsyncWrite for WsByteStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        if buf.is_empty() {
            return Poll::Ready(Ok(0));
        }
        if self.pending_send.is_none() {
            match Pin::new(&mut self.ws).poll_ready(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(io::Error::other(e.to_string()))),
                Poll::Ready(Ok(())) => {
                    self.pending_send = Some(Message::Binary(buf.to_vec()));
                }
            }
        }
        if let Some(msg) = self.pending_send.take() {
            Pin::new(&mut self.ws)
                .start_send(msg)
                .map_err(|e| io::Error::other(e.to_string()))?;
        }
        let _ = Pin::new(&mut self.ws).poll_flush(cx);
        Poll::Ready(Ok(buf.len()))
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.ws)
            .poll_flush(cx)
            .map_err(|e| io::Error::other(e.to_string()))
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.ws)
            .poll_close(cx)
            .map_err(|e| io::Error::other(e.to_string()))
    }
}

// ============================================================================
// Outbound Protocol Handshakes (VLESS, Trojan, Shadowsocks AEAD, VMess AEAD)
// ============================================================================

async fn connect_outbound(outbound: &Value, target: &TargetAddr) -> io::Result<BoxStream> {
    let proto = outbound
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_ascii_lowercase();
    let transport = dial_transport(outbound).await?;

    match proto.as_str() {
        "vless" => connect_vless(transport, outbound, target).await,
        "trojan" => connect_trojan(transport, outbound, target).await,
        "shadowsocks" | "ss" => connect_shadowsocks(transport, outbound, target).await,
        "vmess" => connect_vmess_aead(transport, outbound, target).await,
        "socks" => connect_socks5_outbound(transport, outbound, target).await,
        "http" => connect_http_outbound(transport, outbound, target).await,
        _ => Err(io::Error::new(
            io::ErrorKind::Unsupported,
            format!("unsupported outbound protocol: {proto}"),
        )),
    }
}

// --- 1. VLESS v0 ---

async fn connect_vless(
    mut stream: BoxStream,
    outbound: &Value,
    target: &TargetAddr,
) -> io::Result<BoxStream> {
    let uuid_str = outbound
        .get("uuid")
        .and_then(Value::as_str)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "missing VLESS uuid"))?;
    let uuid = uuid::Uuid::parse_str(uuid_str.trim())
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e.to_string()))?;

    let mut hdr = Vec::with_capacity(64);
    hdr.push(0x00); // VLESS version 0
    hdr.extend_from_slice(uuid.as_bytes());
    hdr.push(0x00); // addons length = 0
    hdr.push(0x01); // command = TCP (0x01)
    target.encode_v2ray_port_addr(&mut hdr);

    stream.write_all(&hdr).await?;
    stream.flush().await?;

    Ok(Box::pin(VlessStream {
        inner: stream,
        hdr_buf: Vec::with_capacity(4),
        addons_remaining: None,
        header_done: false,
    }))
}

struct VlessStream {
    inner: BoxStream,
    hdr_buf: Vec<u8>,
    addons_remaining: Option<usize>,
    header_done: bool,
}

impl AsyncRead for VlessStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        while !self.header_done {
            if let Some(rem) = self.addons_remaining {
                if rem == 0 {
                    self.header_done = true;
                    break;
                }
                let mut skip = vec![0u8; rem.min(256)];
                let mut rb = ReadBuf::new(&mut skip);
                match self.inner.as_mut().poll_read(cx, &mut rb) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                    Poll::Ready(Ok(())) => {
                        let n = rb.filled().len();
                        if n == 0 {
                            return Poll::Ready(Err(io::Error::new(
                                io::ErrorKind::UnexpectedEof,
                                "EOF in VLESS response addons",
                            )));
                        }
                        self.addons_remaining = Some(rem - n);
                    }
                }
            } else {
                let need = 2 - self.hdr_buf.len();
                let mut tmp = [0u8; 2];
                let mut rb = ReadBuf::new(&mut tmp[..need]);
                match self.inner.as_mut().poll_read(cx, &mut rb) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                    Poll::Ready(Ok(())) => {
                        let filled = rb.filled();
                        if filled.is_empty() {
                            return Poll::Ready(Err(io::Error::new(
                                io::ErrorKind::UnexpectedEof,
                                "EOF before VLESS response header",
                            )));
                        }
                        self.hdr_buf.extend_from_slice(filled);
                        if self.hdr_buf.len() == 2 {
                            let addons_len = self.hdr_buf[1] as usize;
                            if addons_len == 0 {
                                self.header_done = true;
                            } else {
                                self.addons_remaining = Some(addons_len);
                            }
                        }
                    }
                }
            }
        }
        self.inner.as_mut().poll_read(cx, buf)
    }
}

impl AsyncWrite for VlessStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        self.inner.as_mut().poll_write(cx, buf)
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.inner.as_mut().poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.inner.as_mut().poll_shutdown(cx)
    }
}

// --- 2. Trojan (SHA-224 hex + CRLF + SOCKS5 cmd/addr + CRLF) ---

async fn connect_trojan(
    mut stream: BoxStream,
    outbound: &Value,
    target: &TargetAddr,
) -> io::Result<BoxStream> {
    let password = outbound
        .get("password")
        .and_then(Value::as_str)
        .unwrap_or("");
    let digest = Sha224::digest(password.as_bytes());
    let mut hex_pw = String::with_capacity(56);
    for b in digest {
        use std::fmt::Write;
        let _ = write!(&mut hex_pw, "{b:02x}");
    }

    let mut hdr = Vec::with_capacity(96);
    hdr.extend_from_slice(hex_pw.as_bytes());
    hdr.extend_from_slice(b"\r\n");
    hdr.push(0x01); // CONNECT
    target.encode_socks5(&mut hdr);
    hdr.extend_from_slice(b"\r\n");

    stream.write_all(&hdr).await?;
    stream.flush().await?;
    Ok(stream)
}

// --- 3. Shadowsocks AEAD (`aes-128-gcm`, `aes-256-gcm`, `chacha20-ietf-poly1305`) ---

fn ss_evp_bytes_to_key(password: &[u8], key_len: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(key_len + 16);
    let mut prev: Vec<u8> = Vec::new();
    while out.len() < key_len {
        let mut md5 = Md5::new();
        md5.update(&prev);
        md5.update(password);
        prev = md5.finalize().to_vec();
        out.extend_from_slice(&prev);
    }
    out.truncate(key_len);
    out
}

struct SsHkdfLen(usize);
impl hkdf::KeyType for SsHkdfLen {
    fn len(&self) -> usize {
        self.0
    }
}

fn ss_derive_subkey(
    alg: &'static aead::Algorithm,
    master_key: &[u8],
    salt: &[u8],
) -> io::Result<LessSafeKey> {
    let hkdf_salt = hkdf::Salt::new(hkdf::HKDF_SHA1_FOR_LEGACY_USE_ONLY, salt);
    let prk = hkdf_salt.extract(master_key);
    let info: &[&[u8]] = &[b"ss-subkey"];
    let okm = prk
        .expand(info, SsHkdfLen(alg.key_len()))
        .map_err(|_| io::Error::other("HKDF-SHA1 expand failed"))?;
    let mut subkey = vec![0u8; alg.key_len()];
    okm.fill(&mut subkey)
        .map_err(|_| io::Error::other("HKDF-SHA1 fill failed"))?;
    let unbound =
        UnboundKey::new(alg, &subkey).map_err(|_| io::Error::other("invalid AEAD key"))?;
    Ok(LessSafeKey::new(unbound))
}

fn ss_nonce_bytes(counter: &mut u64) -> [u8; 12] {
    let mut n = [0u8; 12];
    n[..8].copy_from_slice(&counter.to_le_bytes());
    *counter = counter.wrapping_add(1);
    n
}

fn ss_seal_chunk(
    key: &LessSafeKey,
    nonce_ctr: &mut u64,
    plaintext: &[u8],
    out: &mut Vec<u8>,
) -> io::Result<()> {
    let len = plaintext.len();
    debug_assert!(len <= 0x3FFF);
    let mut len_block = (len as u16).to_be_bytes().to_vec();
    let n1 = Nonce::assume_unique_for_key(ss_nonce_bytes(nonce_ctr));
    key.seal_in_place_append_tag(n1, Aad::empty(), &mut len_block)
        .map_err(|_| io::Error::other("SS AEAD seal length failed"))?;
    out.extend_from_slice(&len_block);

    let mut payload_block = plaintext.to_vec();
    let n2 = Nonce::assume_unique_for_key(ss_nonce_bytes(nonce_ctr));
    key.seal_in_place_append_tag(n2, Aad::empty(), &mut payload_block)
        .map_err(|_| io::Error::other("SS AEAD seal payload failed"))?;
    out.extend_from_slice(&payload_block);
    Ok(())
}

async fn connect_shadowsocks(
    mut stream: BoxStream,
    outbound: &Value,
    target: &TargetAddr,
) -> io::Result<BoxStream> {
    let method = outbound
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or("aes-256-gcm")
        .to_ascii_lowercase();
    let password = outbound
        .get("password")
        .and_then(Value::as_str)
        .unwrap_or("");

    if matches!(method.as_str(), "none" | "plain") {
        let mut addr = Vec::with_capacity(32);
        target.encode_socks5(&mut addr);
        stream.write_all(&addr).await?;
        stream.flush().await?;
        return Ok(stream);
    }

    let (alg, salt_len): (&'static aead::Algorithm, usize) = match method.as_str() {
        "aes-128-gcm" => (&aead::AES_128_GCM, 16),
        "aes-256-gcm" => (&aead::AES_256_GCM, 32),
        "chacha20-ietf-poly1305" | "chacha20-poly1305" => (&aead::CHACHA20_POLY1305, 32),
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                format!("unsupported SS cipher: {method}"),
            ))
        }
    };

    let master_key = ss_evp_bytes_to_key(password.as_bytes(), alg.key_len());
    let rng = SystemRandom::new();
    let mut tx_salt = vec![0u8; salt_len];
    rng.fill(&mut tx_salt)
        .map_err(|_| io::Error::other("RNG failed"))?;
    let tx_key = ss_derive_subkey(alg, &master_key, &tx_salt)?;
    let mut tx_nonce = 0u64;

    let mut target_plain = Vec::with_capacity(64);
    target.encode_socks5(&mut target_plain);

    let mut init_wire = Vec::with_capacity(salt_len + target_plain.len() + 34);
    init_wire.extend_from_slice(&tx_salt);
    ss_seal_chunk(&tx_key, &mut tx_nonce, &target_plain, &mut init_wire)?;
    stream.write_all(&init_wire).await?;
    stream.flush().await?;

    Ok(Box::pin(SsAeadStream {
        inner: stream,
        alg,
        master_key,
        salt_len,
        tx_key,
        tx_nonce,
        tx_pending: Vec::new(),
        tx_pending_pos: 0,
        tx_plain_len: 0,
        rx_key: None,
        rx_nonce: 0,
        rx_raw: Vec::with_capacity(4096),
        rx_expect_payload_len: None,
        rx_plain: Vec::new(),
        rx_plain_pos: 0,
    }))
}

struct SsAeadStream {
    inner: BoxStream,
    alg: &'static aead::Algorithm,
    master_key: Vec<u8>,
    salt_len: usize,
    tx_key: LessSafeKey,
    tx_nonce: u64,
    tx_pending: Vec<u8>,
    tx_pending_pos: usize,
    tx_plain_len: usize,
    rx_key: Option<LessSafeKey>,
    rx_nonce: u64,
    rx_raw: Vec<u8>,
    rx_expect_payload_len: Option<usize>,
    rx_plain: Vec<u8>,
    rx_plain_pos: usize,
}

impl SsAeadStream {
    fn poll_drain_tx(&mut self, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        while self.tx_pending_pos < self.tx_pending.len() {
            let n = match self
                .inner
                .as_mut()
                .poll_write(cx, &self.tx_pending[self.tx_pending_pos..])
            {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Ready(Ok(0)) => {
                    return Poll::Ready(Err(io::Error::new(
                        io::ErrorKind::WriteZero,
                        "SS upstream write zero",
                    )))
                }
                Poll::Ready(Ok(n)) => n,
            };
            self.tx_pending_pos += n;
        }
        self.tx_pending.clear();
        self.tx_pending_pos = 0;
        Poll::Ready(Ok(()))
    }
}

impl AsyncRead for SsAeadStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        loop {
            if self.rx_plain_pos < self.rx_plain.len() {
                let avail = &self.rx_plain[self.rx_plain_pos..];
                let n = avail.len().min(buf.remaining());
                buf.put_slice(&avail[..n]);
                self.rx_plain_pos += n;
                if self.rx_plain_pos >= self.rx_plain.len() {
                    self.rx_plain.clear();
                    self.rx_plain_pos = 0;
                }
                return Poll::Ready(Ok(()));
            }

            if self.rx_key.is_none() && self.rx_raw.len() >= self.salt_len {
                let salt_len = self.salt_len;
                let salt: Vec<u8> = self.rx_raw.drain(..salt_len).collect();
                let key = ss_derive_subkey(self.alg, &self.master_key, &salt)?;
                self.rx_key = Some(key);
            }

            if self.rx_key.is_some() {
                if self.rx_expect_payload_len.is_none() && self.rx_raw.len() >= 18 {
                    let mut enc_len: Vec<u8> = self.rx_raw.drain(..18).collect();
                    let nonce = Nonce::assume_unique_for_key(ss_nonce_bytes(&mut self.rx_nonce));
                    let dec = self
                        .rx_key
                        .as_ref()
                        .unwrap()
                        .open_in_place(nonce, Aad::empty(), &mut enc_len)
                        .map_err(|_| {
                            io::Error::new(io::ErrorKind::InvalidData, "SS AEAD length auth failed")
                        })?;
                    let plen = (u16::from_be_bytes([dec[0], dec[1]]) & 0x3FFF) as usize;
                    self.rx_expect_payload_len = Some(plen);
                }

                if let Some(plen) = self.rx_expect_payload_len {
                    if self.rx_raw.len() >= plen + 16 {
                        let mut enc_pay: Vec<u8> = self.rx_raw.drain(..plen + 16).collect();
                        let nonce =
                            Nonce::assume_unique_for_key(ss_nonce_bytes(&mut self.rx_nonce));
                        let dec = self
                            .rx_key
                            .as_ref()
                            .unwrap()
                            .open_in_place(nonce, Aad::empty(), &mut enc_pay)
                            .map_err(|_| {
                                io::Error::new(
                                    io::ErrorKind::InvalidData,
                                    "SS AEAD payload auth failed",
                                )
                            })?;
                        self.rx_plain = dec.to_vec();
                        self.rx_plain_pos = 0;
                        self.rx_expect_payload_len = None;
                        continue;
                    }
                }
            }

            let mut tmp = [0u8; 8192];
            let mut rb = ReadBuf::new(&mut tmp);
            match self.inner.as_mut().poll_read(cx, &mut rb) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Ready(Ok(())) => {
                    let filled = rb.filled();
                    if filled.is_empty() {
                        if self.rx_raw.is_empty() && self.rx_expect_payload_len.is_none() {
                            return Poll::Ready(Ok(()));
                        }
                        return Poll::Ready(Err(io::Error::new(
                            io::ErrorKind::UnexpectedEof,
                            "truncated SS AEAD frame",
                        )));
                    }
                    self.rx_raw.extend_from_slice(filled);
                }
            }
        }
    }
}

impl AsyncWrite for SsAeadStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        if buf.is_empty() {
            return Poll::Ready(Ok(0));
        }
        if !self.tx_pending.is_empty() {
            match self.poll_drain_tx(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Ready(Ok(())) => {
                    if self.tx_plain_len > 0 {
                        let ack = self.tx_plain_len;
                        self.tx_plain_len = 0;
                        return Poll::Ready(Ok(ack));
                    }
                }
            }
        }
        let chunk = &buf[..buf.len().min(0x3FFF)];
        let mut sealed = Vec::with_capacity(chunk.len() + 34);
        let mut ctr = self.tx_nonce;
        ss_seal_chunk(&self.tx_key, &mut ctr, chunk, &mut sealed)?;
        self.tx_nonce = ctr;
        self.tx_pending = sealed;
        self.tx_pending_pos = 0;
        self.tx_plain_len = chunk.len();

        match self.poll_drain_tx(cx) {
            Poll::Pending => Poll::Pending,
            Poll::Ready(Err(e)) => Poll::Ready(Err(e)),
            Poll::Ready(Ok(())) => {
                let ack = self.tx_plain_len;
                self.tx_plain_len = 0;
                Poll::Ready(Ok(ack))
            }
        }
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        match self.poll_drain_tx(cx) {
            Poll::Pending => return Poll::Pending,
            Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
            Poll::Ready(Ok(())) => {}
        }
        self.inner.as_mut().poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let _ = self.poll_drain_tx(cx);
        self.inner.as_mut().poll_shutdown(cx)
    }
}

// --- 4. VMess AEAD (V2Ray / Xray / Sing-box modern AEAD specification) ---

fn hmac_32<F: Fn(&[u8]) -> [u8; 32]>(hash_fn: &F, key: &[u8], data: &[u8]) -> [u8; 32] {
    let mut k_block = [0u8; 64];
    if key.len() > 64 {
        let hk = hash_fn(key);
        k_block[..32].copy_from_slice(&hk);
    } else {
        k_block[..key.len()].copy_from_slice(key);
    }
    let mut ipad = [0x36u8; 64];
    let mut opad = [0x5cu8; 64];
    for i in 0..64 {
        ipad[i] ^= k_block[i];
        opad[i] ^= k_block[i];
    }
    let mut inner_in = Vec::with_capacity(64 + data.len());
    inner_in.extend_from_slice(&ipad);
    inner_in.extend_from_slice(data);
    let inner = hash_fn(&inner_in);

    let mut outer_in = [0u8; 96];
    outer_in[..64].copy_from_slice(&opad);
    outer_in[64..].copy_from_slice(&inner);
    hash_fn(&outer_in)
}

fn vmess_kdf(key: &[u8], path: &[&[u8]]) -> [u8; 32] {
    fn eval_level(depth: usize, path: &[&[u8]], data: &[u8]) -> [u8; 32] {
        if depth == 0 {
            let sha = |inp: &[u8]| -> [u8; 32] { Sha256::digest(inp).into() };
            hmac_32(&sha, b"VMess AEAD KDF", data)
        } else {
            let prev = |inp: &[u8]| -> [u8; 32] { eval_level(depth - 1, path, inp) };
            hmac_32(&prev, path[depth - 1], data)
        }
    }
    eval_level(path.len(), path, key)
}

fn vmess_cmd_key(uuid: &uuid::Uuid) -> [u8; 16] {
    let mut md5 = Md5::new();
    md5.update(uuid.as_bytes());
    md5.update(b"c48619fe-8f02-49e0-b9e9-edf763e17e21");
    md5.finalize().into()
}

fn fnv1a_32(data: &[u8]) -> u32 {
    let mut h: u32 = 0x811c9dc5;
    for &b in data {
        h ^= b as u32;
        h = h.wrapping_mul(0x01000193);
    }
    h
}

fn vmess_chacha_key_from_16(key16: &[u8; 16]) -> [u8; 32] {
    let d1: [u8; 16] = Md5::digest(key16).into();
    let d2: [u8; 16] = Md5::digest(d1).into();
    let mut out = [0u8; 32];
    out[..16].copy_from_slice(&d1);
    out[16..].copy_from_slice(&d2);
    out
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum VmessBodyCipher {
    Aes128Gcm,
    ChaCha20Poly1305,
    None,
}

async fn connect_vmess_aead(
    mut stream: BoxStream,
    outbound: &Value,
    target: &TargetAddr,
) -> io::Result<BoxStream> {
    let uuid_str = outbound
        .get("uuid")
        .and_then(Value::as_str)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "missing VMess uuid"))?;
    let uuid = uuid::Uuid::parse_str(uuid_str.trim())
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e.to_string()))?;
    let sec_str = outbound
        .get("security")
        .and_then(Value::as_str)
        .unwrap_or("auto")
        .to_ascii_lowercase();

    let (body_cipher, sec_byte) = match sec_str.as_str() {
        "chacha20-poly1305" => (VmessBodyCipher::ChaCha20Poly1305, 0x04u8),
        "none" | "zero" => (VmessBodyCipher::None, 0x05u8),
        _ => (VmessBodyCipher::Aes128Gcm, 0x03u8),
    };

    let rng = SystemRandom::new();
    let mut rnd = [0u8; 45];
    rng.fill(&mut rnd)
        .map_err(|_| io::Error::other("RNG failed"))?;

    let mut body_iv = [0u8; 16];
    let mut body_key = [0u8; 16];
    body_iv.copy_from_slice(&rnd[0..16]);
    body_key.copy_from_slice(&rnd[16..32]);
    let resp_v = rnd[32];
    let mut conn_nonce = [0u8; 8];
    conn_nonce.copy_from_slice(&rnd[33..41]);
    let mut auth_rand = [0u8; 4];
    auth_rand.copy_from_slice(&rnd[41..45]);

    let cmd_key = vmess_cmd_key(&uuid);

    // 1. Build 16-byte AES-128-ECB encrypted AuthID
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let mut auth_plain = [0u8; 16];
    auth_plain[0..8].copy_from_slice(&ts.to_be_bytes());
    auth_plain[8..12].copy_from_slice(&auth_rand);
    let crc = crc32fast::hash(&auth_plain[0..12]);
    auth_plain[12..16].copy_from_slice(&crc.to_be_bytes());

    let auth_aes_key = vmess_kdf(&cmd_key, &[b"AES Auth ID Encryption"]);
    let ecb = Aes128::new_from_slice(&auth_aes_key[..16])
        .map_err(|_| io::Error::other("AES128 init failed"))?;
    let mut auth_id_block = aes::Block::clone_from_slice(&auth_plain);
    ecb.encrypt_block(&mut auth_id_block);
    let mut auth_id = [0u8; 16];
    auth_id.copy_from_slice(&auth_id_block);

    // 2. Build VMess request header plaintext
    let mut req_hdr = Vec::with_capacity(96);
    req_hdr.push(0x01); // version = 1
    req_hdr.extend_from_slice(&body_iv);
    req_hdr.extend_from_slice(&body_key);
    req_hdr.push(resp_v);
    req_hdr.push(0x01); // Option S (ChunkStream = 0x01)
    req_hdr.push(sec_byte); // pad_len = 0, security
    req_hdr.push(0x00); // reserved
    req_hdr.push(0x01); // Cmd TCP
    target.encode_v2ray_port_addr(&mut req_hdr);
    let csum = fnv1a_32(&req_hdr);
    req_hdr.extend_from_slice(&csum.to_be_bytes());

    // 3. Seal 2-byte header length + header payload using VMess Header AEAD KDF
    let len_key_raw = vmess_kdf(
        &cmd_key,
        &[b"VMess Header AEAD Key_Length", &auth_id, &conn_nonce],
    );
    let len_iv_raw = vmess_kdf(
        &cmd_key,
        &[b"VMess Header AEAD Nonce_Length", &auth_id, &conn_nonce],
    );
    let mut enc_hdr_len = (req_hdr.len() as u16).to_be_bytes().to_vec();
    seal_aes128_gcm(
        &len_key_raw[..16],
        &len_iv_raw[..12],
        &auth_id,
        &mut enc_hdr_len,
    )?;

    let pay_key_raw = vmess_kdf(&cmd_key, &[b"VMess Header AEAD Key", &auth_id, &conn_nonce]);
    let pay_iv_raw = vmess_kdf(
        &cmd_key,
        &[b"VMess Header AEAD Nonce", &auth_id, &conn_nonce],
    );
    let mut enc_hdr_pay = req_hdr;
    seal_aes128_gcm(
        &pay_key_raw[..16],
        &pay_iv_raw[..12],
        &auth_id,
        &mut enc_hdr_pay,
    )?;

    let mut wire = Vec::with_capacity(16 + 18 + 8 + enc_hdr_pay.len());
    wire.extend_from_slice(&auth_id);
    wire.extend_from_slice(&enc_hdr_len);
    wire.extend_from_slice(&conn_nonce);
    wire.extend_from_slice(&enc_hdr_pay);
    stream.write_all(&wire).await?;
    stream.flush().await?;

    let resp_key_full: [u8; 32] = Sha256::digest(body_key).into();
    let resp_iv_full: [u8; 32] = Sha256::digest(body_iv).into();
    let mut resp_key = [0u8; 16];
    let mut resp_iv = [0u8; 16];
    resp_key.copy_from_slice(&resp_key_full[..16]);
    resp_iv.copy_from_slice(&resp_iv_full[..16]);

    let tx_aead_key = build_vmess_body_key(body_cipher, &body_key)?;
    let rx_aead_key = build_vmess_body_key(body_cipher, &resp_key)?;

    Ok(Box::pin(VmessAeadStream {
        inner: stream,
        cipher: body_cipher,
        resp_v,
        resp_key,
        resp_iv,
        resp_hdr_done: false,
        resp_hdr_len: None,
        tx_key: tx_aead_key,
        tx_iv: body_iv,
        tx_count: 0,
        tx_pending: Vec::new(),
        tx_pending_pos: 0,
        tx_plain_len: 0,
        rx_key: rx_aead_key,
        rx_iv: resp_iv,
        rx_count: 0,
        rx_raw: Vec::with_capacity(4096),
        rx_plain: Vec::new(),
        rx_plain_pos: 0,
        rx_eof: false,
    }))
}

fn build_vmess_body_key(
    cipher: VmessBodyCipher,
    key16: &[u8; 16],
) -> io::Result<Option<LessSafeKey>> {
    match cipher {
        VmessBodyCipher::None => Ok(None),
        VmessBodyCipher::Aes128Gcm => {
            let ub = UnboundKey::new(&aead::AES_128_GCM, key16)
                .map_err(|_| io::Error::other("VMess AES-128-GCM key error"))?;
            Ok(Some(LessSafeKey::new(ub)))
        }
        VmessBodyCipher::ChaCha20Poly1305 => {
            let k32 = vmess_chacha_key_from_16(key16);
            let ub = UnboundKey::new(&aead::CHACHA20_POLY1305, &k32)
                .map_err(|_| io::Error::other("VMess ChaCha20 key error"))?;
            Ok(Some(LessSafeKey::new(ub)))
        }
    }
}

fn seal_aes128_gcm(key16: &[u8], iv12: &[u8], aad: &[u8], buf: &mut Vec<u8>) -> io::Result<()> {
    let ub = UnboundKey::new(&aead::AES_128_GCM, key16)
        .map_err(|_| io::Error::other("AES128GCM key error"))?;
    let lsk = LessSafeKey::new(ub);
    let mut n = [0u8; 12];
    n.copy_from_slice(&iv12[..12]);
    lsk.seal_in_place_append_tag(Nonce::assume_unique_for_key(n), Aad::from(aad), buf)
        .map_err(|_| io::Error::other("AES128GCM seal error"))
}

fn open_aes128_gcm<'a>(
    key16: &[u8],
    iv12: &[u8],
    aad: &[u8],
    buf: &'a mut [u8],
) -> io::Result<&'a [u8]> {
    let ub = UnboundKey::new(&aead::AES_128_GCM, key16)
        .map_err(|_| io::Error::other("AES128GCM key error"))?;
    let lsk = LessSafeKey::new(ub);
    let mut n = [0u8; 12];
    n.copy_from_slice(&iv12[..12]);
    lsk.open_in_place(Nonce::assume_unique_for_key(n), Aad::from(aad), buf)
        .map(|s| &*s)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "VMess AEAD open failed"))
}

fn vmess_chunk_nonce(count: &mut u16, iv16: &[u8; 16]) -> [u8; 12] {
    let mut n = [0u8; 12];
    n[0..2].copy_from_slice(&count.to_be_bytes());
    n[2..12].copy_from_slice(&iv16[2..12]);
    *count = count.wrapping_add(1);
    n
}

struct VmessAeadStream {
    inner: BoxStream,
    cipher: VmessBodyCipher,
    resp_v: u8,
    resp_key: [u8; 16],
    resp_iv: [u8; 16],
    resp_hdr_done: bool,
    resp_hdr_len: Option<usize>,
    tx_key: Option<LessSafeKey>,
    tx_iv: [u8; 16],
    tx_count: u16,
    tx_pending: Vec<u8>,
    tx_pending_pos: usize,
    tx_plain_len: usize,
    rx_key: Option<LessSafeKey>,
    rx_iv: [u8; 16],
    rx_count: u16,
    rx_raw: Vec<u8>,
    rx_plain: Vec<u8>,
    rx_plain_pos: usize,
    rx_eof: bool,
}

impl VmessAeadStream {
    fn poll_drain_tx(&mut self, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        while self.tx_pending_pos < self.tx_pending.len() {
            let n = match self
                .inner
                .as_mut()
                .poll_write(cx, &self.tx_pending[self.tx_pending_pos..])
            {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Ready(Ok(0)) => {
                    return Poll::Ready(Err(io::Error::new(
                        io::ErrorKind::WriteZero,
                        "VMess write zero",
                    )))
                }
                Poll::Ready(Ok(n)) => n,
            };
            self.tx_pending_pos += n;
        }
        self.tx_pending.clear();
        self.tx_pending_pos = 0;
        Poll::Ready(Ok(()))
    }
}

impl AsyncRead for VmessAeadStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        loop {
            if self.rx_plain_pos < self.rx_plain.len() {
                let avail = &self.rx_plain[self.rx_plain_pos..];
                let n = avail.len().min(buf.remaining());
                buf.put_slice(&avail[..n]);
                self.rx_plain_pos += n;
                if self.rx_plain_pos >= self.rx_plain.len() {
                    self.rx_plain.clear();
                    self.rx_plain_pos = 0;
                }
                return Poll::Ready(Ok(()));
            }
            if self.rx_eof {
                return Poll::Ready(Ok(()));
            }

            if !self.resp_hdr_done {
                if self.resp_hdr_len.is_none() && self.rx_raw.len() >= 18 {
                    let mut enc_len: Vec<u8> = self.rx_raw.drain(..18).collect();
                    let lk = vmess_kdf(&self.resp_key, &[b"AEAD Resp Header Len Key"]);
                    let liv = vmess_kdf(&self.resp_iv, &[b"AEAD Resp Header Len IV"]);
                    let dec = open_aes128_gcm(&lk[..16], &liv[..12], b"", &mut enc_len)?;
                    self.resp_hdr_len = Some(u16::from_be_bytes([dec[0], dec[1]]) as usize);
                }
                if let Some(hlen) = self.resp_hdr_len {
                    if self.rx_raw.len() >= hlen + 16 {
                        let mut enc_hdr: Vec<u8> = self.rx_raw.drain(..hlen + 16).collect();
                        let pk = vmess_kdf(&self.resp_key, &[b"AEAD Resp Header Payload Key"]);
                        let piv = vmess_kdf(&self.resp_iv, &[b"AEAD Resp Header Payload IV"]);
                        let dec = open_aes128_gcm(&pk[..16], &piv[..12], b"", &mut enc_hdr)?;
                        if dec.is_empty() || dec[0] != self.resp_v {
                            return Poll::Ready(Err(io::Error::new(
                                io::ErrorKind::InvalidData,
                                "VMess response auth mismatch",
                            )));
                        }
                        self.resp_hdr_done = true;
                    }
                }
            }

            if self.resp_hdr_done && self.rx_raw.len() >= 2 {
                let frame_len = u16::from_be_bytes([self.rx_raw[0], self.rx_raw[1]]) as usize;
                if self.rx_raw.len() >= 2 + frame_len {
                    self.rx_raw.drain(..2);
                    let mut chunk: Vec<u8> = self.rx_raw.drain(..frame_len).collect();
                    if self.rx_key.is_some() {
                        if frame_len < 16 {
                            return Poll::Ready(Err(io::Error::new(
                                io::ErrorKind::InvalidData,
                                "VMess chunk shorter than tag",
                            )));
                        }
                        let iv = self.rx_iv;
                        let nonce_bytes = vmess_chunk_nonce(&mut self.rx_count, &iv);
                        let key_clone_res = {
                            let key_ref = self.rx_key.as_ref().unwrap();
                            key_ref
                                .open_in_place(
                                    Nonce::assume_unique_for_key(nonce_bytes),
                                    Aad::empty(),
                                    &mut chunk,
                                )
                                .map(|s| s.to_vec())
                        };
                        let plain = key_clone_res.map_err(|_| {
                            io::Error::new(io::ErrorKind::InvalidData, "VMess body tag mismatch")
                        })?;
                        if plain.is_empty() {
                            self.rx_eof = true;
                            return Poll::Ready(Ok(()));
                        }
                        self.rx_plain = plain;
                        self.rx_plain_pos = 0;
                        continue;
                    } else {
                        if chunk.is_empty() {
                            self.rx_eof = true;
                            return Poll::Ready(Ok(()));
                        }
                        self.rx_plain = chunk;
                        self.rx_plain_pos = 0;
                        continue;
                    }
                }
            }

            let mut tmp = [0u8; 8192];
            let mut rb = ReadBuf::new(&mut tmp);
            match self.inner.as_mut().poll_read(cx, &mut rb) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Ready(Ok(())) => {
                    let filled = rb.filled();
                    if filled.is_empty() {
                        return Poll::Ready(Ok(()));
                    }
                    self.rx_raw.extend_from_slice(filled);
                }
            }
        }
    }
}

impl AsyncWrite for VmessAeadStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        if buf.is_empty() {
            return Poll::Ready(Ok(0));
        }
        if !self.tx_pending.is_empty() {
            match self.poll_drain_tx(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Ready(Ok(())) => {
                    if self.tx_plain_len > 0 {
                        let ack = self.tx_plain_len;
                        self.tx_plain_len = 0;
                        return Poll::Ready(Ok(ack));
                    }
                }
            }
        }

        let max_plain = if self.cipher == VmessBodyCipher::None {
            0x3FFF
        } else {
            0x3FFF - 16
        };
        let slice = &buf[..buf.len().min(max_plain)];
        let mut frame = Vec::with_capacity(2 + slice.len() + 16);
        if self.tx_key.is_some() {
            let iv = self.tx_iv;
            let nonce_bytes = vmess_chunk_nonce(&mut self.tx_count, &iv);
            let mut body = slice.to_vec();
            self.tx_key
                .as_ref()
                .unwrap()
                .seal_in_place_append_tag(
                    Nonce::assume_unique_for_key(nonce_bytes),
                    Aad::empty(),
                    &mut body,
                )
                .map_err(|_| io::Error::other("VMess body seal failed"))?;
            frame.extend_from_slice(&(body.len() as u16).to_be_bytes());
            frame.extend_from_slice(&body);
        } else {
            frame.extend_from_slice(&(slice.len() as u16).to_be_bytes());
            frame.extend_from_slice(slice);
        }

        self.tx_pending = frame;
        self.tx_pending_pos = 0;
        self.tx_plain_len = slice.len();

        match self.poll_drain_tx(cx) {
            Poll::Pending => Poll::Pending,
            Poll::Ready(Err(e)) => Poll::Ready(Err(e)),
            Poll::Ready(Ok(())) => {
                let ack = self.tx_plain_len;
                self.tx_plain_len = 0;
                Poll::Ready(Ok(ack))
            }
        }
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        match self.poll_drain_tx(cx) {
            Poll::Pending => return Poll::Pending,
            Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
            Poll::Ready(Ok(())) => {}
        }
        self.inner.as_mut().poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let _ = self.poll_drain_tx(cx);
        self.inner.as_mut().poll_shutdown(cx)
    }
}

// --- 5. SOCKS5 & HTTP Outbound ---

async fn connect_socks5_outbound(
    mut stream: BoxStream,
    outbound: &Value,
    target: &TargetAddr,
) -> io::Result<BoxStream> {
    let user = outbound
        .get("username")
        .and_then(Value::as_str)
        .unwrap_or("");
    let pass = outbound
        .get("password")
        .and_then(Value::as_str)
        .unwrap_or("");
    if user.is_empty() {
        stream.write_all(&[0x05, 0x01, 0x00]).await?;
    } else {
        stream.write_all(&[0x05, 0x02, 0x00, 0x02]).await?;
    }
    let mut choice = [0u8; 2];
    stream.read_exact(&mut choice).await?;
    if choice[1] == 0x02 {
        let mut auth = Vec::with_capacity(3 + user.len() + pass.len());
        auth.push(0x01);
        auth.push(user.len() as u8);
        auth.extend_from_slice(user.as_bytes());
        auth.push(pass.len() as u8);
        auth.extend_from_slice(pass.as_bytes());
        stream.write_all(&auth).await?;
        let mut ares = [0u8; 2];
        stream.read_exact(&mut ares).await?;
        if ares[1] != 0x00 {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "SOCKS5 auth rejected",
            ));
        }
    } else if choice[1] != 0x00 {
        return Err(io::Error::other("SOCKS5 method rejected"));
    }

    let mut req = vec![0x05, 0x01, 0x00];
    target.encode_socks5(&mut req);
    stream.write_all(&req).await?;
    let mut rep = [0u8; 4];
    stream.read_exact(&mut rep).await?;
    if rep[1] != 0x00 {
        return Err(io::Error::other(format!("SOCKS5 connect error {}", rep[1])));
    }
    match rep[3] {
        0x01 => {
            let mut skip = [0u8; 6];
            stream.read_exact(&mut skip).await?;
        }
        0x03 => {
            let mut l = [0u8; 1];
            stream.read_exact(&mut l).await?;
            let mut skip = vec![0u8; l[0] as usize + 2];
            stream.read_exact(&mut skip).await?;
        }
        0x04 => {
            let mut skip = [0u8; 18];
            stream.read_exact(&mut skip).await?;
        }
        _ => {}
    }
    Ok(stream)
}

async fn connect_http_outbound(
    mut stream: BoxStream,
    outbound: &Value,
    target: &TargetAddr,
) -> io::Result<BoxStream> {
    let hp = target.host_port_string();
    let user = outbound
        .get("username")
        .and_then(Value::as_str)
        .unwrap_or("");
    let pass = outbound
        .get("password")
        .and_then(Value::as_str)
        .unwrap_or("");
    let auth_line = if !user.is_empty() {
        use base64::Engine;
        let b64 = base64::engine::general_purpose::STANDARD.encode(format!("{user}:{pass}"));
        format!("Proxy-Authorization: Basic {b64}\r\n")
    } else {
        String::new()
    };
    let req = format!("CONNECT {hp} HTTP/1.1\r\nHost: {hp}\r\n{auth_line}\r\n");
    stream.write_all(req.as_bytes()).await?;
    let mut resp = Vec::new();
    let mut b = [0u8; 256];
    let end = loop {
        if let Some(pos) = find_double_crlf(&resp) {
            break pos;
        }
        let n = stream.read(&mut b).await?;
        if n == 0 || resp.len() > 8192 {
            return Err(io::Error::other("HTTP proxy CONNECT failed"));
        }
        resp.extend_from_slice(&b[..n]);
    };
    let line = String::from_utf8_lossy(&resp[..end]);
    if !line.contains(" 200 ") {
        return Err(io::Error::other("HTTP proxy non-200 status"));
    }
    Ok(Box::pin(PrefixedStream {
        inner: stream,
        read_prefix: resp[end..].to_vec(),
        prefix_pos: 0,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn capability_detection_matches_mobile_and_desktop_protocols() {
        let vless_ws = json!({
            "type": "vless",
            "server": "hk.example.com",
            "server_port": 443,
            "uuid": "11111111-2222-3333-4444-555555555555",
            "tls": { "enabled": true, "server_name": "hk.example.com" },
            "transport": { "type": "ws", "path": "/ws?ed=2048" }
        });
        assert!(can_handle_outbound(&vless_ws));
        assert_eq!(sanitize_ws_path("/ws?ed=2048"), "/ws");
        assert_eq!(sanitize_ws_path("/ws?token=abc&ed=2048"), "/ws?token=abc");

        let vless_reality = json!({
            "type": "vless",
            "server": "us.example.com",
            "server_port": 443,
            "uuid": "11111111-2222-3333-4444-555555555555",
            "flow": "xtls-rprx-vision",
            "tls": { "enabled": true, "reality": { "enabled": true, "public_key": "abc" } }
        });
        assert!(!can_handle_outbound(&vless_reality));

        let ss = json!({
            "type": "shadowsocks",
            "server": "jp.example.com",
            "server_port": 8388,
            "method": "chacha20-ietf-poly1305",
            "password": "secret"
        });
        assert!(can_handle_outbound(&ss));

        let vmess = json!({
            "type": "vmess",
            "server": "sg.example.com",
            "server_port": 443,
            "uuid": "11111111-2222-3333-4444-555555555555",
            "security": "auto"
        });
        assert!(can_handle_outbound(&vmess));
    }

    #[tokio::test]
    async fn in_process_vless_trojan_and_shadowsocks_roundtrip_via_socks5() {
        // 1. Mock VLESS v0 server on loopback
        let vless_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let vless_port = vless_listener.local_addr().unwrap().port();
        let uuid_str = "11111111-2222-3333-4444-555555555555";
        let expected_uuid = *uuid::Uuid::parse_str(uuid_str).unwrap().as_bytes();

        tokio::spawn(async move {
            let (mut s, _) = vless_listener.accept().await.unwrap();
            let mut hdr = [0u8; 1 + 16 + 1 + 1 + 2 + 1 + 1];
            s.read_exact(&mut hdr).await.unwrap();
            assert_eq!(hdr[0], 0);
            assert_eq!(&hdr[1..17], &expected_uuid);
            assert_eq!(hdr[18], 0x01); // TCP
            let port = u16::from_be_bytes([hdr[19], hdr[20]]);
            assert_eq!(port, 8080);
            assert_eq!(hdr[21], 0x02); // VLESS Domain type!
            let dlen = hdr[22] as usize;
            let mut dom = vec![0u8; dlen];
            s.read_exact(&mut dom).await.unwrap();
            assert_eq!(&dom, b"emby.example.com");

            let mut req = [0u8; 4];
            s.read_exact(&mut req).await.unwrap();
            assert_eq!(&req, b"PING");
            // VLESS v0 response header [0x00, 0x00] + payload
            s.write_all(b"\x00\x00PONG-VLESS").await.unwrap();
        });

        let vless_proxy = start_local_proxy(json!({
            "type": "vless",
            "server": "127.0.0.1",
            "server_port": vless_port,
            "uuid": uuid_str,
        }))
        .await
        .unwrap();

        let mut cli = TcpStream::connect(("127.0.0.1", vless_proxy.listen_port))
            .await
            .unwrap();
        cli.write_all(&[0x05, 0x01, 0x00]).await.unwrap();
        let mut m = [0u8; 2];
        cli.read_exact(&mut m).await.unwrap();
        assert_eq!(m, [0x05, 0x00]);
        let mut sreq = vec![0x05, 0x01, 0x00, 0x03, 16];
        sreq.extend_from_slice(b"emby.example.com");
        sreq.extend_from_slice(&8080u16.to_be_bytes());
        cli.write_all(&sreq).await.unwrap();
        let mut srep = [0u8; 10];
        cli.read_exact(&mut srep).await.unwrap();
        assert_eq!(srep[1], 0x00);
        cli.write_all(b"PING").await.unwrap();
        let mut pong = [0u8; 10];
        cli.read_exact(&mut pong).await.unwrap();
        assert_eq!(&pong, b"PONG-VLESS");
        drop(vless_proxy);

        // 2. Mock Shadowsocks AES-256-GCM server on loopback
        let ss_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let ss_port = ss_listener.local_addr().unwrap().port();
        let ss_pw = "vedro-secret-256";
        tokio::spawn(async move {
            let (mut s, _) = ss_listener.accept().await.unwrap();
            let mk = ss_evp_bytes_to_key(ss_pw.as_bytes(), 32);
            let mut rx_salt = [0u8; 32];
            s.read_exact(&mut rx_salt).await.unwrap();
            let rx_key = ss_derive_subkey(&aead::AES_256_GCM, &mk, &rx_salt).unwrap();
            let mut rx_nonce = 0u64;

            // Frame 1: target address
            let mut l1 = [0u8; 18];
            s.read_exact(&mut l1).await.unwrap();
            let d1 = rx_key
                .open_in_place(
                    Nonce::assume_unique_for_key(ss_nonce_bytes(&mut rx_nonce)),
                    Aad::empty(),
                    &mut l1,
                )
                .unwrap();
            let plen1 = u16::from_be_bytes([d1[0], d1[1]]) as usize;
            let mut p1 = vec![0u8; plen1 + 16];
            s.read_exact(&mut p1).await.unwrap();
            let addr_dec = rx_key
                .open_in_place(
                    Nonce::assume_unique_for_key(ss_nonce_bytes(&mut rx_nonce)),
                    Aad::empty(),
                    &mut p1,
                )
                .unwrap();
            assert_eq!(addr_dec[0], 0x03); // SOCKS5 domain

            // Frame 2: "HELLO"
            let mut l2 = [0u8; 18];
            s.read_exact(&mut l2).await.unwrap();
            let d2 = rx_key
                .open_in_place(
                    Nonce::assume_unique_for_key(ss_nonce_bytes(&mut rx_nonce)),
                    Aad::empty(),
                    &mut l2,
                )
                .unwrap();
            let plen2 = u16::from_be_bytes([d2[0], d2[1]]) as usize;
            let mut p2 = vec![0u8; plen2 + 16];
            s.read_exact(&mut p2).await.unwrap();
            let msg_dec = rx_key
                .open_in_place(
                    Nonce::assume_unique_for_key(ss_nonce_bytes(&mut rx_nonce)),
                    Aad::empty(),
                    &mut p2,
                )
                .unwrap();
            assert_eq!(msg_dec, b"HELLO");

            // Reply encrypted SS AEAD frame: "WORLD-SS"
            let tx_salt = [7u8; 32];
            let tx_key = ss_derive_subkey(&aead::AES_256_GCM, &mk, &tx_salt).unwrap();
            let mut tx_nonce = 0u64;
            let mut reply = tx_salt.to_vec();
            ss_seal_chunk(&tx_key, &mut tx_nonce, b"WORLD-SS", &mut reply).unwrap();
            s.write_all(&reply).await.unwrap();
        });

        let ss_proxy = start_local_proxy(json!({
            "type": "shadowsocks",
            "server": "127.0.0.1",
            "server_port": ss_port,
            "method": "aes-256-gcm",
            "password": ss_pw,
        }))
        .await
        .unwrap();

        // Connect via HTTP CONNECT to verify HTTP proxy inbound on the same mixed port!
        let mut hcli = TcpStream::connect(("127.0.0.1", ss_proxy.listen_port))
            .await
            .unwrap();
        hcli.write_all(
            b"CONNECT media.example.com:443 HTTP/1.1\r\nHost: media.example.com:443\r\n\r\n",
        )
        .await
        .unwrap();
        let mut hresp = [0u8; 39];
        hcli.read_exact(&mut hresp).await.unwrap();
        assert!(String::from_utf8_lossy(&hresp).starts_with("HTTP/1.1 200"));
        hcli.write_all(b"HELLO").await.unwrap();
        let mut ss_out = [0u8; 8];
        hcli.read_exact(&mut ss_out).await.unwrap();
        assert_eq!(&ss_out, b"WORLD-SS");
        drop(ss_proxy);
    }
}
