mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use base64::Engine;
use tower::ServiceExt;

async fn test_app() -> axum::Router {
    let db = common::test_db().await;
    let config = prism_relay::config::Config::from_env();
    let state = prism_relay::state::AppState::new(db, config);
    prism_relay::routes::router(state)
}

fn valid_sync_id() -> String {
    "a".repeat(64)
}

fn auth_token() -> String {
    "b".repeat(64)
}

fn auth_header() -> String {
    format!("Bearer {}", auth_token())
}

fn register_body() -> String {
    let engine = base64::engine::general_purpose::STANDARD;
    serde_json::json!({
        "signing_public_key": engine.encode([1u8; 32]),
        "x25519_public_key": engine.encode([2u8; 32]),
    })
    .to_string()
}

async fn register_device(
    app: &axum::Router,
    sync_id: &str,
    device_id: &str,
    auth: &str,
) -> StatusCode {
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
    resp.status()
}

/// Helper: set up app + state with two devices registered directly via DB.
/// Returns (Router, AppState) so tests can query the DB.
async fn app_with_two_devices() -> (axum::Router, prism_relay::state::AppState) {
    let db = common::test_db().await;
    let config = prism_relay::config::Config::from_env();
    let state = prism_relay::state::AppState::new(db, config);

    let sync_id = valid_sync_id();
    let token_hash = prism_relay::auth::hash_token(&auth_token());

    let sid = sync_id.clone();
    let th = token_hash.clone();
    let engine = base64::engine::general_purpose::STANDARD;
    let spk = engine.encode([1u8; 32]);
    let xpk = engine.encode([2u8; 32]);

    state
        .db
        .call(move |conn| -> Result<(), rusqlite::Error> {
            prism_relay::db::create_sync_group(conn, &sid, 0)?;
            prism_relay::db::register_device(conn, &sid, "dev-1", &th, &spk, &xpk, 0)?;
            prism_relay::db::register_device(conn, &sid, "dev-2", &th, &spk, &xpk, 0)?;
            Ok(())
        })
        .await
        .unwrap();

    let router = prism_relay::routes::router(state.clone());
    (router, state)
}

/// Helper: set up app + state with three devices registered directly via DB.
async fn app_with_three_devices() -> (axum::Router, prism_relay::state::AppState) {
    let db = common::test_db().await;
    let config = prism_relay::config::Config::from_env();
    let state = prism_relay::state::AppState::new(db, config);

    let sync_id = valid_sync_id();
    let token_hash = prism_relay::auth::hash_token(&auth_token());

    let sid = sync_id.clone();
    let th = token_hash.clone();
    let engine = base64::engine::general_purpose::STANDARD;
    let spk = engine.encode([1u8; 32]);
    let xpk = engine.encode([2u8; 32]);

    state
        .db
        .call(move |conn| -> Result<(), rusqlite::Error> {
            prism_relay::db::create_sync_group(conn, &sid, 0)?;
            prism_relay::db::register_device(conn, &sid, "dev-1", &th, &spk, &xpk, 0)?;
            prism_relay::db::register_device(conn, &sid, "dev-2", &th, &spk, &xpk, 0)?;
            prism_relay::db::register_device(conn, &sid, "dev-3", &th, &spk, &xpk, 0)?;
            Ok(())
        })
        .await
        .unwrap();

    let router = prism_relay::routes::router(state.clone());
    (router, state)
}

// ---- Tests for revoking another device (Case 1) ----

#[tokio::test]
async fn test_revoke_another_device_succeeds() {
    let (app, state) = app_with_two_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // dev-1 revokes dev-2
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-2", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // Verify: dev-2 is revoked, epoch is bumped to 1
    let sid = sync_id.clone();
    let (dev2_status, group_epoch, dev1_epoch) = state
        .db
        .call(move |conn| -> Result<(String, i64, i64), rusqlite::Error> {
            let dev2 = prism_relay::db::get_device(conn, &sid, "dev-2")?.unwrap();
            let epoch = prism_relay::db::get_sync_group_epoch(conn, &sid)?.unwrap();
            let dev1 = prism_relay::db::get_device(conn, &sid, "dev-1")?.unwrap();
            Ok((dev2.status, epoch, dev1.epoch))
        })
        .await
        .unwrap();

    assert_eq!(dev2_status, "revoked");
    assert_eq!(group_epoch, 1, "sync group epoch should be bumped to 1");
    assert_eq!(dev1_epoch, 1, "remaining active device epoch should be bumped to 1");
}

#[tokio::test]
async fn test_revoke_another_device_bumps_epoch_for_all_remaining() {
    let (app, state) = app_with_three_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // dev-1 revokes dev-3
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-3", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // Verify all remaining active devices have epoch 1
    let sid = sync_id.clone();
    let (dev1_epoch, dev2_epoch, dev3_status, group_epoch) = state
        .db
        .call(move |conn| -> Result<(i64, i64, String, i64), rusqlite::Error> {
            let dev1 = prism_relay::db::get_device(conn, &sid, "dev-1")?.unwrap();
            let dev2 = prism_relay::db::get_device(conn, &sid, "dev-2")?.unwrap();
            let dev3 = prism_relay::db::get_device(conn, &sid, "dev-3")?.unwrap();
            let epoch = prism_relay::db::get_sync_group_epoch(conn, &sid)?.unwrap();
            Ok((dev1.epoch, dev2.epoch, dev3.status, epoch))
        })
        .await
        .unwrap();

    assert_eq!(dev3_status, "revoked");
    assert_eq!(group_epoch, 1);
    assert_eq!(dev1_epoch, 1);
    assert_eq!(dev2_epoch, 1);
}

#[tokio::test]
async fn test_revoke_nonexistent_device_returns_not_found() {
    let (app, _state) = app_with_two_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // dev-1 tries to revoke a device that doesn't exist
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-999", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_revoke_already_revoked_device_returns_not_found() {
    let (app, _state) = app_with_three_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // dev-1 revokes dev-3 (first time succeeds)
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-3", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // dev-1 revokes dev-3 again (already revoked, no active row to update)
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-3", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

// ---- Tests for self-deregister (Case 2) ----

#[tokio::test]
async fn test_self_deregister_succeeds() {
    let (app, state) = app_with_two_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // dev-2 deregisters itself
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-2", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-2")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // Verify: dev-2 is fully removed (not just revoked), epoch is NOT bumped
    let sid = sync_id.clone();
    let (dev2_exists, group_epoch) = state
        .db
        .call(move |conn| -> Result<(bool, i64), rusqlite::Error> {
            let dev2 = prism_relay::db::get_device(conn, &sid, "dev-2")?;
            let epoch = prism_relay::db::get_sync_group_epoch(conn, &sid)?.unwrap();
            Ok((dev2.is_some(), epoch))
        })
        .await
        .unwrap();

    assert!(!dev2_exists, "self-deregister should DELETE the device row, not just revoke it");
    assert_eq!(group_epoch, 0, "self-deregister should NOT bump epoch");
}

#[tokio::test]
async fn test_self_deregister_cleans_up_receipts_and_rekey_artifacts() {
    let (app, state) = app_with_two_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Insert a device receipt and rekey artifact for dev-2
    let sid = sync_id.clone();
    state
        .db
        .call(move |conn| -> Result<(), rusqlite::Error> {
            prism_relay::db::upsert_device_receipt(conn, &sid, "dev-2", 5)?;
            prism_relay::db::store_rekey_artifact(conn, &sid, 0, "dev-2", b"wrapped-key")?;
            Ok(())
        })
        .await
        .unwrap();

    // dev-2 deregisters itself
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-2", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-2")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // Verify: device row, receipt, and rekey artifact are all gone
    let sid = sync_id.clone();
    let (dev2_exists, receipt_count, artifact) = state
        .db
        .call(move |conn| -> Result<(bool, u64, Option<Vec<u8>>), rusqlite::Error> {
            let dev2 = prism_relay::db::get_device(conn, &sid, "dev-2")?;
            let receipt_count: u64 = conn.query_row(
                "SELECT COUNT(*) FROM device_receipts WHERE sync_id = ?1 AND device_id = 'dev-2'",
                rusqlite::params![sid],
                |row| row.get(0),
            )?;
            let artifact = prism_relay::db::get_rekey_artifact(conn, &sid, 0, "dev-2")?;
            Ok((dev2.is_some(), receipt_count, artifact))
        })
        .await
        .unwrap();

    assert!(!dev2_exists, "device row should be deleted");
    assert_eq!(receipt_count, 0, "device receipt should be deleted");
    assert!(artifact.is_none(), "rekey artifact should be deleted");
}

#[tokio::test]
async fn test_self_deregister_does_not_affect_other_devices() {
    let (app, state) = app_with_three_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Insert receipts and artifacts for both dev-2 and dev-3
    let sid = sync_id.clone();
    state
        .db
        .call(move |conn| -> Result<(), rusqlite::Error> {
            prism_relay::db::upsert_device_receipt(conn, &sid, "dev-2", 5)?;
            prism_relay::db::upsert_device_receipt(conn, &sid, "dev-3", 3)?;
            prism_relay::db::store_rekey_artifact(conn, &sid, 0, "dev-2", b"key-2")?;
            prism_relay::db::store_rekey_artifact(conn, &sid, 0, "dev-3", b"key-3")?;
            Ok(())
        })
        .await
        .unwrap();

    // dev-2 deregisters itself
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-2", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-2")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // Verify: dev-3's data is untouched
    let sid = sync_id.clone();
    let (dev3_exists, dev3_receipt, dev3_artifact) = state
        .db
        .call(move |conn| -> Result<(bool, u64, Option<Vec<u8>>), rusqlite::Error> {
            let dev3 = prism_relay::db::get_device(conn, &sid, "dev-3")?;
            let receipt_count: u64 = conn.query_row(
                "SELECT COUNT(*) FROM device_receipts WHERE sync_id = ?1 AND device_id = 'dev-3'",
                rusqlite::params![sid],
                |row| row.get(0),
            )?;
            let artifact = prism_relay::db::get_rekey_artifact(conn, &sid, 0, "dev-3")?;
            Ok((dev3.is_some(), receipt_count, artifact))
        })
        .await
        .unwrap();

    assert!(dev3_exists, "dev-3 should still exist");
    assert_eq!(dev3_receipt, 1, "dev-3 receipt should still exist");
    assert!(dev3_artifact.is_some(), "dev-3 artifact should still exist");
}

#[tokio::test]
async fn test_self_deregister_last_device_forbidden() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Register a single device
    let status = register_device(&app, &sync_id, "dev-1", &auth).await;
    assert_eq!(status, StatusCode::CREATED);

    // dev-1 tries to deregister itself — should be forbidden (last active device)
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-1", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// ---- Tests for rekey artifact fetch ----

#[tokio::test]
async fn test_get_rekey_artifact_uses_header_device_id() {
    let (app, state) = app_with_two_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Store a rekey artifact for dev-1
    let sid = sync_id.clone();
    state
        .db
        .call(move |conn| -> Result<(), rusqlite::Error> {
            prism_relay::db::store_rekey_artifact(conn, &sid, 0, "dev-1", b"wrapped-key-1")?;
            prism_relay::db::store_rekey_artifact(conn, &sid, 0, "dev-2", b"wrapped-key-2")?;
            Ok(())
        })
        .await
        .unwrap();

    // dev-1 fetches its own rekey artifact (device_id from X-Device-Id header, not query)
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/sync/{}/rekey-artifacts?epoch=0", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    let engine = base64::engine::general_purpose::STANDARD;
    let wrapped = engine.decode(json["wrapped_key"].as_str().unwrap()).unwrap();
    assert_eq!(wrapped, b"wrapped-key-1", "should return dev-1's artifact, not dev-2's");
}

#[tokio::test]
async fn test_get_rekey_artifact_ignores_device_id_query_param() {
    let (app, state) = app_with_two_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Store rekey artifacts for both devices
    let sid = sync_id.clone();
    state
        .db
        .call(move |conn| -> Result<(), rusqlite::Error> {
            prism_relay::db::store_rekey_artifact(conn, &sid, 0, "dev-1", b"wrapped-key-1")?;
            prism_relay::db::store_rekey_artifact(conn, &sid, 0, "dev-2", b"wrapped-key-2")?;
            Ok(())
        })
        .await
        .unwrap();

    // dev-1 tries to fetch dev-2's artifact by passing device_id as query param
    // The query param should be ignored; it should return dev-1's artifact
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/sync/{}/rekey-artifacts?epoch=0&device_id=dev-2",
                    sync_id
                ))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    let engine = base64::engine::general_purpose::STANDARD;
    let wrapped = engine.decode(json["wrapped_key"].as_str().unwrap()).unwrap();
    assert_eq!(
        wrapped, b"wrapped-key-1",
        "should return the authenticated device's artifact, ignoring device_id query param"
    );
}

#[tokio::test]
async fn test_get_rekey_artifact_not_found_when_no_artifact() {
    let (app, _state) = app_with_two_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // No artifacts stored — should return 404
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/sync/{}/rekey-artifacts?epoch=0", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

// ---- Test: device list reflects revocation ----

#[tokio::test]
async fn test_list_devices_shows_revoked_status() {
    let (app, _state) = app_with_two_devices().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // dev-1 revokes dev-2
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}/devices/dev-2", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    // List devices — dev-2 should show as revoked with old epoch
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/sync/{}/devices", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let devices: Vec<serde_json::Value> = serde_json::from_slice(&body).unwrap();
    assert_eq!(devices.len(), 2);

    let dev1 = devices.iter().find(|d| d["device_id"] == "dev-1").unwrap();
    let dev2 = devices.iter().find(|d| d["device_id"] == "dev-2").unwrap();
    assert_eq!(dev1["status"], "active");
    assert_eq!(dev1["epoch"], 1); // bumped
    assert_eq!(dev2["status"], "revoked");
    assert_eq!(dev2["epoch"], 0); // not bumped (was revoked before epoch update)
}
