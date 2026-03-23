mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use base64::Engine;
use futures::{SinkExt, StreamExt};
use tokio::net::TcpListener;
use tower::ServiceExt;

fn valid_sync_id() -> String {
    "a".repeat(64)
}

fn auth_header() -> String {
    format!("Bearer {}", "b".repeat(64))
}

fn register_body() -> String {
    let engine = base64::engine::general_purpose::STANDARD;
    serde_json::json!({
        "signing_public_key": engine.encode([1u8; 32]),
        "x25519_public_key": engine.encode([2u8; 32]),
    })
    .to_string()
}

async fn start_server() -> (String, axum::Router, prism_relay::state::AppState) {
    let db = common::test_db().await;
    let config = prism_relay::config::Config::from_env();
    let state = prism_relay::state::AppState::new(db, config);
    let app = prism_relay::routes::router(state.clone());

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let app_clone = app.clone();
    tokio::spawn(async move {
        axum::serve(listener, app_clone).await.unwrap();
    });

    (format!("127.0.0.1:{}", addr.port()), app, state)
}

async fn register_device(app: &axum::Router, sync_id: &str, auth: &str) {
    register_named_device(app, sync_id, "testdevice", auth).await;
}

async fn register_named_device(app: &axum::Router, sync_id: &str, device_id: &str, auth: &str) {
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/sync/{}/register", sync_id))
                .header("Authorization", auth)
                .header("X-Device-Id", device_id)
                .header("Content-Type", "application/json")
                .body(Body::from(register_body()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
}

#[tokio::test]
async fn test_ws_connect_and_receive_notification() {
    let (addr, app, state) = start_server().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let token = "b".repeat(64);

    register_named_device(&app, &sync_id, "dev-1", &auth).await;
    let sync_id_for_seed = sync_id.clone();
    let token_hash = prism_relay::auth::hash_token(&token);
    state
        .db
        .call(move |conn| {
            prism_relay::db::register_device(
                conn,
                &sync_id_for_seed,
                "dev-2",
                &token_hash,
                &base64::engine::general_purpose::STANDARD.encode([3u8; 32]),
                &base64::engine::general_purpose::STANDARD.encode([4u8; 32]),
                0,
            )?;
            Ok::<(), rusqlite::Error>(())
        })
        .await
        .unwrap();

    let ws_url = format!(
        "ws://{}/v1/sync/{}/ws?device_id=dev-2&token={}",
        addr, sync_id, token
    );
    let (mut ws_stream, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("WebSocket connect failed");

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/sync/{}/changes", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .header("X-Epoch", "0")
                .header("X-Batch-Id", "batch-1")
                .body(Body::from(b"test-data".to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let msg = tokio::time::timeout(std::time::Duration::from_secs(2), ws_stream.next()).await;
    assert!(msg.is_ok(), "Should receive a WebSocket message within timeout");
    if let Ok(Some(Ok(msg))) = msg {
        let text = msg.to_text().unwrap();
        let json: serde_json::Value = serde_json::from_str(text).unwrap();
        assert_eq!(json["type"], "new_data");
        assert!(json["server_seq"].as_i64().unwrap() > 0);
    }
}

#[tokio::test]
async fn test_ws_rejected_invalid_sync_id() {
    let (addr, _app, _state) = start_server().await;
    let token = "b".repeat(64);

    let ws_url = format!(
        "ws://{}/v1/sync/invalid/ws?device_id=testdevice&token={}",
        addr, token
    );
    let result = tokio_tungstenite::connect_async(&ws_url).await;
    assert!(result.is_err(), "Should reject invalid sync ID");
}

#[tokio::test]
async fn test_ws_rejected_invalid_token() {
    let (addr, _app, _state) = start_server().await;
    let sync_id = valid_sync_id();

    let ws_url = format!(
        "ws://{}/v1/sync/{}/ws?device_id=testdevice&token=short",
        addr, sync_id
    );
    let result = tokio_tungstenite::connect_async(&ws_url).await;
    assert!(result.is_err(), "Should reject short/invalid token");
}

#[tokio::test]
async fn test_ws_rejected_unregistered() {
    let (addr, _app, _state) = start_server().await;
    let sync_id = valid_sync_id();
    let token = "b".repeat(64);

    let ws_url = format!(
        "ws://{}/v1/sync/{}/ws?device_id=testdevice&token={}",
        addr, sync_id, token
    );
    let result = tokio_tungstenite::connect_async(&ws_url).await;
    assert!(result.is_err(), "Should reject unregistered sync ID");
}

#[tokio::test]
async fn test_ws_ack_updates_receipt() {
    let (addr, app, _state) = start_server().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let token = "b".repeat(64);

    register_device(&app, &sync_id, &auth).await;

    let push_resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/sync/{}/changes", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "testdevice")
                .header("X-Epoch", "0")
                .header("X-Batch-Id", "batch-ack")
                .body(Body::from(b"ack-data".to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();
    let push_body = axum::body::to_bytes(push_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let push_json: serde_json::Value = serde_json::from_slice(&push_body).unwrap();
    let server_seq = push_json["server_seq"].as_i64().unwrap();

    let ws_url = format!(
        "ws://{}/v1/sync/{}/ws?device_id=testdevice&token={}",
        addr, sync_id, token
    );
    let (mut ws_stream, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("WebSocket connect failed");

    let ack = serde_json::json!({
        "type": "ack",
        "server_seq": server_seq,
    });
    ws_stream
        .send(tokio_tungstenite::tungstenite::Message::Text(
            ack.to_string().into(),
        ))
        .await
        .expect("Failed to send ack");

    tokio::time::sleep(std::time::Duration::from_millis(100)).await;

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/sync/{}/ack", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "testdevice")
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::json!({ "server_seq": server_seq }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    ws_stream.close(None).await.ok();
}
