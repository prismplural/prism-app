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

async fn register(app: &axum::Router, sync_id: &str, auth: &str) {
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/sync/{}/register", sync_id))
                .header("Authorization", auth)
                .header("X-Device-Id", "dev-1")
                .header("Content-Type", "application/json")
                .body(Body::from(register_body()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
}

#[tokio::test]
async fn test_invite_create_and_fetch() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    register(&app, &sync_id, &auth).await;

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/share/invite")
                .header("Authorization", &auth)
                .header("X-Sync-Id", &sync_id)
                .header("X-Device-Id", "dev-1")
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"pubkey":"abc123"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);

    let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let link_id = json["linkId"].as_str().unwrap();

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/share/invite/{}", link_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_invite_not_found() {
    let app = test_app().await;
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/share/invite/nonexistent")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_friend_keys_round_trip() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    register(&app, &sync_id, &auth).await;

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/share/friend123/keys")
                .header("Authorization", &auth)
                .header("X-Sync-Id", &sync_id)
                .header("X-Device-Id", "dev-1")
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"key":"encrypted-key-data"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_shared_data_round_trip() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    register(&app, &sync_id, &auth).await;

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/share/friend123/data")
                .header("Authorization", &auth)
                .header("X-Sync-Id", &sync_id)
                .header("X-Device-Id", "dev-1")
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"shared":"data"}"#))
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
                .uri("/v1/share/friend123/data")
                .header("Authorization", &auth)
                .header("X-Sync-Id", &sync_id)
                .header("X-Device-Id", "dev-1")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_share_auth_requires_sync_id_header() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    register(&app, &sync_id, &auth).await;

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/share/invite")
                .header("Authorization", &auth)
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"pubkey":"abc123"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_share_auth_requires_bearer_token() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    register(&app, &sync_id, &auth).await;

    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/share/invite")
                .header("X-Sync-Id", &sync_id)
                .header("X-Device-Id", "dev-1")
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"pubkey":"abc123"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_share_auth_rejects_wrong_token() {
    let app = test_app().await;
    let sync_id = valid_sync_id();
    let auth = auth_header();
    register(&app, &sync_id, &auth).await;

    let wrong_auth = format!("Bearer {}", "z".repeat(64));
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/share/invite")
                .header("Authorization", &wrong_auth)
                .header("X-Sync-Id", &sync_id)
                .header("X-Device-Id", "dev-1")
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"pubkey":"abc123"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}
