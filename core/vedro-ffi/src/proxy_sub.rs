use std::collections::HashMap;
use std::time::Duration;

use base64::Engine;
use percent_encoding::percent_decode_str;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use url::Url;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyNodeInfo {
    pub id: String,
    pub name: String,
    pub protocol: String,
    pub server: String,
    pub port: u16,
    #[serde(default)]
    pub direct_proxy_url: Option<String>,
    #[serde(default)]
    pub singbox_outbound: Option<Value>,
}

pub fn parse_subscription_userinfo(raw: &str) -> Option<Value> {
    let mut upload: Option<u64> = None;
    let mut download: Option<u64> = None;
    let mut total: Option<u64> = None;
    let mut expire: Option<u64> = None;
    for part in raw.split(';') {
        let Some((k, v)) = part.trim().split_once('=') else {
            continue;
        };
        let num = v.trim().parse::<u64>().ok();
        match k.trim().to_ascii_lowercase().as_str() {
            "upload" => upload = num,
            "download" => download = num,
            "total" => total = num,
            "expire" => expire = num,
            _ => {}
        }
    }
    if upload.is_none() && download.is_none() && total.is_none() && expire.is_none() {
        return None;
    }
    let used = upload.unwrap_or(0).saturating_add(download.unwrap_or(0));
    Some(json!({
        "upload": upload.unwrap_or(0),
        "download": download.unwrap_or(0),
        "used": used,
        "total": total,
        "expire": expire,
    }))
}

fn stable_node_id(protocol: &str, server: &str, port: u16, name: &str, idx: usize) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in format!("{protocol}:{server}:{port}:{name}:{idx}").bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("node_{h:012x}")
}

fn decode_b64_flexible(input: &str) -> Option<Vec<u8>> {
    let trimmed: String = input.chars().filter(|c| !c.is_whitespace()).collect();
    if trimmed.is_empty() {
        return None;
    }
    let normalized = trimmed.replace('-', "+").replace('_', "/");
    let padded = match normalized.len() % 4 {
        0 => normalized,
        2 => format!("{normalized}=="),
        3 => format!("{normalized}="),
        _ => return None,
    };
    base64::engine::general_purpose::STANDARD
        .decode(padded.as_bytes())
        .ok()
}

fn url_decode(s: &str) -> String {
    percent_decode_str(s).decode_utf8_lossy().into_owned()
}

/// Parse subscription body supporting:
/// 1) Sing-box JSON (`{"outbounds": [...]}`)
/// 2) Clash / Mihomo YAML (`proxies:` flow `{...}` or block `- name: ...`)
/// 3) Base64-encoded or plain URI lines (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`/`hy2://`, `tuic://`, `socks5://`, `http://`)
pub fn parse_subscription_content(raw: &str) -> Result<Vec<ProxyNodeInfo>, String> {
    let text = raw.trim().trim_start_matches('\u{feff}');
    if text.is_empty() {
        return Err("订阅内容为空".into());
    }

    // 1. Sing-box JSON
    if text.starts_with('{') {
        if let Ok(doc) = serde_json::from_str::<Value>(text) {
            let nodes = parse_singbox_json(&doc);
            if !nodes.is_empty() {
                return Ok(nodes);
            }
        }
    }

    // 2. Clash / Mihomo YAML
    if text.contains("proxies:") {
        let nodes = parse_clash_yaml(text);
        if !nodes.is_empty() {
            return Ok(nodes);
        }
    }

    // 3. Plain URI lines or Base64-encoded URI lines
    let decoded_cow: String;
    let uri_source = if text.contains("://") {
        text
    } else if let Some(bytes) = decode_b64_flexible(text) {
        decoded_cow = String::from_utf8_lossy(&bytes).into_owned();
        decoded_cow.as_str()
    } else {
        text
    };

    if uri_source.contains("proxies:") {
        let nodes = parse_clash_yaml(uri_source);
        if !nodes.is_empty() {
            return Ok(nodes);
        }
    }

    let mut out = Vec::new();
    for line in uri_source.lines() {
        let l = line.trim();
        if l.is_empty() || l.starts_with('#') || l.starts_with("//") {
            continue;
        }
        if let Some(node) = parse_proxy_uri(l, out.len()) {
            out.push(node);
        }
    }

    if out.is_empty() {
        Err("未识别到可用代理节点（支持 Clash/Mihomo、Sing-box 与 VLESS/VMess/Trojan/SS/Hysteria2/SOCKS5 订阅）".into())
    } else {
        Ok(out)
    }
}

fn parse_singbox_json(doc: &Value) -> Vec<ProxyNodeInfo> {
    let Some(arr) = doc.get("outbounds").and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for ob in arr {
        let proto = ob
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_ascii_lowercase();
        if matches!(
            proto.as_str(),
            "" | "direct" | "block" | "dns" | "selector" | "urltest"
        ) {
            continue;
        }
        let server = ob
            .get("server")
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_string();
        let port = ob.get("server_port").and_then(Value::as_u64).unwrap_or(0) as u16;
        if server.is_empty() || port == 0 {
            continue;
        }
        let name = ob
            .get("tag")
            .and_then(Value::as_str)
            .filter(|s| !s.trim().is_empty())
            .map(ToString::to_string)
            .unwrap_or_else(|| format!("{server}:{port}"));
        let direct_proxy_url = if proto == "socks" || proto == "http" {
            let scheme = if proto == "socks" { "socks5h" } else { "http" };
            let user = ob.get("username").and_then(Value::as_str).unwrap_or("");
            let pass = ob.get("password").and_then(Value::as_str).unwrap_or("");
            if !user.is_empty() {
                Some(format!("{scheme}://{user}:{pass}@{server}:{port}"))
            } else {
                Some(format!("{scheme}://{server}:{port}"))
            }
        } else {
            None
        };
        let mut cloned = ob.clone();
        cloned["tag"] = Value::String("proxy".into());
        let id = stable_node_id(&proto, &server, port, &name, out.len());
        out.push(ProxyNodeInfo {
            id,
            name,
            protocol: proto,
            server,
            port,
            direct_proxy_url,
            singbox_outbound: Some(cloned),
        });
    }
    out
}

fn unquote_yaml(raw: &str) -> String {
    let s = raw.trim();
    if (s.starts_with('"') && s.ends_with('"') && s.len() >= 2)
        || (s.starts_with('\'') && s.ends_with('\'') && s.len() >= 2)
    {
        s[1..s.len() - 1].to_string()
    } else {
        s.to_string()
    }
}

fn parse_flow_map(inner: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let mut depth = 0i32;
    let mut in_quote: Option<char> = None;
    let mut token = String::new();
    let mut parts = Vec::new();
    for ch in inner.chars() {
        if let Some(q) = in_quote {
            if ch == q {
                in_quote = None;
            }
            token.push(ch);
            continue;
        }
        match ch {
            '"' | '\'' => {
                in_quote = Some(ch);
                token.push(ch);
            }
            '{' | '[' => {
                depth += 1;
                token.push(ch);
            }
            '}' | ']' => {
                depth -= 1;
                token.push(ch);
            }
            ',' if depth == 0 => {
                parts.push(std::mem::take(&mut token));
            }
            _ => token.push(ch),
        }
    }
    if !token.trim().is_empty() {
        parts.push(token);
    }
    for part in parts {
        if let Some((k, v)) = part.split_once(':') {
            let key = unquote_yaml(k);
            let val = v.trim();
            if val.starts_with('{') && val.ends_with('}') && val.len() >= 2 {
                for (nk, nv) in parse_flow_map(&val[1..val.len() - 1]) {
                    map.insert(format!("{key}.{nk}"), nv);
                }
            } else {
                map.insert(key, unquote_yaml(val));
            }
        }
    }
    map
}

fn parse_clash_yaml(text: &str) -> Vec<ProxyNodeInfo> {
    let mut in_proxies = false;
    let mut raw_items: Vec<HashMap<String, String>> = Vec::new();
    let mut current_block: Option<HashMap<String, String>> = None;
    let mut current_subkey: Option<(usize, String)> = None;

    for raw_line in text.lines() {
        let line_no_comment = match raw_line.find(" #") {
            Some(idx) => &raw_line[..idx],
            None => raw_line,
        };
        let trimmed = line_no_comment.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let indent = line_no_comment.len() - line_no_comment.trim_start().len();
        if indent == 0 {
            if let Some(prev) = current_block.take() {
                raw_items.push(prev);
            }
            in_proxies = trimmed == "proxies:" || trimmed.starts_with("proxies:");
            continue;
        }
        if !in_proxies {
            continue;
        }

        if let Some(after_dash) = trimmed.strip_prefix('-') {
            if let Some(prev) = current_block.take() {
                raw_items.push(prev);
            }
            current_subkey = None;
            let item_str = after_dash.trim();
            if item_str.starts_with('{') && item_str.ends_with('}') && item_str.len() >= 2 {
                raw_items.push(parse_flow_map(&item_str[1..item_str.len() - 1]));
            } else if let Some((k, v)) = item_str.split_once(':') {
                let mut m = HashMap::new();
                m.insert(unquote_yaml(k), unquote_yaml(v));
                current_block = Some(m);
            } else {
                current_block = Some(HashMap::new());
            }
            continue;
        }

        if let Some(ref mut blk) = current_block {
            if let Some((sub_indent, ref prefix)) = current_subkey {
                if indent <= sub_indent {
                    current_subkey = None;
                } else if let Some((k, v)) = trimmed.split_once(':') {
                    let v_trim = v.trim();
                    if v_trim.starts_with('{') && v_trim.ends_with('}') && v_trim.len() >= 2 {
                        for (nk, nv) in parse_flow_map(&v_trim[1..v_trim.len() - 1]) {
                            blk.insert(format!("{prefix}.{}.{nk}", unquote_yaml(k)), nv);
                        }
                    } else if !v_trim.is_empty() {
                        blk.insert(
                            format!("{prefix}.{}", unquote_yaml(k)),
                            unquote_yaml(v_trim),
                        );
                    }
                    continue;
                }
            }
            if let Some((k, v)) = trimmed.split_once(':') {
                let key = unquote_yaml(k);
                let v_trim = v.trim();
                if v_trim.is_empty() {
                    current_subkey = Some((indent, key));
                } else if v_trim.starts_with('{') && v_trim.ends_with('}') && v_trim.len() >= 2 {
                    for (nk, nv) in parse_flow_map(&v_trim[1..v_trim.len() - 1]) {
                        blk.insert(format!("{key}.{nk}"), nv);
                    }
                } else {
                    blk.insert(key, unquote_yaml(v_trim));
                }
            }
        }
    }
    if let Some(prev) = current_block.take() {
        raw_items.push(prev);
    }

    let mut out = Vec::new();
    for map in raw_items {
        if let Some(node) = clash_map_to_node(&map, out.len()) {
            out.push(node);
        }
    }
    out
}

fn build_tls_json(
    enabled: bool,
    sni: Option<&str>,
    insecure: bool,
    alpn: Option<&str>,
    reality_pbk: Option<&str>,
    reality_sid: Option<&str>,
    utls_fp: Option<&str>,
) -> Option<Value> {
    if !enabled && reality_pbk.filter(|s| !s.is_empty()).is_none() {
        return None;
    }
    let mut tls = json!({
        "enabled": true,
        "insecure": insecure,
    });
    if let Some(s) = sni.filter(|s| !s.is_empty()) {
        tls["server_name"] = Value::String(s.to_string());
    }
    if let Some(a) = alpn.filter(|s| !s.is_empty()) {
        let list: Vec<Value> = a
            .split(',')
            .map(|x| x.trim().trim_matches(['[', ']', '"', '\'']))
            .filter(|x| !x.is_empty())
            .map(|x| Value::String(x.to_string()))
            .collect();
        if !list.is_empty() {
            tls["alpn"] = Value::Array(list);
        }
    }
    if let Some(fp) = utls_fp.filter(|s| !s.is_empty()) {
        tls["utls"] = json!({ "enabled": true, "fingerprint": fp });
    }
    if let Some(pbk) = reality_pbk.filter(|s| !s.is_empty()) {
        tls["reality"] = json!({
            "enabled": true,
            "public_key": pbk,
            "short_id": reality_sid.unwrap_or(""),
        });
        if tls.get("utls").is_none() {
            tls["utls"] = json!({ "enabled": true, "fingerprint": "chrome" });
        }
    }
    Some(tls)
}

fn build_transport_json(
    net: &str,
    path: Option<&str>,
    host: Option<&str>,
    service_name: Option<&str>,
) -> Option<Value> {
    match net.to_ascii_lowercase().as_str() {
        "ws" | "websocket" => {
            let mut tr = json!({
                "type": "ws",
                "path": path.filter(|s| !s.is_empty()).unwrap_or("/"),
            });
            if let Some(h) = host.filter(|s| !s.is_empty()) {
                tr["headers"] = json!({ "Host": h });
            }
            Some(tr)
        }
        "grpc" => Some(json!({
            "type": "grpc",
            "service_name": service_name.or(path).unwrap_or(""),
        })),
        "http" | "h2" => {
            let mut tr = json!({
                "type": "http",
                "path": path.filter(|s| !s.is_empty()).unwrap_or("/"),
            });
            if let Some(h) = host.filter(|s| !s.is_empty()) {
                tr["host"] = json!([h]);
            }
            Some(tr)
        }
        "httpupgrade" => {
            let mut tr = json!({
                "type": "httpupgrade",
                "path": path.filter(|s| !s.is_empty()).unwrap_or("/"),
            });
            if let Some(h) = host.filter(|s| !s.is_empty()) {
                tr["host"] = Value::String(h.to_string());
            }
            Some(tr)
        }
        _ => None,
    }
}

fn clash_map_to_node(m: &HashMap<String, String>, idx: usize) -> Option<ProxyNodeInfo> {
    let proto_raw = m.get("type")?.trim().to_ascii_lowercase();
    let server = m.get("server")?.trim().to_string();
    let port = m.get("port")?.trim().parse::<u16>().ok()?;
    if server.is_empty() || port == 0 {
        return None;
    }
    let name = m
        .get("name")
        .cloned()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| format!("{server}:{port}"));
    let insecure = matches!(
        m.get("skip-cert-verify").map(String::as_str),
        Some("true" | "1" | "yes")
    );
    let tls_flag = matches!(m.get("tls").map(String::as_str), Some("true" | "1" | "yes"));
    let sni = m
        .get("servername")
        .or_else(|| m.get("sni"))
        .map(String::as_str);
    let net = m.get("network").map(String::as_str).unwrap_or("tcp");
    let ws_path = m
        .get("ws-opts.path")
        .or_else(|| m.get("ws-path"))
        .map(String::as_str);
    let ws_host = m
        .get("ws-opts.headers.Host")
        .or_else(|| m.get("ws-opts.headers.host"))
        .map(String::as_str);
    let grpc_svc = m.get("grpc-opts.grpc-service-name").map(String::as_str);
    let reality_pbk = m.get("reality-opts.public-key").map(String::as_str);
    let reality_sid = m.get("reality-opts.short-id").map(String::as_str);
    let fp = m.get("client-fingerprint").map(String::as_str);
    let alpn = m.get("alpn").map(String::as_str);

    let mut direct_proxy_url = None;
    let outbound = match proto_raw.as_str() {
        "ss" | "shadowsocks" => json!({
            "type": "shadowsocks",
            "tag": "proxy",
            "server": server,
            "server_port": port,
            "method": m.get("cipher").map(String::as_str).unwrap_or("aes-256-gcm"),
            "password": m.get("password").map(String::as_str).unwrap_or(""),
        }),
        "vmess" => {
            let mut ob = json!({
                "type": "vmess",
                "tag": "proxy",
                "server": server,
                "server_port": port,
                "uuid": m.get("uuid")?,
                "alter_id": m.get("alterId").and_then(|x| x.parse::<u32>().ok()).unwrap_or(0),
                "security": m.get("cipher").map(String::as_str).unwrap_or("auto"),
            });
            if let Some(t) =
                build_tls_json(tls_flag, sni.or(ws_host), insecure, alpn, None, None, fp)
            {
                ob["tls"] = t;
            }
            if let Some(tr) = build_transport_json(net, ws_path, ws_host, grpc_svc) {
                ob["transport"] = tr;
            }
            ob
        }
        "vless" => {
            let mut ob = json!({
                "type": "vless",
                "tag": "proxy",
                "server": server,
                "server_port": port,
                "uuid": m.get("uuid")?,
            });
            if let Some(flow) = m.get("flow").filter(|s| !s.is_empty()) {
                ob["flow"] = Value::String(flow.clone());
            }
            if let Some(t) = build_tls_json(
                tls_flag || reality_pbk.is_some(),
                sni.or(ws_host),
                insecure,
                alpn,
                reality_pbk,
                reality_sid,
                fp,
            ) {
                ob["tls"] = t;
            }
            if let Some(tr) = build_transport_json(net, ws_path, ws_host, grpc_svc) {
                ob["transport"] = tr;
            }
            ob
        }
        "trojan" => {
            let mut ob = json!({
                "type": "trojan",
                "tag": "proxy",
                "server": server,
                "server_port": port,
                "password": m.get("password")?,
            });
            if let Some(t) = build_tls_json(
                true,
                sni.or(ws_host).or(Some(server.as_str())),
                insecure,
                alpn,
                reality_pbk,
                reality_sid,
                fp,
            ) {
                ob["tls"] = t;
            }
            if let Some(tr) = build_transport_json(net, ws_path, ws_host, grpc_svc) {
                ob["transport"] = tr;
            }
            ob
        }
        "hysteria2" | "hy2" => {
            let mut ob = json!({
                "type": "hysteria2",
                "tag": "proxy",
                "server": server,
                "server_port": port,
                "password": m.get("password")?,
                "tls": {
                    "enabled": true,
                    "server_name": sni.unwrap_or(server.as_str()),
                    "insecure": insecure,
                }
            });
            if let Some(obfs) = m.get("obfs").filter(|s| !s.is_empty()) {
                ob["obfs"] = json!({
                    "type": obfs,
                    "password": m.get("obfs-password").cloned().unwrap_or_default(),
                });
            }
            ob
        }
        "tuic" => json!({
            "type": "tuic",
            "tag": "proxy",
            "server": server,
            "server_port": port,
            "uuid": m.get("uuid")?,
            "password": m.get("password").cloned().unwrap_or_default(),
            "congestion_control": m.get("congestion-controller").cloned().unwrap_or_else(|| "bbr".into()),
            "tls": {
                "enabled": true,
                "server_name": sni.unwrap_or(server.as_str()),
                "insecure": insecure,
            }
        }),
        "socks5" | "socks" | "http" => {
            let is_socks = proto_raw.starts_with("socks");
            let scheme = if is_socks { "socks5h" } else { "http" };
            let user = m.get("username").map(String::as_str).unwrap_or("");
            let pass = m.get("password").map(String::as_str).unwrap_or("");
            direct_proxy_url = Some(if !user.is_empty() {
                format!("{scheme}://{user}:{pass}@{server}:{port}")
            } else {
                format!("{scheme}://{server}:{port}")
            });
            json!({
                "type": if is_socks { "socks" } else { "http" },
                "tag": "proxy",
                "server": server,
                "server_port": port,
            })
        }
        _ => return None,
    };

    let proto_label = match proto_raw.as_str() {
        "shadowsocks" => "ss".to_string(),
        "hy2" => "hysteria2".to_string(),
        other => other.to_string(),
    };
    let id = stable_node_id(&proto_label, &server, port, &name, idx);
    Some(ProxyNodeInfo {
        id,
        name,
        protocol: proto_label,
        server,
        port,
        direct_proxy_url,
        singbox_outbound: Some(outbound),
    })
}

fn parse_proxy_uri(line: &str, idx: usize) -> Option<ProxyNodeInfo> {
    if let Some(rest) = line.strip_prefix("vmess://") {
        let bytes = decode_b64_flexible(rest)?;
        let v: Value = serde_json::from_slice(&bytes).ok()?;
        let server = v.get("add")?.as_str()?.trim().to_string();
        let port = match v.get("port")? {
            Value::Number(n) => n.as_u64()? as u16,
            Value::String(s) => s.trim().parse::<u16>().ok()?,
            _ => return None,
        };
        let uuid = v.get("id")?.as_str()?.trim().to_string();
        let name = v
            .get("ps")
            .and_then(Value::as_str)
            .filter(|s| !s.trim().is_empty())
            .map(ToString::to_string)
            .unwrap_or_else(|| format!("{server}:{port}"));
        let aid = v
            .get("aid")
            .and_then(|x| x.as_u64().or_else(|| x.as_str()?.parse().ok()))
            .unwrap_or(0);
        let net = v.get("net").and_then(Value::as_str).unwrap_or("tcp");
        let tls_on = v.get("tls").and_then(Value::as_str).unwrap_or("") == "tls";
        let host = v.get("host").and_then(Value::as_str);
        let path = v.get("path").and_then(Value::as_str);
        let sni = v.get("sni").and_then(Value::as_str).or(host);
        let fp = v.get("fp").and_then(Value::as_str);
        let mut ob = json!({
            "type": "vmess",
            "tag": "proxy",
            "server": server,
            "server_port": port,
            "uuid": uuid,
            "alter_id": aid,
            "security": v.get("scy").and_then(Value::as_str).filter(|s| !s.is_empty()).unwrap_or("auto"),
        });
        if let Some(t) = build_tls_json(tls_on, sni, false, None, None, None, fp) {
            ob["tls"] = t;
        }
        if let Some(tr) = build_transport_json(net, path, host, path) {
            ob["transport"] = tr;
        }
        let id = stable_node_id("vmess", &server, port, &name, idx);
        return Some(ProxyNodeInfo {
            id,
            name,
            protocol: "vmess".into(),
            server,
            port,
            direct_proxy_url: None,
            singbox_outbound: Some(ob),
        });
    }

    if let Some(rest) = line.strip_prefix("ss://") {
        let (main_part, frag) = match rest.split_once('#') {
            Some((a, b)) => (a, Some(url_decode(b))),
            None => (rest, None),
        };
        let (cred_raw, host_port) = if let Some((u, hp)) = main_part.split_once('@') {
            let decoded_u = decode_b64_flexible(u)
                .map(|b| String::from_utf8_lossy(&b).into_owned())
                .unwrap_or_else(|| url_decode(u));
            (decoded_u, hp.split('?').next().unwrap_or(hp).to_string())
        } else {
            let clean = main_part.split('?').next().unwrap_or(main_part);
            let decoded = String::from_utf8(decode_b64_flexible(clean)?).ok()?;
            let (u, hp) = decoded.rsplit_once('@')?;
            (u.to_string(), hp.to_string())
        };
        let (method, password) = cred_raw.split_once(':')?;
        let parsed = Url::parse(&format!("http://{host_port}")).ok()?;
        let server = parsed.host_str()?.to_string();
        let port = parsed.port()?;
        let name = frag
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| format!("{server}:{port}"));
        let ob = json!({
            "type": "shadowsocks",
            "tag": "proxy",
            "server": server,
            "server_port": port,
            "method": method,
            "password": password,
        });
        let id = stable_node_id("ss", &server, port, &name, idx);
        return Some(ProxyNodeInfo {
            id,
            name,
            protocol: "ss".into(),
            server,
            port,
            direct_proxy_url: None,
            singbox_outbound: Some(ob),
        });
    }

    let url = Url::parse(line).ok()?;
    let scheme = url.scheme().to_ascii_lowercase();
    let server = url.host_str()?.to_string();
    let port = url.port_or_known_default()?;
    let name = url
        .fragment()
        .map(url_decode)
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| format!("{server}:{port}"));
    let qp: HashMap<String, String> = url
        .query_pairs()
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect();
    let sni = qp.get("sni").or_else(|| qp.get("peer")).map(String::as_str);
    let insecure = matches!(
        qp.get("allowInsecure")
            .or_else(|| qp.get("insecure"))
            .map(String::as_str),
        Some("1" | "true")
    );
    let net = qp.get("type").map(String::as_str).unwrap_or("tcp");
    let host = qp.get("host").map(String::as_str);
    let path = qp.get("path").map(String::as_str);
    let svc = qp.get("serviceName").map(String::as_str);
    let fp = qp.get("fp").map(String::as_str);
    let alpn = qp.get("alpn").map(String::as_str);
    let pbk = qp.get("pbk").map(String::as_str);
    let sid = qp.get("sid").map(String::as_str);

    match scheme.as_str() {
        "vless" => {
            let uuid = url_decode(url.username());
            let security = qp.get("security").map(String::as_str).unwrap_or("none");
            let tls_on = security == "tls" || security == "reality";
            let mut ob = json!({
                "type": "vless",
                "tag": "proxy",
                "server": server,
                "server_port": port,
                "uuid": uuid,
            });
            if let Some(flow) = qp.get("flow").filter(|s| !s.is_empty()) {
                ob["flow"] = Value::String(flow.clone());
            }
            if let Some(t) = build_tls_json(tls_on, sni.or(host), insecure, alpn, pbk, sid, fp) {
                ob["tls"] = t;
            }
            if let Some(tr) = build_transport_json(net, path, host, svc) {
                ob["transport"] = tr;
            }
            let id = stable_node_id("vless", &server, port, &name, idx);
            Some(ProxyNodeInfo {
                id,
                name,
                protocol: "vless".into(),
                server,
                port,
                direct_proxy_url: None,
                singbox_outbound: Some(ob),
            })
        }
        "trojan" => {
            let password = url_decode(url.username());
            let mut ob = json!({
                "type": "trojan",
                "tag": "proxy",
                "server": server,
                "server_port": port,
                "password": password,
            });
            if let Some(t) = build_tls_json(
                true,
                sni.or(host).or(Some(server.as_str())),
                insecure,
                alpn,
                pbk,
                sid,
                fp,
            ) {
                ob["tls"] = t;
            }
            if let Some(tr) = build_transport_json(net, path, host, svc) {
                ob["transport"] = tr;
            }
            let id = stable_node_id("trojan", &server, port, &name, idx);
            Some(ProxyNodeInfo {
                id,
                name,
                protocol: "trojan".into(),
                server,
                port,
                direct_proxy_url: None,
                singbox_outbound: Some(ob),
            })
        }
        "hysteria2" | "hy2" => {
            let password = url_decode(url.username());
            let mut ob = json!({
                "type": "hysteria2",
                "tag": "proxy",
                "server": server,
                "server_port": port,
                "password": password,
                "tls": {
                    "enabled": true,
                    "server_name": sni.unwrap_or(server.as_str()),
                    "insecure": insecure,
                }
            });
            if let Some(obfs) = qp.get("obfs").filter(|s| !s.is_empty() && *s != "none") {
                ob["obfs"] = json!({
                    "type": obfs,
                    "password": qp.get("obfs-password").cloned().unwrap_or_default(),
                });
            }
            let id = stable_node_id("hysteria2", &server, port, &name, idx);
            Some(ProxyNodeInfo {
                id,
                name,
                protocol: "hysteria2".into(),
                server,
                port,
                direct_proxy_url: None,
                singbox_outbound: Some(ob),
            })
        }
        "tuic" => {
            let uuid = url_decode(url.username());
            let password = url.password().map(url_decode).unwrap_or_default();
            let ob = json!({
                "type": "tuic",
                "tag": "proxy",
                "server": server,
                "server_port": port,
                "uuid": uuid,
                "password": password,
                "congestion_control": qp.get("congestion_control").cloned().unwrap_or_else(|| "bbr".into()),
                "tls": {
                    "enabled": true,
                    "server_name": sni.unwrap_or(server.as_str()),
                    "insecure": insecure,
                }
            });
            let id = stable_node_id("tuic", &server, port, &name, idx);
            Some(ProxyNodeInfo {
                id,
                name,
                protocol: "tuic".into(),
                server,
                port,
                direct_proxy_url: None,
                singbox_outbound: Some(ob),
            })
        }
        "socks5" | "socks5h" | "socks" | "http" | "https" => {
            let is_socks = scheme.starts_with("socks");
            let norm_scheme = if is_socks { "socks5h" } else { scheme.as_str() };
            let user = url.username();
            let pass = url.password().unwrap_or("");
            let direct = if !user.is_empty() {
                format!("{norm_scheme}://{user}:{pass}@{server}:{port}")
            } else {
                format!("{norm_scheme}://{server}:{port}")
            };
            let proto = if is_socks { "socks5" } else { "http" };
            let id = stable_node_id(proto, &server, port, &name, idx);
            Some(ProxyNodeInfo {
                id,
                name,
                protocol: proto.into(),
                server,
                port,
                direct_proxy_url: Some(direct),
                singbox_outbound: None,
            })
        }
        _ => None,
    }
}

pub async fn ping_nodes_tcp(nodes: Vec<(String, String, u16)>) -> serde_json::Map<String, Value> {
    let sem = std::sync::Arc::new(tokio::sync::Semaphore::new(24));
    let mut set = tokio::task::JoinSet::new();
    for (id, server, port) in nodes {
        let sem_clone = std::sync::Arc::clone(&sem);
        set.spawn(async move {
            let _permit = sem_clone.acquire_owned().await.ok();
            if server.is_empty() || port == 0 {
                return (id, Value::Null);
            }
            let started = std::time::Instant::now();
            let res = tokio::time::timeout(
                Duration::from_millis(2500),
                tokio::net::TcpStream::connect((server.as_str(), port)),
            )
            .await;
            match res {
                Ok(Ok(_)) => (
                    id,
                    Value::Number((started.elapsed().as_millis() as u64).into()),
                ),
                _ => (id, Value::Null),
            }
        });
    }
    let mut out = serde_json::Map::new();
    while let Some(joined) = set.join_next().await {
        if let Ok((id, val)) = joined {
            out.insert(id, val);
        }
    }
    out
}

/// Extract a single named binary (e.g. `sing-box` or `sing-box.exe`) from a `.tar.gz` byte slice
/// using `flate2::read::GzDecoder` + POSIX USTAR 512-byte header walk (zero extra crate needed!).
pub fn extract_binary_from_targz(
    gz_bytes: &[u8],
    target_names: &[&str],
) -> Result<Vec<u8>, String> {
    use std::io::Read;
    let mut tar_bytes = Vec::new();
    flate2::read::GzDecoder::new(gz_bytes)
        .read_to_end(&mut tar_bytes)
        .map_err(|e| format!("解压核心包失败: {e}"))?;

    let mut offset = 0usize;
    while offset + 512 <= tar_bytes.len() {
        let hdr = &tar_bytes[offset..offset + 512];
        if hdr.iter().all(|&b| b == 0) {
            break;
        }
        let name_end = hdr[..100].iter().position(|&b| b == 0).unwrap_or(100);
        let name = String::from_utf8_lossy(&hdr[..name_end]);
        let size_raw = String::from_utf8_lossy(&hdr[124..136]);
        let size_clean = size_raw.trim_matches(|c: char| c == '\0' || c.is_whitespace());
        let size = usize::from_str_radix(size_clean, 8).unwrap_or(0);
        let data_start = offset + 512;
        let data_end = data_start.saturating_add(size);
        if data_end > tar_bytes.len() {
            break;
        }
        let base_name = name.rsplit('/').next().unwrap_or(&name);
        let typeflag = hdr[156];
        if (typeflag == 0 || typeflag == b'0')
            && size > 1024
            && target_names
                .iter()
                .any(|t| base_name.eq_ignore_ascii_case(t))
        {
            return Ok(tar_bytes[data_start..data_end].to_vec());
        }
        let blocks = size.div_ceil(512);
        offset = data_start + blocks * 512;
    }
    Err("核心压缩包中未找到 sing-box 可执行文件".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_clash_yaml_and_uri_subscriptions() {
        let yaml = r#"
proxies:
  - { name: "🇭🇰 香港 IEPL 01", type: vless, server: hk1.example.com, port: 443, uuid: 11111111-2222-3333-4444-555555555555, tls: true, servername: hk1.example.com, network: ws, ws-opts: { path: /ws } }
  - name: "🇯🇵 东京 BGP 02"
    type: ss
    server: jp1.example.com
    port: 8388
    cipher: aes-256-gcm
    password: secret
  - { name: "🇸🇬 本地网关", type: socks5, server: 127.0.0.1, port: 7890 }
"#;
        let nodes = parse_subscription_content(yaml).expect("parse clash yaml");
        assert_eq!(nodes.len(), 3);
        assert_eq!(nodes[0].protocol, "vless");
        assert_eq!(nodes[0].name, "🇭🇰 香港 IEPL 01");
        assert_eq!(nodes[1].protocol, "ss");
        assert_eq!(
            nodes[2].direct_proxy_url.as_deref(),
            Some("socks5h://127.0.0.1:7890")
        );

        let uris = "vless://11111111-2222-3333-4444-555555555555@us.example.com:443?security=reality&pbk=pubkey123&sid=ab12&sni=www.apple.com#US-Reality\ntrojan://pass123@sg.example.com:443?sni=sg.example.com#SG-Trojan\nsocks5://127.0.0.1:1080#LocalSocks";
        let b64 = base64::engine::general_purpose::STANDARD.encode(uris.as_bytes());
        let parsed_uris = parse_subscription_content(&b64).expect("parse b64 uris");
        assert_eq!(parsed_uris.len(), 3);
        assert_eq!(parsed_uris[0].name, "US-Reality");
        assert_eq!(parsed_uris[1].protocol, "trojan");
        assert_eq!(
            parsed_uris[2].direct_proxy_url.as_deref(),
            Some("socks5h://127.0.0.1:1080")
        );
    }
}
