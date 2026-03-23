use prism_relay::hlc;

#[test]
fn test_normalize_hlc() {
    let normalized = hlc::normalize("1710000000000:0:nodeA").unwrap();
    assert_eq!(normalized, "00000001710000000000:0000000000:nodeA");
}

#[test]
fn test_normalize_already_padded() {
    let input = "01710000000000000000:0000000000:nodeA";
    assert_eq!(hlc::normalize(input).unwrap(), input);
}

#[test]
fn test_compare_by_timestamp() {
    let a = hlc::normalize("100:0:nodeA").unwrap();
    let b = hlc::normalize("200:0:nodeA").unwrap();
    assert!(a < b);
}

#[test]
fn test_compare_same_timestamp_different_counter() {
    let a = hlc::normalize("100:1:nodeA").unwrap();
    let b = hlc::normalize("100:2:nodeA").unwrap();
    assert!(a < b);
}

#[test]
fn test_compare_same_ts_counter_different_node() {
    let a = hlc::normalize("100:0:nodeA").unwrap();
    let b = hlc::normalize("100:0:nodeB").unwrap();
    assert!(a < b);
}

#[test]
fn test_parse_roundtrip() {
    let (ts, ctr, node) = hlc::parse("1710000000000:42:abc123").unwrap();
    assert_eq!(ts, 1710000000000u64);
    assert_eq!(ctr, 42u64);
    assert_eq!(node, "abc123");
}

#[test]
fn test_invalid_hlc_returns_error() {
    assert!(hlc::parse("garbage").is_err());
}

#[test]
fn test_invalid_hlc_bad_timestamp() {
    assert!(hlc::parse("notanumber:0:node").is_err());
}

#[test]
fn test_invalid_hlc_bad_counter() {
    assert!(hlc::parse("100:notanumber:node").is_err());
}

#[test]
fn test_normalize_invalid_returns_error() {
    assert!(hlc::normalize("garbage").is_err());
}
