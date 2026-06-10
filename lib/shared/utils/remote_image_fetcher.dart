import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io'
    show
        ConnectionTask,
        HttpClient,
        InternetAddress,
        InternetAddressType,
        SecureSocket,
        Socket,
        SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:prism_plurality/core/services/build_info.dart';

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

/// Why a remote image fetch did not yield bytes. Callers map this to a
/// user-facing message so "that's a web page" ([notAnImage]) and "the host is
/// unreachable" ([unreachable]) read as the different problems they are.
enum RemoteImageFetchError {
  /// Empty / unparseable input, or a non-`https` scheme that could not be
  /// normalized (e.g. an explicit `http://` or `ftp://` URL).
  invalidUrl,

  /// Host is private/loopback/link-local, or refused for SSRF safety.
  blockedHost,

  /// The server responded, but the body is not a supported image — most often
  /// because the URL points at a web page (Pinterest pin, Tumblr post, an image
  /// host's landing page) rather than a direct image link.
  notAnImage,

  /// The image exceeds the size cap.
  tooLarge,

  /// Network failure: DNS, connect, TLS, timeout, redirect loop, or non-image
  /// HTTP error (404/410/etc.).
  unreachable,
}

/// Normalizes a user-typed image URL so a bare host like `i.postimg.cc/x.png`
/// (no scheme) is treated as `https://i.postimg.cc/x.png` instead of being
/// rejected outright. Mobile users routinely paste without the scheme.
///
/// Only prepends `https://` when no scheme is present. An explicit scheme
/// (including `http://`) is left untouched so the caller's HTTPS-only policy can
/// still reject it deliberately. Returns the trimmed input unchanged when it is
/// empty or already has a scheme.
String normalizeImageUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  // RFC 3986 scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed)) return trimmed;
  // Protocol-relative `//host/path` → https.
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  return 'https://$trimmed';
}

/// Returns `true` if [data]'s leading bytes match a supported raster image
/// magic number (JPEG, PNG, GIF, WebP, HEIC/HEIF). Used as a fallback when a
/// host serves a valid image under a wrong/absent `Content-Type` such as
/// `application/octet-stream` or the non-standard `image/jpg`.
bool _looksLikeRasterImage(Uint8List d) {
  final n = d.length;
  // JPEG: FF D8 FF
  if (n >= 3 && d[0] == 0xFF && d[1] == 0xD8 && d[2] == 0xFF) return true;
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (n >= 8 &&
      d[0] == 0x89 &&
      d[1] == 0x50 &&
      d[2] == 0x4E &&
      d[3] == 0x47 &&
      d[4] == 0x0D &&
      d[5] == 0x0A &&
      d[6] == 0x1A &&
      d[7] == 0x0A) {
    return true;
  }
  // GIF: "GIF8"
  if (n >= 4 &&
      d[0] == 0x47 &&
      d[1] == 0x49 &&
      d[2] == 0x46 &&
      d[3] == 0x38) {
    return true;
  }
  // WebP: "RIFF" .... "WEBP"
  if (n >= 12 &&
      d[0] == 0x52 &&
      d[1] == 0x49 &&
      d[2] == 0x46 &&
      d[3] == 0x46 &&
      d[8] == 0x57 &&
      d[9] == 0x45 &&
      d[10] == 0x42 &&
      d[11] == 0x50) {
    return true;
  }
  // HEIC/HEIF (ISO-BMFF): bytes 4..7 == "ftyp", brand at 8..11 in a known set.
  if (n >= 12 &&
      d[4] == 0x66 &&
      d[5] == 0x74 &&
      d[6] == 0x79 &&
      d[7] == 0x70) {
    const heifBrands = {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'mif1',
      'msf1',
      'heif',
    };
    final brand = String.fromCharCodes(d.sublist(8, 12));
    if (heifBrands.contains(brand)) return true;
  }
  return false;
}

/// Returns `true` if the host should be blocked (private/loopback/link-local).
///
/// Rejects:
///   - Well-known private hostnames (localhost, *.local, metadata.internal)
///   - IPv4 literal addresses in private/loopback/APIPA ranges
///   - IPv6 loopback, link-local, ULA, and IPv4-mapped private addresses
///   - DNS names that resolve exclusively to private addresses
Future<bool> _isPrivateHost(String host) async {
  // Cheap, DNS-free checks first (well-known names + IP literals).
  if (isPrivateHostLiteral(host)) return true;

  // If it parsed as an IP literal, isPrivateHostLiteral already decided.
  if (InternetAddress.tryParse(host) != null) return false;

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

/// Synchronous, DNS-free SSRF host check for the **shape** of a host string.
///
/// Returns `true` when [host] is a well-known private hostname or an IP literal
/// in a private/loopback/link-local/CGNAT/metadata range. Unlike
/// [_isPrivateHost] this does **not** resolve DNS names — a public-looking DNS
/// name returns `false` here (callers that need full protection must pin the
/// connection / re-validate the resolved address, e.g. [_buildPinnedClient]).
///
/// Use this to validate relay-supplied URLs (e.g. the GIF `api_base_url`) at
/// config time, where async DNS resolution is undesirable and the goal is to
/// reject the obvious SSRF targets before the URL is ever used.
bool isPrivateHostLiteral(String host) {
  final lc = host.toLowerCase();
  if (lc.isEmpty) return true;

  // Reject well-known private / metadata hostnames immediately.
  if (lc == 'localhost' ||
      lc == 'metadata.internal' ||
      lc == 'metadata.google.internal' ||
      lc.endsWith('.local') ||
      lc.endsWith('.localhost') ||
      lc.endsWith('.internal')) {
    return true;
  }

  // IP literal? Classify it. (Strip IPv6 brackets if present.)
  final stripped = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
  final parsed = InternetAddress.tryParse(stripped);
  if (parsed != null) return _isPrivateAddress(parsed);

  // `InternetAddress.tryParse` only accepts canonical dotted-quad / IPv6 forms.
  // Alternate IPv4 encodings (decimal `2130706433`, hex `0x7f000001`,
  // abbreviated `127.1` / `10.1`) parse as NULL above but are still routable to
  // the same private addresses by the OS resolver — a classic SSRF bypass.
  // Normalize them to octets and reject the private/loopback/metadata ranges.
  final octets = _decodeAlternateIpv4(stripped);
  if (octets != null) return _isPrivateV4(octets[0], octets[1]);

  return false;
}

/// Decodes the non-canonical IPv4 literal encodings that
/// [InternetAddress.tryParse] rejects, returning the four octets
/// (most-significant first) or `null` if [host] is not one of these forms.
///
/// Covers:
///   * 32-bit decimal      — `2130706433`            → 127.0.0.1
///   * 32-bit hex          — `0x7f000001`            → 127.0.0.1
///   * abbreviated / mixed — `127.1`, `10.1`, `0xA.1`, `127.0.1`
///     (each part may itself be decimal or `0x`-hex; the final part fills the
///     remaining low-order octets, per inet_aton semantics).
///
/// Octal (`0`-prefixed) parts are intentionally *not* interpreted as octal:
/// we parse a leading-zero decimal part as plain decimal, which is the
/// conservative choice (it can only make an address look *more* like a public
/// one, and the canonical-literal path above already covers the real octal
/// resolution risk via the OS). Returns `null` for anything ambiguous so the
/// caller treats it as a (resolvable) DNS name and the async/pinned path
/// re-validates the resolved address.
List<int>? _decodeAlternateIpv4(String host) {
  if (host.isEmpty) return null;

  final parts = host.split('.');
  if (parts.isEmpty || parts.length > 4) return null;

  // Parse each part as a decimal or `0x`-hex unsigned integer.
  final values = <int>[];
  for (final part in parts) {
    final value = _parseIpPart(part);
    if (value == null) return null;
    values.add(value);
  }

  // inet_aton allows the final part to span the remaining octets. With N parts,
  // parts[0..N-2] are single octets (0..255) and the last part fills the
  // remaining (4 - (N-1)) octets.
  final leadCount = values.length - 1;
  for (var i = 0; i < leadCount; i++) {
    if (values[i] > 0xFF) return null;
  }

  final remainingOctets = 4 - leadCount;
  final tail = values.last;
  final maxTail = remainingOctets == 4
      ? 0xFFFFFFFF
      : (1 << (8 * remainingOctets)) - 1;
  if (tail > maxTail) return null;

  final octets = <int>[];
  for (var i = 0; i < leadCount; i++) {
    octets.add(values[i]);
  }
  for (var shift = remainingOctets - 1; shift >= 0; shift--) {
    octets.add((tail >> (8 * shift)) & 0xFF);
  }

  // A single canonical dotted-quad would already have been caught by
  // InternetAddress.tryParse; reaching here with 4 plain-decimal parts means
  // one was out of range — not a valid address, treat as not-an-IP.
  if (octets.length != 4) return null;
  return octets;
}

/// Parses one part of an IPv4 literal as a non-negative decimal or `0x`-hex
/// integer. Returns `null` for empty, signed, or non-numeric parts.
int? _parseIpPart(String part) {
  if (part.isEmpty) return null;
  if (part.startsWith('0x') || part.startsWith('0X')) {
    final hex = part.substring(2);
    if (hex.isEmpty) return null;
    return int.tryParse(hex, radix: 16);
  }
  // Plain decimal. Reject anything with non-digit characters.
  for (final code in part.codeUnits) {
    if (code < 0x30 || code > 0x39) return null;
  }
  return int.tryParse(part);
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

    final firstTwelveZeroExceptTail =
        raw[4] == 0 &&
        raw[5] == 0 &&
        raw[6] == 0 &&
        raw[7] == 0 &&
        raw[8] == 0 &&
        raw[9] == 0;

    // IPv4-mapped: ::ffff:0:0/96 — validate the embedded IPv4 (bytes 12–15).
    final isV4Mapped =
        raw[0] == 0 &&
        raw[1] == 0 &&
        raw[2] == 0 &&
        raw[3] == 0 &&
        firstTwelveZeroExceptTail &&
        raw[10] == 0xFF &&
        raw[11] == 0xFF;
    if (isV4Mapped) return _isPrivateV4(raw[12], raw[13]);

    // NAT64 well-known prefix 64:ff9b::/96 — translates to arbitrary IPv4,
    // including internal hosts; block the whole range.
    final isNat64 =
        raw[0] == 0x00 &&
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

  // Connect to a validated address — no second DNS resolution, so the bytes we
  // validated are the bytes we connect to. Try every resolved address in turn,
  // not just the first: the default HttpClient does this ("happy eyeballs"), and
  // without it a host whose first record is unreachable on this network — most
  // commonly an AAAA (IPv6) record on an IPv4-only mobile connection — fails
  // every fetch even though another resolved address would connect fine.
  var cancelled = false;
  ConnectionTask<Socket>? inFlight;

  Future<Socket> connect() async {
    Object? lastError;
    for (final addr in addresses) {
      if (cancelled) throw const SocketException('Image fetch cancelled');
      Socket? raw;
      try {
        final task = await Socket.startConnect(addr, url.port);
        inFlight = task;
        raw = await task.socket;
        // A custom connectionFactory means Dart will not perform the HTTPS
        // upgrade for us; wrap the raw socket with TLS while preserving the
        // original hostname for SNI and certificate validation.
        if (url.scheme != 'https') return raw;
        return await SecureSocket.secure(raw, host: url.host);
      } catch (e) {
        lastError = e;
        inFlight = null;
        // If the TCP socket opened but the TLS upgrade (or anything after)
        // threw, close it before moving on — otherwise a host with several A
        // records that fail TLS leaks one FD per failed address.
        raw?.destroy();
      }
    }
    throw SocketException(
      'Could not connect to ${url.host} (tried ${addresses.length} '
      'address(es)): $lastError',
    );
  }

  return ConnectionTask.fromSocket(connect(), () {
    cancelled = true;
    inFlight?.cancel();
  });
}

/// Test hook for verifying the custom connection factory keeps HTTPS as TLS.
ConnectionTask<Socket> upgradePinnedConnectionForTesting(
  ConnectionTask<Socket> rawTask,
  Uri url,
) => _upgradePinnedConnectionForUri(rawTask, url);

ConnectionTask<Socket> _upgradePinnedConnectionForUri(
  ConnectionTask<Socket> rawTask,
  Uri url,
) {
  if (url.scheme != 'https') return rawTask;

  return ConnectionTask.fromSocket(
    rawTask.socket.then(
      (socket) => SecureSocket.secure(socket, host: url.host),
    ),
    rawTask.cancel,
  );
}

/// Returns `true` if [data] starts like markup (SVG / XML / HTML) rather than a
/// raster image. No supported image format begins with `<`, so a leading angle
/// bracket — after an optional UTF-8 BOM and ASCII whitespace — means the bytes
/// are not an image we should accept. Catches `<?xml`, `<svg`, `<!DOCTYPE…`,
/// `<!-- …`, and `<html`, including the BOM-prefixed variants that a naive
/// `String.trimLeft()` would miss (U+FEFF is not Unicode whitespace).
bool _looksLikeMarkup(Uint8List data) {
  var i = 0;
  if (data.length >= 3 &&
      data[0] == 0xEF &&
      data[1] == 0xBB &&
      data[2] == 0xBF) {
    i = 3; // UTF-8 BOM
  }
  while (i < data.length) {
    final b = data[i];
    // ASCII whitespace: space, tab, LF, CR, FF, VT.
    final isWs = b == 0x20 ||
        b == 0x09 ||
        b == 0x0A ||
        b == 0x0D ||
        b == 0x0C ||
        b == 0x0B;
    if (!isWs) break;
    i++;
  }
  return i < data.length && data[i] == 0x3C; // '<'
}

/// Fetches a remote image with shared importer guardrails.
///
/// Returns `null` for all validation, network, timeout, and size failures. For
/// the failure *reason* (to drive a useful error message), use
/// [fetchRemoteImageResult].
Future<Uint8List?> fetchRemoteImageBytes(
  String url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
  int maxBytes = 10 * 1024 * 1024,
  int maxAttempts = 3,
  Duration initialRetryDelay = const Duration(milliseconds: 500),
  Duration maxRetryDelay = const Duration(seconds: 4),
}) async {
  final result = await fetchRemoteImageResult(
    url,
    client: client,
    timeout: timeout,
    maxBytes: maxBytes,
    maxAttempts: maxAttempts,
    initialRetryDelay: initialRetryDelay,
    maxRetryDelay: maxRetryDelay,
  );
  return result.bytes;
}

/// Like [fetchRemoteImageBytes] but reports *why* a fetch failed via
/// [RemoteImageFetchError], so UIs can tell "that's a web page, not an image"
/// apart from "the host is unreachable".
///
/// A scheme-less URL (`i.postimg.cc/x.png`) is normalized to `https://` first;
/// only an explicit non-`https` scheme is rejected as [invalidUrl].
///
/// When [followLinkPreview] is true and the URL turns out to be a web page
/// rather than a direct image, the page's `og:image` / `twitter:image`
/// link-preview metadata is resolved and fetched instead — so pasting the
/// Tumblr post or Pinterest pin you were *looking at* works, not just the raw
/// CDN link. The resolved image goes through the exact same guardrails (HTTPS,
/// private-host rejection, size cap, magic-byte sniff); only one preview hop is
/// attempted (a preview that itself resolves to a page is not chased).
///
/// It defaults to **false** — the rescue is for interactive paste, where one
/// extra page fetch + parse is worth it. Bulk callers (avatar / bio import) must
/// not pay that cost (or take on the adversarial-HTML parse surface) for every
/// failed URL, so they keep the default.
Future<({Uint8List? bytes, RemoteImageFetchError? error})> fetchRemoteImageResult(
  String url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
  int maxBytes = 10 * 1024 * 1024,
  int maxAttempts = 3,
  Duration initialRetryDelay = const Duration(milliseconds: 500),
  Duration maxRetryDelay = const Duration(seconds: 4),
  bool followLinkPreview = false,
}) async {
  final validated = await _validateImageUri(url);
  if (validated.uri == null) {
    return (bytes: null, error: validated.error);
  }
  final uri = validated.uri!;

  final owned = client == null;
  final effective = client ?? _buildPinnedClient();
  final attempts = maxAttempts < 1 ? 1 : maxAttempts;

  try {
    final direct = await _runImageAttempts(
      uri,
      client: effective,
      timeout: timeout,
      maxBytes: maxBytes,
      attempts: attempts,
      initialRetryDelay: initialRetryDelay,
      maxRetryDelay: maxRetryDelay,
    );
    if (direct.bytes != null) return direct;

    // Link-preview fallback: the URL was a web page, not a direct image. Pull
    // its og:image and fetch THAT through the same guards (one hop only).
    if (followLinkPreview &&
        direct.error == RemoteImageFetchError.notAnImage) {
      final previewUri = await _resolveLinkPreviewImage(
        uri,
        client: effective,
        timeout: timeout,
      );
      if (previewUri != null) {
        _log('following og:image "${previewUri.host}" from page '
            '"${uri.host}"');
        final viaPreview = await _runImageAttempts(
          previewUri,
          client: effective,
          timeout: timeout,
          maxBytes: maxBytes,
          attempts: attempts,
          initialRetryDelay: initialRetryDelay,
          maxRetryDelay: maxRetryDelay,
        );
        if (viaPreview.bytes != null) return viaPreview;
      }
    }

    return direct;
  } finally {
    if (owned) {
      effective.close();
    }
  }
}

/// Parses, normalizes, and SSRF-validates [url] into a fetchable HTTPS [Uri].
/// On success returns `(uri: …, error: null)`; on rejection `(uri: null,
/// error: …)` describing why.
Future<({Uri? uri, RemoteImageFetchError? error})> _validateImageUri(
  String url,
) async {
  final normalized = normalizeImageUrl(url);
  if (normalized.isEmpty || normalized.toLowerCase().startsWith('data:')) {
    return (uri: null, error: RemoteImageFetchError.invalidUrl);
  }

  final Uri uri;
  try {
    uri = Uri.parse(normalized);
  } catch (_) {
    return (uri: null, error: RemoteImageFetchError.invalidUrl);
  }

  if (uri.scheme != 'https') {
    _log('rejected non-https scheme "${uri.scheme}"');
    return (uri: null, error: RemoteImageFetchError.invalidUrl);
  }
  if (uri.host.isEmpty) {
    return (uri: null, error: RemoteImageFetchError.invalidUrl);
  }
  if (await _isPrivateHost(uri.host)) {
    _log('blocked private host "${uri.host}"');
    return (uri: null, error: RemoteImageFetchError.blockedHost);
  }
  return (uri: uri, error: null);
}

/// Runs the retry loop for a single already-validated image [uri].
Future<({Uint8List? bytes, RemoteImageFetchError? error})> _runImageAttempts(
  Uri uri, {
  required http.Client client,
  required Duration timeout,
  required int maxBytes,
  required int attempts,
  required Duration initialRetryDelay,
  required Duration maxRetryDelay,
}) async {
  // Tracks the most specific reason seen across attempts. Defaults to
  // unreachable (network-ish) until a definitive content verdict overrides it.
  var lastError = RemoteImageFetchError.unreachable;

  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      final result = await _fetchRemoteImageBytesOnce(
        uri,
        client: client,
        timeout: timeout,
        maxBytes: maxBytes,
      );
      if (result.bytes != null) return (bytes: result.bytes, error: null);
      if (result.error != null) lastError = result.error!;
      if (!result.retryable || attempt == attempts - 1) {
        return (bytes: null, error: lastError);
      }
    } on TimeoutException {
      lastError = RemoteImageFetchError.unreachable;
      if (attempt == attempts - 1) return (bytes: null, error: lastError);
    } catch (e) {
      lastError = RemoteImageFetchError.unreachable;
      _log('attempt ${attempt + 1}/$attempts for "${uri.host}" threw: $e');
      if (attempt == attempts - 1) return (bytes: null, error: lastError);
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

  return (bytes: null, error: lastError);
}

/// Resolves a web page's link-preview image to a fetchable, SSRF-validated
/// HTTPS [Uri] — `og:image`, then `twitter:image`, then `<link rel="image_src">`
/// — or null if the page can't be fetched or advertises no preview image.
///
/// Reads only published link-preview metadata (the tags that drive
/// Discord/iMessage thumbnails); it does not scrape `<img>` tags or spoof a
/// crawler user-agent.
Future<Uri?> _resolveLinkPreviewImage(
  Uri pageUri, {
  required http.Client client,
  required Duration timeout,
}) async {
  final page = await _fetchTextHead(pageUri, client: client, timeout: timeout);
  if (page == null) return null;

  final raw = _extractPreviewImageUrl(page.html);
  if (raw == null) {
    _log('no og:image/twitter:image on page "${pageUri.host}"');
    return null;
  }

  // Resolve relative / protocol-relative URLs against the final page URI.
  final Uri candidate;
  try {
    candidate = page.finalUri.resolve(raw);
  } catch (_) {
    return null;
  }

  // The preview URL is attacker-influenced (it comes from page content), so it
  // gets the exact same guards as a directly-pasted image URL.
  if (candidate.scheme != 'https' || candidate.host.isEmpty) {
    _log('og:image is not https; skipping');
    return null;
  }
  if (await _isPrivateHost(candidate.host)) {
    _log('og:image host "${candidate.host}" is private; skipping');
    return null;
  }
  return candidate;
}

/// Fetches up to [maxBytes] of [pageUri] as text, following redirects through
/// the same HTTPS-only / private-host guards as image fetches. Returns the
/// decoded text and the final (post-redirect) URI, or null on any failure.
/// Content-type is ignored — the caller only scans for `<meta>`/`<link>` tags.
Future<({String html, Uri finalUri})?> _fetchTextHead(
  Uri pageUri, {
  required http.Client client,
  required Duration timeout,
  int maxBytes = 128 * 1024,
}) async {
  const maxRedirects = 3;
  var currentUri = pageUri;
  try {
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..headers['User-Agent'] = BuildInfo.userAgent;
      final response = await client.send(request).timeout(timeout);
      final status = response.statusCode;

      if (status >= 300 && status < 400) {
        if (hop == maxRedirects) return null;
        final location = response.headers['location'];
        response.stream.drain<void>().ignore();
        if (location == null || location.isEmpty) return null;
        final Uri nextUri;
        try {
          nextUri = currentUri.resolve(location);
        } catch (_) {
          return null;
        }
        if (nextUri.scheme != 'https') return null;
        if (nextUri.host.isEmpty || await _isPrivateHost(nextUri.host)) {
          return null;
        }
        currentUri = nextUri;
        continue;
      }

      if (status != 200) {
        response.stream.drain<void>().ignore();
        return null;
      }

      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length >= maxBytes) break; // the <head> is all we need
      }
      if (bytes.isEmpty) return null;
      final slice = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
      return (html: utf8.decode(slice, allowMalformed: true), finalUri: currentUri);
    }
    return null;
  } on TimeoutException {
    return null;
  } catch (e) {
    _log('link-preview page fetch for "${pageUri.host}" failed: $e');
    return null;
  }
}

/// Pulls a preview-image URL out of an HTML document's `<head>`: prefers
/// `og:image`, then `twitter:image`, then `<link rel="image_src">`. Returns the
/// entity-decoded URL string, or null if none is present.
///
/// Runs on the UI isolate against attacker-controlled HTML, so it is bounded on
/// both axes: the scan region is capped, and each tag matcher uses a bounded
/// `{0,N}` quantifier so an unterminated `<meta` can't drive quadratic
/// backtracking across the whole body. Tags are matched on the *exact*
/// `property`/`name`/`rel` value — `contains('og:image')` would wrongly fire on
/// `og:image:width` and return a number instead of a URL.
String? _extractPreviewImageUrl(String html) {
  // Preview tags live near the top of <head>; cap what we scan.
  final headEnd = html.toLowerCase().indexOf('</head>');
  var region = headEnd >= 0 ? html.substring(0, headEnd) : html;
  const maxScan = 64 * 1024;
  if (region.length > maxScan) region = region.substring(0, maxScan);

  final metaTag = RegExp(r'<meta\b[^>]{0,4096}>', caseSensitive: false);
  final linkTag = RegExp(r'<link\b[^>]{0,4096}>', caseSensitive: false);
  final propAttr = RegExp(
    r'''(?:property|name)\s*=\s*["']([^"']{1,128})["']''',
    caseSensitive: false,
  );
  final contentAttr = RegExp(
    r'''content\s*=\s*["']([^"']{1,4096})["']''',
    caseSensitive: false,
  );

  String? twitter;
  for (final m in metaTag.allMatches(region)) {
    final tag = m.group(0)!;
    final prop = propAttr.firstMatch(tag)?.group(1)?.trim().toLowerCase();
    if (prop == null) continue;
    final isOg = prop == 'og:image' ||
        prop == 'og:image:url' ||
        prop == 'og:image:secure_url';
    final isTwitter = prop == 'twitter:image' || prop == 'twitter:image:src';
    if (!isOg && !isTwitter) continue;
    final content = contentAttr.firstMatch(tag)?.group(1)?.trim();
    if (content == null || content.isEmpty) continue;
    if (isOg) return _unescapeHtml(content); // og:image wins outright
    twitter ??= _unescapeHtml(content);
  }
  if (twitter != null) return twitter;

  final relAttr = RegExp(
    r'''rel\s*=\s*["']([^"']{1,128})["']''',
    caseSensitive: false,
  );
  final hrefAttr = RegExp(
    r'''href\s*=\s*["']([^"']{1,4096})["']''',
    caseSensitive: false,
  );
  for (final m in linkTag.allMatches(region)) {
    final tag = m.group(0)!;
    if (relAttr.firstMatch(tag)?.group(1)?.trim().toLowerCase() != 'image_src') {
      continue;
    }
    final href = hrefAttr.firstMatch(tag)?.group(1)?.trim();
    if (href != null && href.isNotEmpty) return _unescapeHtml(href);
  }
  return null;
}

/// Test hook for the link-preview metadata extractor.
@visibleForTesting
String? extractPreviewImageUrlForTesting(String html) =>
    _extractPreviewImageUrl(html);

/// Minimal HTML-entity decode for the few that appear inside URL attributes —
/// notably `&amp;` separating query parameters.
String _unescapeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#38;', '&')
    .replaceAll('&#x26;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'");

/// Debug-only diagnostics. The fetch path converts every failure to a bare
/// `null`, so without this a misbehaving host is invisible. Logs host + reason
/// only (never secrets), and only in debug builds.
void _log(String message) {
  if (kDebugMode) debugPrint('[remote_image_fetcher] $message');
}

Future<({Uint8List? bytes, bool retryable, RemoteImageFetchError? error})>
_fetchRemoteImageBytesOnce(
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
      ..followRedirects = false
      ..headers['User-Agent'] = BuildInfo.userAgent;
    final response = await client.send(request).timeout(timeout);

    final status = response.statusCode;

    // Handle redirects.
    if (status >= 300 && status < 400) {
      if (hop == maxRedirects) {
        _log('too many redirects for "${uri.host}"');
        return _miss(RemoteImageFetchError.unreachable);
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        return _miss(RemoteImageFetchError.unreachable);
      }

      // Cancel response body to avoid resource leaks.
      response.stream.drain<void>().ignore();

      final Uri nextUri;
      try {
        // Location may be relative — resolve against current URI.
        nextUri = currentUri.resolve(location);
      } catch (_) {
        return _miss(RemoteImageFetchError.unreachable);
      }

      // Validate redirect target: HTTPS only, no private hosts.
      if (nextUri.scheme != 'https') {
        _log('redirect to non-https "${nextUri.scheme}" blocked');
        return _miss(RemoteImageFetchError.unreachable);
      }
      final nextHost = nextUri.host;
      if (nextHost.isEmpty || await _isPrivateHost(nextHost)) {
        _log('redirect to private host "$nextHost" blocked');
        return _miss(RemoteImageFetchError.blockedHost);
      }

      currentUri = nextUri;
      continue;
    }

    if (status != 200) {
      _log('non-200 status $status for "${currentUri.host}"');
      return _miss(
        RemoteImageFetchError.unreachable,
        retryable: _isTransientStatus(status),
      );
    }

    // ── 200 OK — content-type as a hint, not a gate ──────────────────────────
    // A correct image type lets us trust the header and skip the magic-byte
    // gate. An unexpected type (text/html web page, but also a valid image
    // served as application/octet-stream or the non-standard image/jpg) does
    // NOT reject outright — we sniff the leading bytes and accept real images,
    // so a working direct link isn't refused over a sloppy Content-Type.
    final contentType = response.headers['content-type'] ?? '';
    final mimeType = contentType.toLowerCase().split(';').first.trim();
    final contentTypeTrusted = _allowedMimeTypes.contains(mimeType);

    final contentLength =
        response.contentLength ??
        int.tryParse(response.headers['content-length'] ?? '');
    if (contentLength != null && contentLength > maxBytes) {
      response.stream.drain<void>().ignore();
      _log('declared length $contentLength exceeds $maxBytes for '
          '"${currentUri.host}"');
      return _miss(RemoteImageFetchError.tooLarge);
    }

    // ── Stream body ──────────────────────────────────────────────────────────
    final chunks = <List<int>>[];
    var total = 0;
    var probeChecked = false;

    await for (final chunk in response.stream.timeout(timeout)) {
      total += chunk.length;
      if (total > maxBytes) {
        _log('streamed bytes exceeded $maxBytes for "${currentUri.host}"');
        return _miss(RemoteImageFetchError.tooLarge);
      }
      chunks.add(chunk);

      if (!probeChecked && total >= 1) {
        probeChecked = true;
        final probe = _assembleProbe(chunks);
        // Reject SVG/XML/HTML even under a trusted image/* type.
        if (_looksLikeMarkup(probe)) {
          _log('content sniffed as markup (SVG/XML/HTML) for '
              '"${currentUri.host}"');
          return _miss(RemoteImageFetchError.notAnImage);
        }
        // Untrusted type: require the bytes to actually be a known raster image.
        if (!contentTypeTrusted && !_looksLikeRasterImage(probe)) {
          _log('content-type "$mimeType" not an image and bytes do not sniff '
              'as one for "${currentUri.host}"');
          return _miss(RemoteImageFetchError.notAnImage);
        }
      }
    }

    if (total == 0) return _miss(RemoteImageFetchError.notAnImage);

    final bytes = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return (bytes: bytes, retryable: false, error: null);
  }

  // Should be unreachable.
  return _miss(RemoteImageFetchError.unreachable);
}

/// Builds the missing-bytes record with a reason. [retryable] defaults to
/// `false` — only transient network states set it true.
({Uint8List? bytes, bool retryable, RemoteImageFetchError? error}) _miss(
  RemoteImageFetchError error, {
  bool retryable = false,
}) => (bytes: null, retryable: retryable, error: error);

/// Assembles up to the first 256 bytes from [chunks] for magic-byte probing.
Uint8List _assembleProbe(List<List<int>> chunks) {
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
  return probe;
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
