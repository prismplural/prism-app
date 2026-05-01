import 'dart:convert';
import 'dart:typed_data';

/// Encodes secret text into a mutable byte buffer for FFI calls.
///
/// Callers should pass the returned buffer to the FFI boundary and then call
/// [zeroBytesBestEffort] from a `finally` block once the call returns.
Uint8List secretUtf8Bytes(String value) => utf8.encoder.convert(value);

void zeroBytesBestEffort(List<int>? bytes) {
  if (bytes == null) return;
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Some platform-channel byte views are immutable. Callers copy Strings
    // into mutable buffers before FFI calls, but scrubbing must never mask the
    // operation result if a platform returns a read-only view.
  }
}
