use prism_relay::auth;

#[test]
fn test_hash_token_deterministic() {
    let hash1 = auth::hash_token("test-token-value");
    let hash2 = auth::hash_token("test-token-value");
    assert_eq!(hash1, hash2);
}

#[test]
fn test_hash_token_different_inputs() {
    let hash1 = auth::hash_token("token-a");
    let hash2 = auth::hash_token("token-b");
    assert_ne!(hash1, hash2);
}

#[test]
fn test_hash_token_is_hex() {
    let hash = auth::hash_token("some-token");
    assert_eq!(hash.len(), 64);
    assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));
}

#[test]
fn test_timing_safe_equal_same() {
    assert!(auth::timing_safe_eq("abcdef", "abcdef"));
}

#[test]
fn test_timing_safe_equal_different() {
    assert!(!auth::timing_safe_eq("abcdef", "ghijkl"));
}

#[test]
fn test_timing_safe_equal_different_lengths() {
    assert!(!auth::timing_safe_eq("short", "longer-string"));
}

#[test]
fn test_validate_sync_id_valid() {
    let valid = "a".repeat(64);
    assert!(auth::is_valid_sync_id(&valid));
}

#[test]
fn test_validate_sync_id_too_short() {
    assert!(!auth::is_valid_sync_id("abc123"));
}

#[test]
fn test_validate_sync_id_invalid_chars() {
    let invalid = "g".repeat(64);
    assert!(!auth::is_valid_sync_id(&invalid));
}

#[test]
fn test_validate_token_min_length() {
    assert!(auth::is_valid_token(&"a".repeat(32)));
    assert!(!auth::is_valid_token(&"a".repeat(31)));
}
