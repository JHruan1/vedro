use std::path::Path;

use parking_lot::Mutex;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, StorageError>;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ServerRoute {
    pub id: String,
    pub name: String,
    pub url: String,
    #[serde(default)]
    pub proxy_url: Option<String>,
    #[serde(default)]
    pub accept_invalid_certs: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerProfile {
    pub id: String,
    pub name: String,
    pub url: String,
    pub dialect: String,
    pub user_id: Option<String>,
    pub username: Option<String>,
    pub access_token: Option<String>,
    pub is_admin: bool,
    pub last_connected_at: i64,
    #[serde(default)]
    pub routes: Vec<ServerRoute>,
    #[serde(default)]
    pub active_route_id: Option<String>,
}

impl ServerProfile {
    /// Ensure every profile always exposes at least one route matching its active URL.
    pub fn normalize_routes(&mut self) {
        if self.routes.is_empty() && !self.url.trim().is_empty() {
            self.routes.push(ServerRoute {
                id: "default".to_string(),
                name: "默认线路".to_string(),
                url: self.url.clone(),
                proxy_url: None,
                accept_invalid_certs: false,
            });
        }
        if self.active_route_id.is_none() {
            self.active_route_id = self
                .routes
                .iter()
                .find(|r| r.url.trim_end_matches('/') == self.url.trim_end_matches('/'))
                .or_else(|| self.routes.first())
                .map(|r| r.id.clone());
        }
    }

    pub fn active_route(&self) -> Option<&ServerRoute> {
        if let Some(id) = &self.active_route_id {
            if let Some(found) = self.routes.iter().find(|r| &r.id == id) {
                return Some(found);
            }
        }
        self.routes.first()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackPreference {
    pub server_id: String,
    pub scope_id: String, // series_id or item_id
    pub audio_lang: Option<String>,
    pub subtitle_lang: Option<String>,
    pub subtitle_disabled: bool,
    pub playback_speed: f64,
    pub skip_intro_secs: i64,
}

/// High-speed local SQLite (WAL mode) persistence for Vedro:
/// - Multi-server profiles + per-server multi-route lines (embygo / Emby / Jellyfin)
/// - App & Dolby Vision / Atmos settings KV
/// - Per-series/item track & speed preferences
/// - Fast JSON item cache for instant cold start even on 550k+ libraries
pub struct VedroStore {
    conn: Mutex<Connection>,
}

impl VedroStore {
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let p = path.as_ref();
        if let Some(parent) = p.parent() {
            if !parent.as_os_str().is_empty() {
                let _ = std::fs::create_dir_all(parent);
            }
        }
        let conn = Connection::open(p)?;
        restrict_unix_file_perms(p);
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.migrate()?;
        // Also restrict WAL/SHM companion files created during migrate
        restrict_unix_file_perms(p);
        Ok(store)
    }

    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.migrate()?;
        Ok(store)
    }

    fn migrate(&self) -> Result<()> {
        let conn = self.conn.lock();
        conn.execute_batch(
            "
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA busy_timeout = 5000;
            PRAGMA temp_store = MEMORY;
            PRAGMA cache_size = -16000;

            CREATE TABLE IF NOT EXISTS servers (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                url TEXT NOT NULL,
                dialect TEXT NOT NULL DEFAULT 'unknown',
                user_id TEXT,
                username TEXT,
                access_token TEXT,
                is_admin INTEGER NOT NULL DEFAULT 0,
                last_connected_at INTEGER NOT NULL DEFAULT 0,
                routes_json TEXT NOT NULL DEFAULT '[]',
                active_route_id TEXT
            );

            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value_json TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS track_preferences (
                server_id TEXT NOT NULL,
                scope_id TEXT NOT NULL,
                audio_lang TEXT,
                subtitle_lang TEXT,
                subtitle_disabled INTEGER NOT NULL DEFAULT 0,
                playback_speed REAL NOT NULL DEFAULT 1.0,
                skip_intro_secs INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (server_id, scope_id)
            );

            CREATE TABLE IF NOT EXISTS item_cache (
                server_id TEXT NOT NULL,
                cache_key TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                cached_at INTEGER NOT NULL,
                PRIMARY KEY (server_id, cache_key)
            );

            CREATE INDEX IF NOT EXISTS idx_servers_last_connected
                ON servers(last_connected_at DESC);
            CREATE INDEX IF NOT EXISTS idx_item_cache_cached_at
                ON item_cache(cached_at);
            ",
        )?;

        // Safe forward migration for existing v0.1.0/v0.1.1 databases
        let _ = conn.execute(
            "ALTER TABLE servers ADD COLUMN routes_json TEXT NOT NULL DEFAULT '[]'",
            [],
        );
        let _ = conn.execute("ALTER TABLE servers ADD COLUMN active_route_id TEXT", []);
        // Prune expired cache rows older than 7 days to keep DB lean
        let cutoff = chrono::Utc::now().timestamp() - 7 * 86_400;
        let _ = conn.execute(
            "DELETE FROM item_cache WHERE cached_at < ?1",
            params![cutoff],
        );
        Ok(())
    }

    pub fn upsert_server(&self, profile: &ServerProfile) -> Result<()> {
        let mut normalized = profile.clone();
        normalized.normalize_routes();
        let routes_json = serde_json::to_string(&normalized.routes)?;
        let conn = self.conn.lock();
        conn.execute(
            "INSERT INTO servers (id, name, url, dialect, user_id, username, access_token, is_admin, last_connected_at, routes_json, active_route_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
             ON CONFLICT(id) DO UPDATE SET
               name = excluded.name,
               url = excluded.url,
               dialect = excluded.dialect,
               user_id = excluded.user_id,
               username = excluded.username,
               access_token = excluded.access_token,
               is_admin = excluded.is_admin,
               last_connected_at = excluded.last_connected_at,
               routes_json = excluded.routes_json,
               active_route_id = excluded.active_route_id",
            params![
                normalized.id,
                normalized.name,
                normalized.url,
                normalized.dialect,
                normalized.user_id,
                normalized.username,
                normalized.access_token,
                if normalized.is_admin { 1 } else { 0 },
                normalized.last_connected_at,
                routes_json,
                normalized.active_route_id,
            ],
        )?;
        Ok(())
    }

    pub fn get_server(&self, id: &str) -> Result<Option<ServerProfile>> {
        let conn = self.conn.lock();
        let row_opt = conn
            .query_row(
                "SELECT id, name, url, dialect, user_id, username, access_token, is_admin, last_connected_at, routes_json, active_route_id
                 FROM servers WHERE id = ?1",
                params![id],
                row_to_server_profile,
            )
            .optional()?;
        Ok(row_opt.map(|mut p| {
            p.normalize_routes();
            p
        }))
    }

    pub fn list_servers(&self) -> Result<Vec<ServerProfile>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT id, name, url, dialect, user_id, username, access_token, is_admin, last_connected_at, routes_json, active_route_id
             FROM servers ORDER BY last_connected_at DESC",
        )?;
        let rows = stmt.query_map([], row_to_server_profile)?;
        let mut out = Vec::new();
        for r in rows {
            let mut p = r?;
            p.normalize_routes();
            out.push(p);
        }
        Ok(out)
    }

    pub fn delete_server(&self, id: &str) -> Result<()> {
        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;
        tx.execute("DELETE FROM servers WHERE id = ?1", params![id])?;
        tx.execute("DELETE FROM item_cache WHERE server_id = ?1", params![id])?;
        tx.execute(
            "DELETE FROM track_preferences WHERE server_id = ?1",
            params![id],
        )?;
        let home_key = format!("home_cache_v1:{id}");
        tx.execute("DELETE FROM settings WHERE key = ?1", params![home_key])?;
        tx.commit()?;
        Ok(())
    }

    /// Batch-fetch settings matching a key prefix using an indexed PRIMARY KEY B-tree range scan
    /// (avoids SQLite `LIKE` full-table scans and `_` wildcard ambiguity).
    pub fn get_settings_by_prefix(
        &self,
        prefix: &str,
    ) -> Result<std::collections::HashMap<String, String>> {
        let conn = self.conn.lock();
        let mut out = std::collections::HashMap::new();
        if prefix.is_empty() {
            let mut stmt = conn.prepare_cached("SELECT key, value_json FROM settings")?;
            let rows = stmt.query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })?;
            for r in rows {
                let (k, v) = r?;
                out.insert(k, v);
            }
            return Ok(out);
        }
        let upper = next_prefix_bound(prefix);
        match upper {
            Some(hi) => {
                let mut stmt = conn.prepare_cached(
                    "SELECT key, value_json FROM settings WHERE key >= ?1 AND key < ?2",
                )?;
                let rows = stmt.query_map(params![prefix, hi], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                })?;
                for r in rows {
                    let (k, v) = r?;
                    out.insert(k, v);
                }
            }
            None => {
                let mut stmt =
                    conn.prepare_cached("SELECT key, value_json FROM settings WHERE key >= ?1")?;
                let rows = stmt.query_map(params![prefix], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                })?;
                for r in rows {
                    let (k, v) = r?;
                    out.insert(k, v);
                }
            }
        }
        Ok(out)
    }

    /// Fetch a specific batch of setting keys using cached point lookups (O(K log N)).
    pub fn get_settings_by_keys(
        &self,
        keys: &[String],
    ) -> Result<std::collections::HashMap<String, String>> {
        let mut out = std::collections::HashMap::with_capacity(keys.len());
        if keys.is_empty() {
            return Ok(out);
        }
        let conn = self.conn.lock();
        let mut stmt = conn.prepare_cached("SELECT value_json FROM settings WHERE key = ?1")?;
        for k in keys {
            if let Some(v) = stmt
                .query_row(params![k], |row| row.get::<_, String>(0))
                .optional()?
            {
                out.insert(k.clone(), v);
            }
        }
        Ok(out)
    }

    /// Prune oldest rows matching a prefix in `settings` beyond `max_rows` (LRU cap).
    pub fn prune_settings_prefix(&self, prefix: &str, max_rows: usize) -> Result<usize> {
        if prefix.is_empty() {
            return Ok(0);
        }
        let conn = self.conn.lock();
        let removed = match next_prefix_bound(prefix) {
            Some(hi) => conn.execute(
                "DELETE FROM settings WHERE key >= ?1 AND key < ?2 AND key NOT IN (
                    SELECT key FROM settings WHERE key >= ?1 AND key < ?2
                    ORDER BY updated_at DESC LIMIT ?3
                )",
                params![prefix, hi, max_rows as i64],
            )?,
            None => conn.execute(
                "DELETE FROM settings WHERE key >= ?1 AND key NOT IN (
                    SELECT key FROM settings WHERE key >= ?1
                    ORDER BY updated_at DESC LIMIT ?2
                )",
                params![prefix, max_rows as i64],
            )?,
        };
        Ok(removed)
    }

    pub fn set_setting<T: Serialize>(&self, key: &str, value: &T) -> Result<()> {
        let json = serde_json::to_string(value)?;
        let now = chrono::Utc::now().timestamp();
        let conn = self.conn.lock();
        let mut stmt = conn.prepare_cached(
            "INSERT INTO settings (key, value_json, updated_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at",
        )?;
        stmt.execute(params![key, json, now])?;
        Ok(())
    }

    pub fn get_setting<T: for<'de> Deserialize<'de>>(&self, key: &str) -> Result<Option<T>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare_cached("SELECT value_json FROM settings WHERE key = ?1")?;
        let raw: Option<String> = stmt.query_row(params![key], |row| row.get(0)).optional()?;
        match raw {
            Some(s) => Ok(Some(serde_json::from_str(&s)?)),
            None => Ok(None),
        }
    }

    pub fn set_track_preference(&self, pref: &TrackPreference) -> Result<()> {
        let conn = self.conn.lock();
        conn.execute(
            "INSERT INTO track_preferences (server_id, scope_id, audio_lang, subtitle_lang, subtitle_disabled, playback_speed, skip_intro_secs)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(server_id, scope_id) DO UPDATE SET
               audio_lang = excluded.audio_lang,
               subtitle_lang = excluded.subtitle_lang,
               subtitle_disabled = excluded.subtitle_disabled,
               playback_speed = excluded.playback_speed,
               skip_intro_secs = excluded.skip_intro_secs",
            params![
                pref.server_id,
                pref.scope_id,
                pref.audio_lang,
                pref.subtitle_lang,
                if pref.subtitle_disabled { 1 } else { 0 },
                pref.playback_speed,
                pref.skip_intro_secs,
            ],
        )?;
        Ok(())
    }

    pub fn get_track_preference(
        &self,
        server_id: &str,
        scope_id: &str,
    ) -> Result<Option<TrackPreference>> {
        let conn = self.conn.lock();
        conn.query_row(
            "SELECT server_id, scope_id, audio_lang, subtitle_lang, subtitle_disabled, playback_speed, skip_intro_secs
             FROM track_preferences WHERE server_id = ?1 AND scope_id = ?2",
            params![server_id, scope_id],
            |row| {
                Ok(TrackPreference {
                    server_id: row.get(0)?,
                    scope_id: row.get(1)?,
                    audio_lang: row.get(2)?,
                    subtitle_lang: row.get(3)?,
                    subtitle_disabled: row.get::<_, i64>(4)? != 0,
                    playback_speed: row.get(5)?,
                    skip_intro_secs: row.get(6)?,
                })
            },
        )
        .optional()
        .map_err(StorageError::from)
    }

    pub fn put_cache(&self, server_id: &str, cache_key: &str, payload_json: &str) -> Result<()> {
        let now = chrono::Utc::now().timestamp();
        let conn = self.conn.lock();
        conn.execute(
            "INSERT INTO item_cache (server_id, cache_key, payload_json, cached_at) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(server_id, cache_key) DO UPDATE SET payload_json = excluded.payload_json, cached_at = excluded.cached_at",
            params![server_id, cache_key, payload_json, now],
        )?;
        Ok(())
    }

    pub fn get_cache(
        &self,
        server_id: &str,
        cache_key: &str,
        max_age_secs: i64,
    ) -> Result<Option<String>> {
        let cutoff = chrono::Utc::now().timestamp() - max_age_secs;
        let conn = self.conn.lock();
        conn.query_row(
            "SELECT payload_json FROM item_cache WHERE server_id = ?1 AND cache_key = ?2 AND cached_at >= ?3",
            params![server_id, cache_key, cutoff],
            |row| row.get(0),
        )
        .optional()
        .map_err(StorageError::from)
    }
}

#[cfg(unix)]
fn restrict_unix_file_perms(db_path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let base = db_path.to_string_lossy();
    for candidate in [
        db_path.to_path_buf(),
        std::path::PathBuf::from(format!("{base}-wal")),
        std::path::PathBuf::from(format!("{base}-shm")),
    ] {
        if candidate.exists() {
            let _ = std::fs::set_permissions(&candidate, std::fs::Permissions::from_mode(0o600));
        }
    }
}

#[cfg(not(unix))]
fn restrict_unix_file_perms(_db_path: &Path) {}

/// Compute the exclusive upper bound string for an indexed SQLite `key >= prefix AND key < upper` scan.
fn next_prefix_bound(prefix: &str) -> Option<String> {
    let mut bytes = prefix.as_bytes().to_vec();
    while let Some(last) = bytes.pop() {
        if last < 0xFF {
            bytes.push(last + 1);
            if let Ok(s) = String::from_utf8(bytes.clone()) {
                return Some(s);
            }
            bytes.pop();
        }
    }
    None
}

fn row_to_server_profile(row: &rusqlite::Row<'_>) -> rusqlite::Result<ServerProfile> {
    let routes_str: String = row.get::<_, Option<String>>(9)?.unwrap_or_default();
    let routes: Vec<ServerRoute> = serde_json::from_str(&routes_str).unwrap_or_default();
    Ok(ServerProfile {
        id: row.get(0)?,
        name: row.get(1)?,
        url: row.get(2)?,
        dialect: row.get(3)?,
        user_id: row.get(4)?,
        username: row.get(5)?,
        access_token: row.get(6)?,
        is_admin: row.get::<_, i64>(7)? != 0,
        last_connected_at: row.get(8)?,
        routes,
        active_route_id: row.get(10)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persists_servers_routes_settings_and_cache() {
        let store = VedroStore::open_in_memory().unwrap();
        store
            .upsert_server(&ServerProfile {
                id: "s1".into(),
                name: "My EmbyGo".into(),
                url: "https://cf.example.com".into(),
                dialect: "embygo".into(),
                user_id: Some("u1".into()),
                username: Some("alice".into()),
                access_token: Some("tok".into()),
                is_admin: true,
                last_connected_at: 1000,
                routes: vec![
                    ServerRoute {
                        id: "r1".into(),
                        name: "主线路".into(),
                        url: "https://cf.example.com".into(),
                        proxy_url: None,
                        accept_invalid_certs: false,
                    },
                    ServerRoute {
                        id: "r2".into(),
                        name: "香港直连".into(),
                        url: "https://hk.example.com".into(),
                        proxy_url: None,
                        accept_invalid_certs: false,
                    },
                ],
                active_route_id: Some("r1".into()),
            })
            .unwrap();

        let servers = store.list_servers().unwrap();
        assert_eq!(servers.len(), 1);
        assert_eq!(servers[0].dialect, "embygo");
        assert!(servers[0].is_admin);
        assert_eq!(servers[0].routes.len(), 2);
        assert_eq!(servers[0].active_route_id.as_deref(), Some("r1"));

        store.set_setting("tone_mapping", &"bt2446a").unwrap();
        let tm: Option<String> = store.get_setting("tone_mapping").unwrap();
        assert_eq!(tm.as_deref(), Some("bt2446a"));

        store.put_cache("s1", "home", r#"{"ok":true}"#).unwrap();
        assert_eq!(
            store.get_cache("s1", "home", 60).unwrap().as_deref(),
            Some(r#"{"ok":true}"#)
        );
    }
}
