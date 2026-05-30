import 'dart:async';
import 'dart:io'
    show
        ConnectionTask,
        HttpClient,
        InternetAddress,
        InternetAddressType,
        Socket,
        SocketException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const _allowedMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  // GIF is a raster format (the SVG/XML magic-byte check below still guards
  // mislabeled content). Without it, remote/SP-imported GIFs are rejected here
  // before the compression service's animated-GIF pass-through can handle them.
  'image/gif',
};

/// Returns `true` if the host should be blocked (private/loopback/link-local).
///
/// Rejects:
///   - Well-known private hostnames (localhost, *.local, metadata.internal)
///   - IPv4 literal addresses in private/loopback/APIPA ranges
///   - IPv6 loopback, link-local, ULA, and IPv4-mapped private addresses
///   - DNS names that resolve exclusively to private addresses
Future<bool> _isPrivateHost(String host) async {
  final lc = host.toLowerCase();

  // Reject well-known private hostnames immediately.
  if (lc == 'localhost' ||
      lc == 'metadata.internal' ||
      lc.endsWith('.local')) {
    return true;
  }

  // Try parsing as an IP literal first (no DNS needed).
  final parsed = InternetAddress.tryParse(host);
  if (parsed != null) {
    return _isPrivateAddress(parsed);
  }

  // Hostname: resolve and reject if any resolved address is private.
  try {
    final resolved = await InternetAddress.lookup(host);
    if (resolved.isEmpty) return true; // unresolvable → block
    for (final addr in resolved) {
      if (_isPrivateAddress(addr)) return true;
    }
    return false;
  } catch (_) {
    return true; // resolution failure → block to be safe
  }
}

/// IPv4 ranges that must never be fetched from (by leading octets).
bool _isPrivateV4(int a, int b) {
  if (a == 0) return true; // 0.0.0.0/8 (this-network / unspecified)
  if (a == 10) return true; // 10.0.0.0/8 private
  if (a == 127) return true; // 127.0.0.0/8 loopback
  if (a == 169 && b == 254) return true; // 169.254.0.0/16 APIPA / link-local
  if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12 private
  if (a == 192 && b == 168) return true; // 192.168.0.0/16 private
  if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
  return false;
}

bool _isPrivateAddress(InternetAddress addr) {
  if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;

  final raw = addr.rawAddress;

  if (addr.type == InternetAddressType.IPv4) {
    return _isPrivateV4(raw[0], raw[1]);
  }

  if (addr.type == InternetAddressType.IPv6) {
    // :: unspecified address (all zero) — not flagged by isLoopback.
    if (raw.every((b) => b == 0)) return true;
    // fc00::/7 — Unique Local Addresses (ULA)
    if ((raw[0] & 0xFE) == 0xFC) return true;
    // fe80::/10 — link-local (also caught by isLinkLocal)
    if (raw[0] == 0xFE && (raw[1] & 0xC0) == 0x80) return true;

    final firstTwelveZeroExceptTail = raw[4] == 0 &&
        raw[5] == 0 &&
        raw[6] == 0 &&
        raw[7] == 0 &&
        raw[8] == 0 &&
        raw[9] == 0;

    // IPv4-mapped: ::ffff:0:0/96 — validate the embedded IPv4 (bytes 12–15).
    final isV4Mapped = raw[0] == 0 &&
        raw[1] == 0 &&
        raw[2] == 0 &&
        raw[3] == 0 &&
        firstTwelveZeroExceptTail &&
        raw[10] == 0xFF &&
        raw[11] == 0xFF;
    if (isV4Mapped) return _isPrivateV4(raw[12], raw[13]);

    // NAT64 well-known prefix 64:ff9b::/96 — translates to arbitrary IPv4,
    // including internal hosts; block the whole range.
    final isNat64 = raw[0] == 0x00 &&
        raw[1] == 0x64 &&
        raw[2] == 0xFF &&
        raw[3] == 0x9B &&
        firstTwelveZeroExceptTail &&
        raw[10] == 0 &&
        raw[11] == 0;
    if (isNat64) return true;

    return false;
  }

  return false;
}

/// Builds an HTTP client that pins each connection to a validated, already
/// resolved IP address.
///
/// Without this, validation and connection perform *independent* DNS lookups:
/// an attacker domain with a low TTL can answer the validation lookup with a
/// public IP and the connection lookup with a private one (DNS rebinding /
/// resolve-then-connect TOCTOU). The [HttpClient.connectionFactory] resolves
/// the host once, rejects the connection if *any* resolved address is private,
/// then connects to that exact address — so the bytes we validate are the
/// bytes we connect to. TLS (SNI + certificate validation) still uses the
/// original hostname from the request URI, so HTTPS keeps working normally.
http.Client _buildPinnedClient() {
  final httpClient = HttpClient()..connectionFactory = _pinnedConnect;
  return IOClient(httpClient);
}

Future<ConnectionTask<Socket>> _pinnedConnect(
  Uri url,
  String? proxyHost,
  int? proxyPort,
) async {
  // We don't route image fetches through a proxy; if one is configured we
  // can't validate the eventual peer, so refuse rather than connect blind.
  if (proxyHost != null) {
    throw const SocketException('Image fetch via proxy is not supported');
  }
  final addresses = await InternetAddress.lookup(url.host);
  if (addresses.isEmpty) {
    throw const SocketException('Could not resolve host');
  }
  for (final addr in addresses) {
    if (_isPrivateAddress(addr)) {
      throw SocketException(
        'Blocked connection to private address',
        address: addr,
      );
    }
  }
  // Connect to the exact validated address — no second DNS resolution.
  return Socket.startConnect(addresses.first, url.port);
}

/// Returns `true` if the first 256 bytes of [data] look like an SVG/XML file.
bool _looksLikeSvg(Uint8List data) {
  final probe = data.length > 256 ? data.sublist(0, 256) : data;
  // Decode as Latin-1 (byte-stable), trim BOM / leading whitespace.
  final text = String.fromCharCodes(probe).trimLeft();
  return text.startsWith('<?xml') || text.startsWith('<svg');
}

/// Fetches a remote image with shared importer guardrails.
///
/// Returns `null` for all validation, network, timeout, and size failures.
Future<Uint8List?> fetchRemoteImageBytes(
  String url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
  int maxBytes = 10 * 1024 * 1024,
  int maxAttempts = 3,
  Duration initialRetryDelay = const Duration(milliseconds: 500),
  Duration maxRetryDelay = const Duration(seconds: 4),
}) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  // Reject data: URIs immediately.
  if (trimmed.toLowerCase().startsWith('data:')) return null;

  final Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } catch (_) {
    return null;
  }

  // Require HTTPS only.
  if (uri.scheme != 'https') return null;

  // Validate host before making any network call.
  final host = uri.host;
  if (host.isEmpty) return null;
  if (await _isPrivateHost(host)) return null;

  final owned = client == null;
  final effective = client ?? _buildPinnedClient();
  final attempts = maxAttempts < 1 ? 1 : maxAttempts;

  try {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final result = await _fetchRemoteImageBytesOnce(
          uri,
          client: effective,
          timeout: timeout,
          maxBytes: maxBytes,
        );
        if (result.bytes != null) return result.bytes;
        if (!result.retryable || attempt == attempts - 1) return null;
      } on TimeoutException {
        if (attempt == attempts - 1) return null;
      } catch (_) {
        if (attempt == attempts - 1) return null;
      }

      final delay = _retryDelay(
        attempt,
        initialRetryDelay: initialRetryDelay,
        maxRetryDelay: maxRetryDelay,
      );
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }

    return null;
  } finally {
    if (owned) {
      effective.close();
    }
  }
}

Future<({Uint8List? bytes, bool retryable})> _fetchRemoteImageBytesOnce(
  Uri uri, {
  required http.Client client,
  required Duration timeout,
  required int maxBytes,
}) async {
  // Manual redirect loop — up to 3 hops, re-validating each hop.
  const maxRedirects = 3;
  var currentUri = uri;

  for (var hop = 0; hop <= maxRedirects; hop++) {
    final request = http.Request('GET', currentUri)
      ..followRedirects = false;
    final response = await client.send(request).timeout(timeout);

    final status = response.statusCode;

    // Handle redirects.
    if (status >= 300 && status < 400) {
      if (hop == maxRedirects) {
        // Too many redirects.
        return (bytes: null, retryable: false);
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        return (bytes: null, retryable: false);
      }

      // Cancel response body to avoid resource leaks.
      response.stream.drain<void>().ignore();

      final Uri nextUri;
      try {
        // Location may be relative — resolve against current URI.
        nextUri = currentUri.resolve(location);
      } catch (_) {
        return (bytes: null, retryable: false);
      }

      // Validate redirect target: HTTPS only, no private hosts.
      if (nextUri.scheme != 'https') {
        return (bytes: null, retryable: false);
      }
      final nextHost = nextUri.host;
      if (nextHost.isEmpty || await _isPrivateHost(nextHost)) {
        return (bytes: null, retryable: false);
      }

      currentUri = nextUri;
      continue;
    }

    if (status != 200) {
      return (bytes: null, retryable: _isTransientStatus(status));
    }

    // ── 200 OK — validate content-type ──────────────────────────────────────
    final contentType = response.headers['content-type'] ?? '';
    final mimeType =
        contentType.toLowerCase().split(';').first.trim();
    if (!_allowedMimeTypes.contains(mimeType)) {
      response.stream.drain<void>().ignore();
      return (bytes: null, retryable: false);
    }

    final contentLength =
        response.contentLength ??
        int.tryParse(response.headers['content-length'] ?? '');
    if (contentLength != null && contentLength > maxBytes) {
      response.stream.drain<void>().ignore();
      return (bytes: null, retryable: false);
    }

    // ── Stream body ──────────────────────────────────────────────────────────
    final chunks = <List<int>>[];
    var total = 0;
    var svgChecked = false;

    await for (final chunk in response.stream.timeout(timeout)) {
      total += chunk.length;
      if (total > maxBytes) return (bytes: null, retryable: false);
      chunks.add(chunk);

      // SVG magic-byte check on the first chunk that gives us ≥1 byte.
      if (!svgChecked && total >= 1) {
        svgChecked = true;
        // Assemble probe bytes (up to 256) from collected chunks so far.
        var probeLen = 0;
        for (final c in chunks) {
          probeLen += c.length;
          if (probeLen >= 256) break;
        }
        probeLen = probeLen.clamp(0, 256);
        final probe = Uint8List(probeLen);
        var off = 0;
        for (final c in chunks) {
          final take = (probeLen - off).clamp(0, c.length);
          probe.setRange(off, off + take, c);
          off += take;
          if (off >= probeLen) break;
        }
        if (_looksLikeSvg(probe)) return (bytes: null, retryable: false);
      }
    }

    if (total == 0) return (bytes: null, retryable: false);

    final bytes = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return (bytes: bytes, retryable: false);
  }

  // Should be unreachable.
  return (bytes: null, retryable: false);
}

bool _isTransientStatus(int statusCode) =>
    statusCode == 408 || statusCode == 429 || statusCode >= 500;

Duration _retryDelay(
  int completedFailures, {
  required Duration initialRetryDelay,
  required Duration maxRetryDelay,
}) {
  var delayMicros = initialRetryDelay.inMicroseconds;
  final maxMicros = maxRetryDelay.inMicroseconds;

  for (var i = 0; i < completedFailures; i++) {
    delayMicros *= 2;
    if (delayMicros >= maxMicros) {
      return maxRetryDelay;
    }
  }

  if (delayMicros > maxMicros) return maxRetryDelay;
  return Duration(microseconds: delayMicros);
}
