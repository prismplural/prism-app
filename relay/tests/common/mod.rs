use prism_relay::db;
use tokio_rusqlite::Connection;

pub async fn test_db() -> Connection {
    db::open_memory().await.expect("Failed to open test db")
}
