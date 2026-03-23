mod common;

use prism_relay::db;

#[tokio::test]
async fn test_prune_expired_invites() {
    let conn = common::test_db().await;

    conn.call(|conn| {
        conn.execute(
            "INSERT INTO invites (link_id, sync_id, data, created_at) VALUES ('old', 'aaa', '{}', 1)",
            [],
        )?;
        conn.execute(
            "INSERT INTO invites (link_id, sync_id, data, created_at) VALUES ('new', 'aaa', '{}', ?1)",
            rusqlite::params![db::now_secs() as i64],
        )?;
        Ok::<(), rusqlite::Error>(())
    })
    .await
    .unwrap();

    let pruned = conn
        .call(|conn| Ok::<usize, rusqlite::Error>(db::prune_expired_invites(conn, 1)?))
        .await
        .unwrap();

    assert_eq!(pruned, 1);

    let count = conn
        .call(|conn| {
            conn.query_row("SELECT COUNT(*) FROM invites", [], |row| row.get::<_, u64>(0))
        })
        .await
        .unwrap();
    assert_eq!(count, 1);
}

#[tokio::test]
async fn test_prune_stale_sync_groups_cascades() {
    let conn = common::test_db().await;

    conn.call(|conn| {
        db::create_sync_group(conn, "stale", 0)?;
        db::register_device(conn, "stale", "dev1", "hash", "spk", "xpk", 0)?;
        conn.execute(
            "UPDATE devices SET last_seen_at = 0 WHERE sync_id = 'stale' AND device_id = 'dev1'",
            [],
        )?;
        db::insert_batch(conn, "stale", 0, Some("dev1"), Some("batch-1"), b"payload")?;
        conn.execute(
            "INSERT INTO device_receipts (sync_id, device_id, confirmed_seq, updated_at) VALUES ('stale', 'dev1', 0, 0)",
            [],
        )?;
        Ok::<(), rusqlite::Error>(())
    })
    .await
    .unwrap();

    let pruned = conn
        .call(|conn| Ok::<usize, rusqlite::Error>(db::prune_stale_sync_groups(conn, 1)?))
        .await
        .unwrap();

    assert_eq!(pruned, 1);

    let batches = conn
        .call(|conn| Ok::<u64, rusqlite::Error>(db::count_batches(conn)?))
        .await
        .unwrap();
    assert_eq!(batches, 0);
}
