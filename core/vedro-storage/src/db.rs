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
/// - Multi-server profiles (embygo / Emby / Jellyfin)
/// - App & Dolby Vision / Atmos settings KV
/// - Per-series/item track & speed preferences
/// - Fast JSON item cache for instant cold start even on 550k+ libraries
pub struct VedroStore {
    conn: Mutex<Connection>,
}

impl VedroStore {
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.migrate()?;
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

            CREATE TABLE IF NOT EXISTS servers (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                url TEXT NOT NULL,
                dialect TEXT NOT NULL DEFAULT 'unknown',
                user_id TEXT,
                username TEXT,
                access_token TEXT,
                is_admin INTEGER NOT NULL DEFAULT 0,
                last_connected_at INTEGER NOT NULL DEFAULT 0
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
            ",
        )?;
        Ok(())
    }

    pub fn upsert_server(&self, profile: &ServerProfile) -> Result<()> {
        let conn = self.conn.lock();
        conn.execute(
            "INSERT INTO servers (id, name, url, dialect, user_id, username, access_token, is_admin, last_connected_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(id) DO UPDATE SET
               name = excluded.name,
               url = excluded.url,
               dialect = excluded.dialect,
               user_id = excluded.user_id,
               username = excluded.username,
               access_token = excluded.access_token,
               is_admin = excluded.is_admin,
               last_connected_at = excluded.last_connected_at",
            params![
                profile.id,
                profile.name,
                profile.url,
                profile.dialect,
                profile.user_id,
                profile.username,
                profile.access_token,
                if profile.is_admin { 1 } else { 0 },
                profile.last_connected_at,
            ],
        )?;
        Ok(())
    }

    pub fn list_servers(&self) -> Result<Vec<ServerProfile>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT id, name, url, dialect, user_id, username, access_token, is_admin, last_connected_at
             FROM servers ORDER BY last_connected_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
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
            })
        })?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r?);
        }
        Ok(out)
    }

    pub fn delete_server(&self, id: &str) -> Result<()> {
        let conn = self.conn.lock();
        conn.execute("DELETE FROM servers WHERE id = ?1", params![id])?;
        conn.execute("DELETE FROM item_cache WHERE server_id = ?1", params![id])?;
        conn.execute(
            "DELETE FROM track_preferences WHERE server_id = ?1",
            params![id],
        )?;
        Ok(())
    }

    pub fn set_setting<T: Serialize>(&self, key: &str, value: &T) -> Result<()> {
        let json = serde_json::to_string(value)?;
        let now = chrono::Utc::now().timestamp();
        let conn = self.conn.lock();
        conn.execute(
            "INSERT INTO settings (key, value_json, updated_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at",
            params![key, json, now],
        )?;
        Ok(())
    }

    pub fn get_setting<T: for<'de> Deserialize<'de>>(&self, key: &str) -> Result<Option<T>> {
        let conn = self.conn.lock();
        let raw: Option<String> = conn
            .query_row(
                "SELECT value_json FROM settings WHERE key = ?1",
                params![key],
                |row| row.get(0),
            )
            .optional()?;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persists_servers_settings_and_cache() {
        let store = VedroStore::open_in_memory().unwrap();
        store
            .upsert_server(&ServerProfile {
                id: "s1".into(),
                name: "My EmbyGo".into(),
                url: "http://127.0.0.1:8097".into(),
                dialect: "embygo".into(),
                user_id: Some("u1".into()),
                username: Some("alice".into()),
                access_token: Some("tok".into()),
                is_admin: true,
                last_connected_at: 1000,
            })
            .unwrap();

        let servers = store.list_servers().unwrap();
        assert_eq!(servers.len(), 1);
        assert_eq!(servers[0].dialect, "embygo");
        assert!(servers[0].is_admin);

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
