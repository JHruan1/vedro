pub mod auth;
pub mod client;
pub mod dialect;
pub mod discovery;
pub mod error;
pub mod models;
pub mod websocket;

pub use auth::ClientIdentity;
pub use client::{ClientTransportOptions, EmbyClient};
pub use dialect::{ServerCapabilities, ServerDialect};
pub use discovery::discover_lan_servers;
pub use error::{ProtocolError, Result};
pub use models::*;
pub use websocket::{ServerPushEvent, WebSocketSession};
