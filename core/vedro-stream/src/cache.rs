use std::num::NonZeroUsize;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use bytes::Bytes;
use lru::LruCache;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

/// Default chunk size: 1 MiB (optimal balance for 4K UHD Remux streaming and fast seeks).
pub const DEFAULT_CHUNK_SIZE: u64 = 1024 * 1024;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CacheStats {
    pub chunk_size_bytes: u64,
    pub max_bytes: u64,
    pub cached_chunks: usize,
    pub cached_bytes: u64,
    pub hits: u64,
    pub misses: u64,
}

/// Thread-safe LRU chunk cache indexed by `(session_id, chunk_index)`.
#[derive(Clone)]
pub struct ChunkCache {
    chunk_size: u64,
    max_chunks: usize,
    inner: Arc<Mutex<LruCache<(String, u64), Bytes>>>,
    hits: Arc<AtomicU64>,
    misses: Arc<AtomicU64>,
}

impl ChunkCache {
    pub fn new(max_bytes: u64, chunk_size: u64) -> Self {
        let cs = chunk_size.max(64 * 1024);
        let max_chunks = (max_bytes / cs).max(8) as usize;
        let cap = NonZeroUsize::new(max_chunks).unwrap();
        Self {
            chunk_size: cs,
            max_chunks,
            inner: Arc::new(Mutex::new(LruCache::new(cap))),
            hits: Arc::new(AtomicU64::new(0)),
            misses: Arc::new(AtomicU64::new(0)),
        }
    }

    pub fn chunk_size(&self) -> u64 {
        self.chunk_size
    }

    pub fn get(&self, session_id: &str, chunk_idx: u64) -> Option<Bytes> {
        let mut guard = self.inner.lock();
        if let Some(val) = guard.get(&(session_id.to_string(), chunk_idx)) {
            self.hits.fetch_add(1, Ordering::Relaxed);
            Some(val.clone())
        } else {
            self.misses.fetch_add(1, Ordering::Relaxed);
            None
        }
    }

    pub fn peek_contains(&self, session_id: &str, chunk_idx: u64) -> bool {
        let guard = self.inner.lock();
        guard.contains(&(session_id.to_string(), chunk_idx))
    }

    pub fn put(&self, session_id: &str, chunk_idx: u64, data: Bytes) {
        let mut guard = self.inner.lock();
        guard.put((session_id.to_string(), chunk_idx), data);
    }

    pub fn evict_session(&self, session_id: &str) {
        let mut guard = self.inner.lock();
        let keys: Vec<(String, u64)> = guard
            .iter()
            .filter(|((sid, _), _)| sid == session_id)
            .map(|(k, _)| k.clone())
            .collect();
        for k in keys {
            guard.pop(&k);
        }
    }

    pub fn stats(&self) -> CacheStats {
        let guard = self.inner.lock();
        let cached_chunks = guard.len();
        let cached_bytes: u64 = guard.iter().map(|(_, b)| b.len() as u64).sum();
        CacheStats {
            chunk_size_bytes: self.chunk_size,
            max_bytes: self.max_chunks as u64 * self.chunk_size,
            cached_chunks,
            cached_bytes,
            hits: self.hits.load(Ordering::Relaxed),
            misses: self.misses.load(Ordering::Relaxed),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunk_cache_tracks_hits_misses_and_eviction() {
        let cache = ChunkCache::new(1024 * 1024, 64 * 1024);
        assert!(cache.get("s1", 0).is_none());
        cache.put("s1", 0, Bytes::from_static(b"hello"));
        assert_eq!(cache.get("s1", 0).unwrap().as_ref(), b"hello");

        let st = cache.stats();
        assert_eq!(st.hits, 1);
        assert_eq!(st.misses, 1);
        assert_eq!(st.cached_chunks, 1);

        cache.evict_session("s1");
        assert_eq!(cache.stats().cached_chunks, 0);
    }
}
