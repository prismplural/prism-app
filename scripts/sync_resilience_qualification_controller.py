#!/usr/bin/env python3
"""Localhost rendezvous + relay fault proxy for the sync-resilience Gate A run.

Two listeners, both bound to 127.0.0.1 only:

  1. Controller (default port 50230) — the cross-device rendezvous the two
     device roles use for pairing handshake material and for barrier keys.
     Endpoints:
       GET  /health                 -> {"ok": true, "proxy_url": ...}
       GET  /kv/<run>/<key>         -> stored JSON value, or 404 if unset
       PUT  /kv/<run>/<key>         -> store a JSON value (bounded size)
       GET  /fault/status           -> live proxy gauges + historical totals
       POST /fault/arm              -> blackhole relay->client on the sockets
                                       that are upgraded right now
       POST /fault/clear            -> restore forwarding on every socket
     The full path after /kv/ is the key, so `/kv/<run>/<key>` and `/kv/<key>`
     both work.

  2. Fault proxy (default port 50226) — a raw TCP forwarder whose upstream is
     the real relay. It is a byte pump, so WebSocket Ping/Pong framing and HTTP
     are preserved. When armed, it drops upstream->client bytes for exactly the
     connections that were already upgraded at arm time; HTTP responses and any
     connection upgraded later keep flowing. The selected socket is left open
     rather than reset, which is the half-open receive fault.

`/fault/status` mixes two kinds of number:

  * Live gauges — `connections` and `upgraded_sockets` count only connections
    whose pump threads are still running, and drop back to zero as peers close.
  * Monotonic history — `upgraded_total` (every socket that ever upgraded),
    `upgraded_since_arm`, `blackholed_bytes`, and `forwarded_bytes` only grow.
    Replacement evidence comes from `upgraded_total`, not from the gauges.

A connection is removed from the live registry only after both of its pump
threads have unwound, so `connections` never counts a half-closed socket and
never drops a socket that can still carry bytes.

Run it on the host, install adb reverse for the controller, direct relay, and
fault proxy ports on the Android device, then point the roles at these URLs (see
the integration test header):

    python3 scripts/sync_resilience_qualification_controller.py \\
        --relay http://localhost:50225

    adb -s <serial> reverse tcp:50230 tcp:50230
    adb -s <serial> reverse tcp:50225 tcp:50225
    adb -s <serial> reverse tcp:50226 tcp:50226

Secrecy: pairing material and barrier values live only in memory and are never
written to disk or logged. Request headers (which carry relay bearer
credentials) and request bodies are never logged — only aggregate counters are
printed. Use a fresh `--relay` database per run; KV state is per-process.
"""

from __future__ import annotations

import argparse
import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

MAX_VALUE_BYTES = 2_000_000
RECV_BYTES = 65536


class Connection:
    """One proxied TCP connection, its fault state, and its lifecycle state.

    A connection is live from the moment it is registered until both pump
    threads have finished unwinding and its sockets have been closed. Every
    field here is guarded by the owning ``FaultProxy._lock``, except ``header``,
    which has a single writer: the upstream->client pump.
    """

    __slots__ = (
        "client",
        "upstream",
        "upgraded",
        "blackholed",
        "header",
        "active_pumps",
        "closed",
    )

    #: One pump thread per direction.
    PUMPS_PER_CONNECTION = 2

    def __init__(self, client: socket.socket, upstream: socket.socket) -> None:
        self.client = client
        self.upstream = upstream
        self.upgraded = False
        self.blackholed = False
        self.header = b""
        # Number of pump threads still running for this connection. It is
        # incremented for both pumps before the first one starts, so ``live``
        # is already accurate while the serving thread is still inside
        # ``_serve`` and the peer pump may not have been scheduled yet.
        self.active_pumps = self.PUMPS_PER_CONNECTION
        self.closed = False

    @property
    def live(self) -> bool:
        """True while either pump is still running. Caller must hold the lock."""
        return self.active_pumps > 0


def _close_socket(endpoint: socket.socket) -> None:
    """Shut down and close a socket once, tolerating an already-dead peer."""
    try:
        endpoint.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    try:
        endpoint.close()
    except OSError:
        pass


class FaultProxy:
    """Raw TCP forwarder that can blackhole one direction of a live WebSocket."""

    def __init__(self, listen_port: int, relay_url: str) -> None:
        parsed = urlparse(relay_url)
        self.listen_port = listen_port
        self.upstream_host = parsed.hostname or "127.0.0.1"
        self.upstream_port = parsed.port or (443 if parsed.scheme == "https" else 80)
        self._lock = threading.Lock()
        self._connections: list[Connection] = []
        self._server: socket.socket | None = None
        self._stopping = False
        self.armed = False
        self.blackholed_bytes = 0
        self.forwarded_bytes = 0
        self.upgraded_total = 0
        self.upgraded_since_arm = 0

    @property
    def proxy_url(self) -> str:
        return f"http://localhost:{self.listen_port}"

    def start(self) -> None:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", self.listen_port))
        server.listen(64)
        # Report the port actually bound, so `--proxy-port 0` (used by the
        # self-test) still yields a usable proxy_url.
        self.listen_port = server.getsockname()[1]
        self._server = server
        threading.Thread(target=self._accept_loop, daemon=True).start()

    def stop(self) -> None:
        self._stopping = True
        if self._server is not None:
            try:
                self._server.close()
            except OSError:
                pass
        with self._lock:
            connections = list(self._connections)
        # Idempotent: each pump also tears its own connection down once, and
        # double shutdown/close on a socket is tolerated by _close_socket.
        for connection in connections:
            _close_socket(connection.client)
            _close_socket(connection.upstream)

    def _accept_loop(self) -> None:
        while not self._stopping:
            try:
                client, _ = self._server.accept()  # type: ignore[union-attr]
            except OSError:
                return
            threading.Thread(target=self._serve, args=(client,), daemon=True).start()

    def _serve(self, client: socket.socket) -> None:
        try:
            upstream = socket.create_connection(
                (self.upstream_host, self.upstream_port), timeout=15
            )
        except OSError:
            _close_socket(client)
            return
        # The connect timeout must not leak into the byte pump: a live but idle
        # WebSocket can be quiet for far longer than 15s, and a timeout on the
        # socket would make recv() raise and tear the connection down.
        upstream.settimeout(None)
        connection = Connection(client, upstream)
        with self._lock:
            self._connections.append(connection)
            already_closing = self._stopping
        if already_closing:
            # stop() snapshotted the registry before this connection was
            # registered, so tear it down here instead of leaking it.
            _close_socket(client)
            _close_socket(upstream)
            return
        threading.Thread(
            target=self._pump,
            args=(client, upstream, connection, True),
            daemon=True,
        ).start()
        self._pump(upstream, client, connection, False)

    def _pump(
        self,
        source: socket.socket,
        destination: socket.socket,
        connection: Connection,
        client_to_upstream: bool,
    ) -> None:
        try:
            while True:
                try:
                    data = source.recv(RECV_BYTES)
                except OSError:
                    break
                if not data:
                    break
                if not client_to_upstream:
                    self._observe_response(connection, data)
                    with self._lock:
                        if connection.blackholed:
                            self.blackholed_bytes += len(data)
                            continue
                        self.forwarded_bytes += len(data)
                try:
                    destination.sendall(data)
                except OSError:
                    break
        finally:
            self._release_pumps(connection)

    def _release_pumps(self, connection: Connection) -> None:
        """Mark one pump done; tear the connection down once both have unwound.

        The first pump to finish shuts both endpoints down, which is what wakes
        its blocked peer (a half-closed TCP pair would otherwise linger). The
        sockets are closed by whichever pump unwinds last, so no pump ever
        closes a socket its peer is still using, and the connection stays
        registered as live in between.
        """
        with self._lock:
            connection.active_pumps = max(0, connection.active_pumps - 1)
            last_pump = connection.active_pumps == 0
        for endpoint in (connection.client, connection.upstream):
            try:
                endpoint.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        if not last_pump:
            return
        with self._lock:
            _close_socket(connection.client)
            _close_socket(connection.upstream)
            if connection.closed:
                return
            connection.closed = True
            self._connections = [c for c in self._connections if c is not connection]

    def _observe_response(self, connection: Connection, data: bytes) -> None:
        if connection.upgraded:
            return
        connection.header += data
        if len(connection.header) > 16384:
            connection.header = connection.header[-16384:]
        first_line = connection.header.split(b"\r\n", 1)[0]
        if b" 101 " in first_line:
            with self._lock:
                connection.upgraded = True
                self.upgraded_total += 1
                if self.armed:
                    self.upgraded_since_arm += 1

    def arm(self) -> dict:
        """Blackhole relay->client on the sockets upgraded as of right now."""
        with self._lock:
            self.armed = True
            targets = 0
            for connection in self._connections:
                # Only live sockets can be blackholed: a socket whose pumps have
                # already unwound carries no traffic, and marking it would leak
                # the fault state for a connection that is about to be removed.
                if connection.live and connection.upgraded and not connection.blackholed:
                    connection.blackholed = True
                    targets += 1
            return {
                "armed": True,
                "targets": targets,
                "upgraded_total": self.upgraded_total,
            }

    def clear(self) -> dict:
        with self._lock:
            self.armed = False
            for connection in self._connections:
                connection.blackholed = False
            return {"armed": False, "upgraded_total": self.upgraded_total}

    def status(self) -> dict:
        """Report live counts plus monotonic historical totals.

        ``connections`` and ``upgraded_sockets`` are live gauges: they drop as
        connections close. ``upgraded_total``, ``upgraded_since_arm``,
        ``blackholed_bytes``, and ``forwarded_bytes`` are monotonic history and
        never decrease. Closed connections are reaped by their pumps, so a
        non-zero count here is not proof of a leak unless it keeps growing while
        no connection could be open.
        """
        with self._lock:
            live = [c for c in self._connections if c.live]
            return {
                "armed": self.armed,
                "connections": len(live),
                "upgraded_sockets": sum(1 for c in live if c.upgraded),
                "upgraded_total": self.upgraded_total,
                "upgraded_since_arm": self.upgraded_since_arm,
                "blackholed_bytes": self.blackholed_bytes,
                "forwarded_bytes": self.forwarded_bytes,
                "blackholed_sockets": sum(1 for c in live if c.blackholed),
                "closing_connections": sum(1 for c in self._connections if not c.live),
                "proxy_url": self.proxy_url,
                "upstream": f"{self.upstream_host}:{self.upstream_port}",
                "uptime_ms": int((time.time() - self._started_at) * 1000),
            }

    _started_at = time.time()


class _State:
    def __init__(self, proxy: FaultProxy) -> None:
        self.proxy = proxy
        self.values: dict[str, object] = {}
        self.lock = threading.Lock()


def _make_handler(state: _State):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        # Never log request lines, headers, or bodies: headers can carry relay
        # bearer credentials and bodies can carry pairing handshake material.
        def log_message(self, *_args) -> None:  # noqa: D102
            pass

        def _respond(self, status: int, value: object) -> None:
            payload = json.dumps(value).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self) -> None:  # noqa: N802
            path = self.path.split("?", 1)[0]
            if path == "/health":
                return self._respond(
                    200,
                    {
                        "ok": True,
                        "proxy_url": state.proxy.proxy_url,
                        "upstream": state.proxy.status()["upstream"],
                    },
                )
            if path == "/fault/status":
                return self._respond(200, state.proxy.status())
            if path.startswith("/kv/"):
                key = unquote(path[len("/kv/") :])
                with state.lock:
                    if key not in state.values:
                        return self._respond(404, {"error": "not ready"})
                    value = state.values[key]
                return self._respond(200, value)
            return self._respond(404, {"error": "not found"})

        def do_POST(self) -> None:  # noqa: N802
            path = self.path.split("?", 1)[0]
            self._discard_body()
            if path == "/fault/arm":
                return self._respond(200, state.proxy.arm())
            if path == "/fault/clear":
                return self._respond(200, state.proxy.clear())
            return self._respond(404, {"error": "not found"})

        def do_PUT(self) -> None:  # noqa: N802
            path = self.path.split("?", 1)[0]
            size = int(self.headers.get("Content-Length", "0") or "0")
            if not path.startswith("/kv/"):
                self._discard_body()
                return self._respond(404, {"error": "not found"})
            if not 0 < size <= MAX_VALUE_BYTES:
                # Mirrors the historical controller contract: a missing
                # Content-Length is rejected rather than silently accepted.
                return self._respond(413, {"error": "invalid size"})
            raw = self.rfile.read(size)
            try:
                value = json.loads(raw)
            except ValueError:
                return self._respond(400, {"error": "invalid json"})
            key = unquote(path[len("/kv/") :])
            with state.lock:
                state.values[key] = value
            return self._respond(200, {"ok": True})

        def _discard_body(self) -> None:
            size = int(self.headers.get("Content-Length", "0") or "0")
            if size > 0:
                self.rfile.read(size)

    return Handler


# ── Host-only self-test ──────────────────────────────────────────────────────
#
#     python3 scripts/sync_resilience_qualification_controller.py --self-test
#
# Stands up a throwaway fake relay plus a FaultProxy on loopback and drives
# connect / upgrade / close / replacement, asserting that the `/fault/status`
# gauges follow live sockets while the historical totals only grow. It never
# touches the real relay, writes nothing to disk, and prints counters only.

_SELF_TEST_PLAIN_REQUEST = b"GET /health HTTP/1.1\r\nHost: relay.local\r\n\r\n"
_SELF_TEST_UPGRADE_REQUEST = (
    b"GET /ws HTTP/1.1\r\nHost: relay.local\r\nUpgrade: websocket\r\n\r\n"
)
_SELF_TEST_PLAIN_RESPONSE = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"
_SELF_TEST_UPGRADE_RESPONSE = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
)
#: Payload sizes the fake relay sends back when it sees these probe markers.
_SELF_TEST_BIG_PROBE = (b"send-big", 4096)
_SELF_TEST_SMALL_PROBE = (b"send-small", 16)
_POLL_SECONDS = 0.01


def _wait_for(predicate, timeout: float = 5.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(_POLL_SECONDS)
    return False


def _can_connect(port: int) -> bool:
    try:
        probe = socket.create_connection(("127.0.0.1", port), timeout=1)
    except OSError:
        return False
    probe.close()
    return True


class _FakeRelay:
    """Loopback stand-in for the relay: plain HTTP, or a 101 plus probe replies."""

    def __init__(self) -> None:
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind(("127.0.0.1", 0))
        self._server.listen(64)
        self.port = self._server.getsockname()[1]
        self._lock = threading.Lock()
        self.upgrades = 0
        threading.Thread(target=self._accept_loop, daemon=True).start()

    def stop(self) -> None:
        try:
            self._server.close()
        except OSError:
            pass

    def _accept_loop(self) -> None:
        while True:
            try:
                conn, _ = self._server.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _serve(self, conn: socket.socket) -> None:
        conn.settimeout(None)
        pending = b""
        upgraded = False
        try:
            while True:
                chunk = conn.recv(RECV_BYTES)
                if not chunk:
                    return
                if upgraded:
                    for marker, size in (_SELF_TEST_BIG_PROBE, _SELF_TEST_SMALL_PROBE):
                        if marker in chunk:
                            conn.sendall(b"p" * size)
                    continue
                pending += chunk
                if b"\r\n\r\n" not in pending:
                    continue
                head, pending = pending.split(b"\r\n\r\n", 1)
                if b"Upgrade:" in head:
                    conn.sendall(_SELF_TEST_UPGRADE_RESPONSE)
                    upgraded = True
                    with self._lock:
                        self.upgrades += 1
                else:
                    conn.sendall(_SELF_TEST_PLAIN_RESPONSE)
        except OSError:
            return
        finally:
            _close_socket(conn)


class _TestClient:
    """Loopback client with the few helpers the self-test needs."""

    def __init__(self, port: int) -> None:
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        self._pending = b""

    def send(self, payload: bytes) -> None:
        self.sock.sendall(payload)

    def _read_until(self, marker: bytes, timeout: float = 5.0) -> bytes:
        self.sock.settimeout(timeout)
        while marker not in self._pending:
            chunk = self.sock.recv(RECV_BYTES)
            if not chunk:
                break
            self._pending += chunk
        head, _, rest = self._pending.partition(marker)
        self._pending = rest
        return head + marker

    def plain_request(self) -> bytes:
        self.send(_SELF_TEST_PLAIN_REQUEST)
        return self._read_until(b"\r\n\r\n")

    def upgrade(self) -> bytes:
        self.send(_SELF_TEST_UPGRADE_REQUEST)
        return self._read_until(b"\r\n\r\n")

    def recv_quiet(self, timeout: float = 0.4) -> bytes | None:
        """Bytes if any arrive before the timeout, else None (timeout or EOF)."""
        self.sock.settimeout(timeout)
        try:
            data = self.sock.recv(RECV_BYTES)
        except OSError:
            return None
        return data or None

    def expect_closed(self, timeout: float = 3.0) -> bool:
        """True when the peer closed or reset the socket within the timeout."""
        deadline = time.time() + timeout
        self.sock.settimeout(0.1)
        while time.time() < deadline:
            try:
                data = self.sock.recv(RECV_BYTES)
            except OSError:
                return True
            if not data:
                return True
        return False

    def close(self) -> None:
        _close_socket(self.sock)


class _Checks:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def check(self, name: str, ok: bool, detail: str = "") -> None:
        suffix = f" ({detail})" if detail else ""
        print(f"  [{'ok' if ok else 'FAIL'}] {name}{suffix}", flush=True)
        if not ok:
            self.failures.append(name)


def run_self_test() -> int:
    """Drive proxy connect/upgrade/close/replacement on loopback; 0 on success."""
    checks = _Checks()
    relay = _FakeRelay()
    proxy = FaultProxy(0, f"http://127.0.0.1:{relay.port}")
    proxy.start()
    clients: list[_TestClient] = []
    try:
        checks.check(
            "proxy binds a loopback port",
            proxy.listen_port > 0,
            f"port {proxy.listen_port}",
        )
        status = proxy.status()
        checks.check(
            "idle status reports no live connections",
            status["connections"] == 0 and status["upgraded_sockets"] == 0,
        )
        checks.check(
            "idle status reports zero history",
            status["upgraded_total"] == 0
            and status["forwarded_bytes"] == 0
            and status["blackholed_bytes"] == 0,
        )

        # ── Plain HTTP keeps working and counts as a live connection ─────────
        http = _TestClient(proxy.listen_port)
        clients.append(http)
        checks.check(
            "plain HTTP response passes through the proxy",
            b"200 OK" in http.plain_request(),
        )
        _wait_for(lambda: proxy.status()["connections"] == 1)
        status = proxy.status()
        checks.check(
            "one live HTTP connection is one live connection",
            status["connections"] == 1,
            f"connections={status['connections']}",
        )
        checks.check(
            "an HTTP-only connection is not counted as upgraded",
            status["upgraded_sockets"] == 0 and status["upgraded_total"] == 0,
        )
        checks.check(
            "HTTP bytes are counted as forwarded history",
            status["forwarded_bytes"] > 0,
            f"forwarded={status['forwarded_bytes']}",
        )
        http.close()
        checks.check(
            "closing the HTTP connection drops the live gauge",
            _wait_for(lambda: proxy.status()["connections"] == 0),
        )
        status = proxy.status()
        checks.check(
            "a closed connection leaves no residue in the registry",
            status["closing_connections"] == 0,
            f"closing={status['closing_connections']}",
        )

        # ── Upgrade accounting ───────────────────────────────────────────────
        live = _TestClient(proxy.listen_port)
        clients.append(live)
        checks.check(
            "upgrade handshake reaches the client",
            b"101 Switching Protocols" in live.upgrade(),
        )
        checks.check(
            "the upgraded socket is one live upgraded socket",
            _wait_for(lambda: proxy.status()["upgraded_sockets"] == 1),
        )
        status = proxy.status()
        checks.check(
            "upgraded_total records the upgrade as history",
            status["upgraded_total"] == 1,
            f"upgraded_total={status['upgraded_total']}",
        )
        checks.check(
            "an upgrade before arming is not counted since arm",
            status["upgraded_since_arm"] == 0,
        )

        # ── Arm blackholes exactly the live upgraded socket ──────────────────
        checks.check(
            "arm targets exactly the live upgraded socket",
            proxy.arm()["targets"] == 1,
        )
        blackholed_before = proxy.status()["blackholed_bytes"]
        big_marker, big_size = _SELF_TEST_BIG_PROBE
        live.send(big_marker)
        checks.check(
            "the armed socket drops relay->client bytes",
            _wait_for(
                lambda: proxy.status()["blackholed_bytes"] - blackholed_before
                >= big_size
            ),
        )
        checks.check("the blackholed client receives nothing", live.recv_quiet() is None)
        status = proxy.status()
        checks.check(
            "a blackholed socket stays live while armed",
            status["connections"] == 1 and status["blackholed_sockets"] == 1,
            f"connections={status['connections']} blackholed={status['blackholed_sockets']}",
        )

        proxy.clear()
        forwarded_before = proxy.status()["forwarded_bytes"]
        small_marker, small_size = _SELF_TEST_SMALL_PROBE
        live.send(small_marker)
        checks.check(
            "the cleared socket forwards again",
            _wait_for(
                lambda: proxy.status()["forwarded_bytes"] - forwarded_before
                >= small_size
            )
            and live.recv_quiet(1.0) is not None,
        )

        # ── Replacement while armed: new sockets stay unblackholed ───────────
        checks.check("re-arming retargets the live socket", proxy.arm()["targets"] == 1)
        replacement = _TestClient(proxy.listen_port)
        clients.append(replacement)
        checks.check(
            "replacement handshake reaches the client",
            b"101 Switching Protocols" in replacement.upgrade(),
        )
        checks.check(
            "the replacement is a second live upgraded socket",
            _wait_for(lambda: proxy.status()["upgraded_sockets"] == 2),
        )
        status = proxy.status()
        checks.check(
            "historical upgraded_total keeps growing",
            status["upgraded_total"] == 2,
            f"upgraded_total={status['upgraded_total']}",
        )
        checks.check(
            "a post-arm upgrade is counted since arm",
            status["upgraded_since_arm"] == 1,
            f"upgraded_since_arm={status['upgraded_since_arm']}",
        )
        checks.check(
            "only sockets upgraded at arm time are blackholed",
            status["blackholed_sockets"] == 1,
            f"blackholed={status['blackholed_sockets']}",
        )
        forwarded_before = status["forwarded_bytes"]
        replacement.send(small_marker)
        checks.check(
            "the replacement still forwards while armed",
            _wait_for(
                lambda: proxy.status()["forwarded_bytes"] - forwarded_before
                >= small_size
            )
            and replacement.recv_quiet(1.0) is not None,
        )
        proxy.clear()

        # ── Close and replacement accounting ────────────────────────────────
        live.close()
        checks.check(
            "closing one socket drops exactly one live socket",
            _wait_for(
                lambda: proxy.status()["connections"] == 1
                and proxy.status()["upgraded_sockets"] == 1
            ),
        )
        status = proxy.status()
        checks.check(
            "closing a socket does not decrement history",
            status["upgraded_total"] == 2 and status["upgraded_since_arm"] == 1,
        )
        checks.check(
            "the closed socket is reaped from the registry",
            status["closing_connections"] == 0,
            f"closing={status['closing_connections']}",
        )
        history = (
            status["upgraded_total"],
            status["blackholed_bytes"],
            status["forwarded_bytes"],
        )
        replacement.close()
        checks.check(
            "closing the last socket zeroes the gauges",
            _wait_for(
                lambda: proxy.status()["connections"] == 0
                and proxy.status()["upgraded_sockets"] == 0
            ),
        )
        status = proxy.status()
        checks.check(
            "all gauges are zero and nothing is left closing",
            status["upgraded_sockets"] == 0 and status["closing_connections"] == 0,
        )
        checks.check(
            "history is untouched by closing",
            (
                status["upgraded_total"],
                status["blackholed_bytes"],
                status["forwarded_bytes"],
            )
            == history,
        )

        # ── Concurrent churn stays consistent ───────────────────────────────
        churn_count = 12
        base_total = proxy.status()["upgraded_total"]
        errors: list[BaseException] = []

        def churn() -> None:
            try:
                client = _TestClient(proxy.listen_port)
                try:
                    client.upgrade()
                    client.send(small_marker)
                    client.recv_quiet(1.0)
                finally:
                    client.close()
            except BaseException as exc:  # reported, never raised
                errors.append(exc)

        threads = [
            threading.Thread(target=churn, daemon=True) for _ in range(churn_count)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=10)
        checks.check("concurrent churn raises nothing", not errors, f"{len(errors)} errors")
        checks.check(
            "concurrent churn reaps every connection",
            _wait_for(
                lambda: proxy.status()["connections"] == 0
                and proxy.status()["closing_connections"] == 0
            ),
        )
        status = proxy.status()
        checks.check(
            "concurrent churn counts every upgrade exactly once",
            status["upgraded_total"] == base_total + churn_count,
            f"upgraded_total={status['upgraded_total']}",
        )
        checks.check(
            "proxy upgrade history matches the upgrade handshakes the relay served",
            relay.upgrades == status["upgraded_total"],
            f"relay_upgrades={relay.upgrades} upgraded_total={status['upgraded_total']}",
        )

        # ── stop() closes live sockets without double-close hazards ──────────
        lingering = _TestClient(proxy.listen_port)
        clients.append(lingering)
        lingering.upgrade()
        checks.check(
            "the stop-check socket is live before stop",
            _wait_for(lambda: proxy.status()["upgraded_sockets"] == 1),
        )
        proxy.stop()
        checks.check("stop() closes the live proxied socket", lingering.expect_closed())
        checks.check(
            "stop() leaves no live connections",
            _wait_for(lambda: proxy.status()["connections"] == 0),
        )
        checks.check(
            "the proxy port stops accepting after stop()",
            not _can_connect(proxy.listen_port),
        )
        proxy.stop()  # idempotent: must not raise on an already-closed proxy
        checks.check("stop() is idempotent", True)
    finally:
        proxy.stop()
        relay.stop()
        for client in clients:
            client.close()

    if checks.failures:
        print(
            f"SELF-TEST FAILED ({len(checks.failures)}): "
            + ", ".join(checks.failures),
            flush=True,
        )
        return 1
    print(
        "SELF-TEST PASSED: live gauges track open sockets; historical totals "
        "stay monotonic.",
        flush=True,
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rendezvous KV + relay fault proxy for the Gate A harness.",
    )
    parser.add_argument("--port", type=int, default=50230, help="controller port")
    parser.add_argument(
        "--proxy-port",
        type=int,
        default=50226,
        help="fixed fault-proxy port (adb reverse needs a known port)",
    )
    parser.add_argument(
        "--relay",
        default="http://localhost:50225",
        help="real relay the fault proxy forwards to",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help=(
            "run the host-only loopback lifecycle/fault self-test and exit "
            "(does not start the controller or touch the real relay)"
        ),
    )
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    proxy = FaultProxy(args.proxy_port, args.relay)
    proxy.start()

    state = _State(proxy)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), _make_handler(state))
    print(f"CONTROLLER_URL=http://localhost:{server.server_port}", flush=True)
    print(f"PROXY_URL={proxy.proxy_url}", flush=True)
    print(f"RELAY_UPSTREAM={proxy.upstream_host}:{proxy.upstream_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        proxy.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
