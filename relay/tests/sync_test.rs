mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};
use std::collections::BTreeMap;
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

/// Build a register body using a real Ed25519 public key for signature verification.
fn register_body_with_signing_key(signing_key: &SigningKey) -> String {
    let engine = base64::engine::general_purpose::STANDARD;
    let verifying_key = signing_key.verifying_key();
    serde_json::json!({
        "signing_public_key": engine.encode(verifying_key.as_bytes()),
        "x25519_public_key": engine.encode([2u8; 32]),
    })
    .to_string()
}

/// Build a register body for a second device, including a signed invitation.
fn register_body_with_invitation(
    dev2_x25519_pk: &[u8; 32],
    signed_invitation: &str,
) -> String {
    let engine = base64::engine::general_purpose::STANDARD;
    serde_json::json!({
        "signing_public_key": engine.encode([3u8; 32]),
        "x25519_public_key": engine.encode(dev2_x25519_pk),
        "signed_invitation": signed_invitation,
    })
    .to_string()
}

/// Create a valid signed invitation JSON string.
fn make_signed_invitation(
    signing_key: &SigningKey,
    inviter_device_id: &str,
    target_device_id: &str,
    target_x25519_pk: &[u8; 32],
    sync_id: &str,
    epoch: i64,
    invitation_id: &str,
    valid_until: &str,
) -> String {
    let engine = base64::engine::general_purpose::STANDARD;
    // Build the invitation as a BTreeMap so serialization order matches the server
    let mut invitation = BTreeMap::new();
    invitation.insert("epoch".to_string(), serde_json::json!(epoch));
    invitation.insert("id".to_string(), serde_json::json!(invitation_id));
    invitation.insert("sync_id".to_string(), serde_json::json!(sync_id));
    invitation.insert("target_device_id".to_string(), serde_json::json!(target_device_id));
    invitation.insert(
        "target_x25519_public_key".to_string(),
        serde_json::json!(engine.encode(target_x25519_pk)),
    );
    invitation.insert("valid_until".to_string(), serde_json::json!(valid_until));

    let invitation_bytes = serde_json::to_vec(&invitation).unwrap();
    let signature = signing_key.sign(&invitation_bytes);

    serde_json::json!({
        "invitation": invitation,
        "signature": engine.encode(signature.to_bytes()),
        "inviter_device_id": inviter_device_id,
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

/// Register a device with a custom body (for invitation-based registration).
async fn register_device_with_body(
    app: &axum::Router,
    sync_id: &str,
    device_id: &str,
    auth: &str,
    body: String,
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
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    resp.status()
}

#[tokio::test]
async fn test_register_and_push_pull() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    let status = register_device(&app, &sync_id, "dev-1", &auth).await;
    assert_eq!(status, StatusCode::CREATED);

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
                .header("Content-Type", "application/octet-stream")
                .body(Body::from(b"encrypted-data".to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/sync/{}/changes?since=0", sync_id))
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
    let batches = json["batches"].as_array().unwrap();
    assert_eq!(batches.len(), 1);
    assert!(json["max_server_seq"].as_i64().unwrap() > 0);
}

#[tokio::test]
async fn test_unauthorized_without_register() {
    let app = test_app().await;
    let sync_id = valid_sync_id();

    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/sync/{}/changes?since=0", sync_id))
                .header("Authorization", format!("Bearer {}", "c".repeat(64)))
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_invalid_sync_id_rejected() {
    let app = test_app().await;
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/sync/invalid/register")
                .header("Authorization", auth_header())
                .header("X-Device-Id", "dev-1")
                .header("Content-Type", "application/json")
                .body(Body::from(register_body()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_snapshot_round_trip() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    let status = register_device(&app, &sync_id, "dev-1", &auth).await;
    assert_eq!(status, StatusCode::CREATED);

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/sync/{}/snapshot", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .header("X-Epoch", "0")
                .header("X-Server-Seq-At", "0")
                .header("Content-Type", "application/octet-stream")
                .body(Body::from(b"snapshot-data".to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/sync/{}/snapshot", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(resp.headers().get("X-Epoch").unwrap(), "0");
    assert_eq!(resp.headers().get("X-Server-Seq-At").unwrap(), "0");

    let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(body.as_ref(), b"snapshot-data");
}

#[tokio::test]
async fn test_delete_account() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    let status = register_device(&app, &sync_id, "dev-1", &auth).await;
    assert_eq!(status, StatusCode::CREATED);

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/sync/{}", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/sync/{}/changes?since=0", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_payload_too_large() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    let status = register_device(&app, &sync_id, "dev-1", &auth).await;
    assert_eq!(status, StatusCode::CREATED);

    let big_data = vec![0u8; 1_100_000];
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/sync/{}/changes", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .header("X-Epoch", "0")
                .header("X-Batch-Id", "batch-big")
                .body(Body::from(big_data))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::PAYLOAD_TOO_LARGE);
}

async fn push_batch(
    app: &axum::Router,
    sync_id: &str,
    device_id: &str,
    auth: &str,
    batch_id: &str,
) -> StatusCode {
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/sync/{}/changes", sync_id))
                .header("Authorization", auth)
                .header("X-Device-Id", device_id)
                .header("X-Epoch", "0")
                .header("X-Batch-Id", batch_id)
                .header("Content-Type", "application/octet-stream")
                .body(Body::from(b"data".to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();
    resp.status()
}

async fn upload_snapshot(
    app: &axum::Router,
    sync_id: &str,
    device_id: &str,
    auth: &str,
    server_seq_at: i64,
) -> StatusCode {
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/sync/{}/snapshot", sync_id))
                .header("Authorization", auth)
                .header("X-Device-Id", device_id)
                .header("X-Epoch", "0")
                .header("X-Server-Seq-At", server_seq_at.to_string())
                .header("Content-Type", "application/octet-stream")
                .body(Body::from(b"snapshot-data".to_vec()))
                .unwrap(),
        )
        .await
        .unwrap();
    resp.status()
}

#[tokio::test]
async fn test_snapshot_watermark_first_upload_succeeds() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    assert_eq!(register_device(&app, &sync_id, "dev-1", &auth).await, StatusCode::CREATED);

    // Push batches to create seq values
    for i in 1..=5 {
        assert_eq!(
            push_batch(&app, &sync_id, "dev-1", &auth, &format!("batch-{}", i)).await,
            StatusCode::OK
        );
    }

    // First snapshot at seq 5 should succeed (no prior watermark)
    assert_eq!(
        upload_snapshot(&app, &sync_id, "dev-1", &auth, 5).await,
        StatusCode::NO_CONTENT
    );
}

#[tokio::test]
async fn test_snapshot_watermark_rejects_regression() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    assert_eq!(register_device(&app, &sync_id, "dev-1", &auth).await, StatusCode::CREATED);

    for i in 1..=7 {
        assert_eq!(
            push_batch(&app, &sync_id, "dev-1", &auth, &format!("batch-{}", i)).await,
            StatusCode::OK
        );
    }

    // Upload snapshot at seq 5
    assert_eq!(
        upload_snapshot(&app, &sync_id, "dev-1", &auth, 5).await,
        StatusCode::NO_CONTENT
    );

    // Try to upload at seq 3 — should be rejected
    assert_eq!(
        upload_snapshot(&app, &sync_id, "dev-1", &auth, 3).await,
        StatusCode::BAD_REQUEST
    );
}

#[tokio::test]
async fn test_snapshot_watermark_allows_advancement() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    assert_eq!(register_device(&app, &sync_id, "dev-1", &auth).await, StatusCode::CREATED);

    for i in 1..=7 {
        assert_eq!(
            push_batch(&app, &sync_id, "dev-1", &auth, &format!("batch-{}", i)).await,
            StatusCode::OK
        );
    }

    // Upload snapshot at seq 5
    assert_eq!(
        upload_snapshot(&app, &sync_id, "dev-1", &auth, 5).await,
        StatusCode::NO_CONTENT
    );

    // Upload at seq 7 — should succeed (advancing watermark)
    assert_eq!(
        upload_snapshot(&app, &sync_id, "dev-1", &auth, 7).await,
        StatusCode::NO_CONTENT
    );
}

// ---- Invitation-based second-device registration tests ----

/// A far-future RFC3339 timestamp for valid invitations.
fn future_valid_until() -> String {
    "2099-01-01T00:00:00Z".to_string()
}

/// Register dev-1 with a real Ed25519 signing key, then return the app and the signing key.
async fn setup_first_device_with_signing_key() -> (axum::Router, SigningKey) {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Use a deterministic seed for the signing key
    let signing_key = SigningKey::from_bytes(&[42u8; 32]);
    let body = register_body_with_signing_key(&signing_key);

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/sync/{}/register", sync_id))
                .header("Authorization", &auth)
                .header("X-Device-Id", "dev-1")
                .header("Content-Type", "application/json")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);

    (app, signing_key)
}

#[tokio::test]
async fn test_second_device_with_valid_invitation_succeeds() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let dev2_x25519_pk = [5u8; 32];

    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &dev2_x25519_pk,
        &sync_id,
        0, // current epoch
        "inv-001",
        &future_valid_until(),
    );
    let body = register_body_with_invitation(&dev2_x25519_pk, &invitation);

    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(status, StatusCode::CREATED);
}

#[tokio::test]
async fn test_second_device_without_invitation_fails() {
    let (app, _signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Try to register dev-2 without an invitation (using the standard body)
    let status = register_device(&app, &sync_id, "dev-2", &auth).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "Second device registration without invitation should be rejected"
    );
}

#[tokio::test]
async fn test_second_device_with_invalid_signature_fails() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let dev2_x25519_pk = [5u8; 32];
    let engine = base64::engine::general_purpose::STANDARD;

    // Create a valid invitation but with a wrong signature
    let mut invitation = BTreeMap::new();
    invitation.insert("epoch".to_string(), serde_json::json!(0));
    invitation.insert("id".to_string(), serde_json::json!("inv-002"));
    invitation.insert("sync_id".to_string(), serde_json::json!(sync_id));
    invitation.insert("target_device_id".to_string(), serde_json::json!("dev-2"));
    invitation.insert(
        "target_x25519_public_key".to_string(),
        serde_json::json!(engine.encode(dev2_x25519_pk)),
    );
    invitation.insert("valid_until".to_string(), serde_json::json!(future_valid_until()));

    // Sign with a DIFFERENT key (not dev-1's key)
    let wrong_key = SigningKey::from_bytes(&[99u8; 32]);
    let invitation_bytes = serde_json::to_vec(&invitation).unwrap();
    let bad_signature = wrong_key.sign(&invitation_bytes);

    let signed_invitation = serde_json::json!({
        "invitation": invitation,
        "signature": engine.encode(bad_signature.to_bytes()),
        "inviter_device_id": "dev-1",
    })
    .to_string();

    let body = register_body_with_invitation(&dev2_x25519_pk, &signed_invitation);
    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "Invalid signature should be rejected"
    );

    // Sanity: verify the correct key still works (not a test setup issue)
    let good_invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &dev2_x25519_pk,
        &sync_id,
        0,
        "inv-002-retry",
        &future_valid_until(),
    );
    let good_body = register_body_with_invitation(&dev2_x25519_pk, &good_invitation);
    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, good_body).await;
    assert_eq!(status, StatusCode::CREATED);
}

#[tokio::test]
async fn test_second_device_with_wrong_target_device_id_fails() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let dev2_x25519_pk = [5u8; 32];

    // Invitation is for "dev-3" but we register as "dev-2"
    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-3", // wrong target
        &dev2_x25519_pk,
        &sync_id,
        0,
        "inv-003",
        &future_valid_until(),
    );
    let body = register_body_with_invitation(&dev2_x25519_pk, &invitation);

    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "Invitation for a different target device should be rejected"
    );
}

#[tokio::test]
async fn test_second_device_with_wrong_sync_id_fails() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let dev2_x25519_pk = [5u8; 32];

    // Invitation references a different sync_id
    let wrong_sync_id = "c".repeat(64);
    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &dev2_x25519_pk,
        &wrong_sync_id, // wrong sync_id
        0,
        "inv-004",
        &future_valid_until(),
    );
    let body = register_body_with_invitation(&dev2_x25519_pk, &invitation);

    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "Invitation for a different sync_id should be rejected"
    );
}

#[tokio::test]
async fn test_second_device_with_wrong_epoch_fails() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let dev2_x25519_pk = [5u8; 32];

    // Invitation has epoch 1 but group is at epoch 0
    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &dev2_x25519_pk,
        &sync_id,
        1, // wrong epoch
        "inv-005",
        &future_valid_until(),
    );
    let body = register_body_with_invitation(&dev2_x25519_pk, &invitation);

    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "Invitation with wrong epoch should be rejected"
    );
}

#[tokio::test]
async fn test_second_device_with_expired_invitation_fails() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let dev2_x25519_pk = [5u8; 32];

    // Invitation expired in the past
    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &dev2_x25519_pk,
        &sync_id,
        0,
        "inv-006",
        "2020-01-01T00:00:00Z", // expired
    );
    let body = register_body_with_invitation(&dev2_x25519_pk, &invitation);

    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "Expired invitation should be rejected"
    );
}

#[tokio::test]
async fn test_invitation_replay_fails() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    let dev2_x25519_pk = [5u8; 32];

    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &dev2_x25519_pk,
        &sync_id,
        0,
        "inv-007",
        &future_valid_until(),
    );
    let body = register_body_with_invitation(&dev2_x25519_pk, &invitation);

    // First use succeeds
    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body.clone()).await;
    assert_eq!(status, StatusCode::CREATED);

    // Replay: try to register dev-3 with the same invitation ID
    // (dev-2's invitation is consumed, so reusing invitation id "inv-007" should fail)
    let dev3_x25519_pk = [6u8; 32];
    let replayed_invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-3",
        &dev3_x25519_pk,
        &sync_id,
        0,
        "inv-007", // same invitation ID — already consumed
        &future_valid_until(),
    );
    let replay_body = register_body_with_invitation(&dev3_x25519_pk, &replayed_invitation);
    let status = register_device_with_body(&app, &sync_id, "dev-3", &auth, replay_body).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "Replayed (consumed) invitation should be rejected"
    );
}

#[tokio::test]
async fn test_second_device_with_wrong_x25519_key_fails() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Invitation is for x25519 key [5u8; 32] but registration body uses [9u8; 32]
    let invitation_x25519_pk = [5u8; 32];
    let actual_x25519_pk = [9u8; 32];

    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &invitation_x25519_pk, // invitation binds to this key
        &sync_id,
        0,
        "inv-008",
        &future_valid_until(),
    );
    let body = register_body_with_invitation(&actual_x25519_pk, &invitation); // body has different key

    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "Mismatched x25519 key should be rejected"
    );
}

// ---- List devices tests ----

#[tokio::test]
async fn test_list_devices_returns_registered_devices() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Register a second device via invitation
    let dev2_x25519_pk = [5u8; 32];
    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &dev2_x25519_pk,
        &sync_id,
        0,
        "inv-list-1",
        &future_valid_until(),
    );
    let body = register_body_with_invitation(&dev2_x25519_pk, &invitation);
    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(status, StatusCode::CREATED);

    // List devices
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
    assert_eq!(dev1["epoch"], 0);
    assert_eq!(dev2["status"], "active");
    assert_eq!(dev2["epoch"], 0);
}

#[tokio::test]
async fn test_list_devices_after_self_deregister_removes_device() {
    let (app, signing_key) = setup_first_device_with_signing_key().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();

    // Register dev-2 via invitation
    let dev2_x25519_pk = [5u8; 32];
    let invitation = make_signed_invitation(
        &signing_key,
        "dev-1",
        "dev-2",
        &dev2_x25519_pk,
        &sync_id,
        0,
        "inv-list-2",
        &future_valid_until(),
    );
    let body = register_body_with_invitation(&dev2_x25519_pk, &invitation);
    let status = register_device_with_body(&app, &sync_id, "dev-2", &auth, body).await;
    assert_eq!(status, StatusCode::CREATED);

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

    // List devices — only dev-1 should remain
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
    assert_eq!(devices.len(), 1, "Self-deregistered device should be fully removed from list");
    assert_eq!(devices[0]["device_id"], "dev-1");
}
