# Prism Relay (Legacy Build Directory)

This was the standalone relay deployment build directory. The relay source was rsync'd
into `src/` for Docker builds on the server.

**Current state:** No `src/` directory — the Cargo.toml cannot build. The relay source
lives at `sync/crates/prism-sync-relay/`.

**Deployment infrastructure** (Dockerfile, docker-compose, provisioning, monitoring, debugging)
has moved to `deploy/` at the monorepo root.

**Tests:** The `tests/` directory contains integration tests (auth, cleanup, devices, sync,
WebSocket, etc.) that are more comprehensive than `sync/crates/prism-sync-relay/tests/`.
These should eventually be consolidated into the sync relay crate.
