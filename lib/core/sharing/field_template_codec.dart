import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';

// Limits enforced on decode.
const kMaxTemplateCodeChars = 64 * 1024; // gzip-bomb guard (pre-gunzip)
const kMaxTemplateJsonBytes = 256 * 1024; // decompressed size cap
const kMaxTemplateEntries = 50;
const kMaxFieldNameChars = 200;
const kMaxChoiceOptions = 200;

enum FieldTemplateCodecError { unsupportedVersion, corrupt, invalid }

class FieldTemplateCodecException implements Exception {
  const FieldTemplateCodecException(this.kind, this.message);

  final FieldTemplateCodecError kind;
  final String message;

  @override
  String toString() => 'FieldTemplateCodecException(${kind.name}): $message';
}

class FieldTemplateCodec {
  const FieldTemplateCodec();

  static const _prefix = 'PF1:';

  String encode(FieldTemplate t) {
    final json = jsonEncode(t.toJson());
    final bytes = utf8.encode(json);
    final compressed = GZipCodec().encode(bytes);
    // Strip trailing padding — re-padded on decode.
    final b64 = base64Url.encode(compressed).replaceAll('=', '');
    return '$_prefix$b64';
  }

  FieldTemplate decode(String code) {
    // Version / prefix check FIRST, before any heavy work.
    if (!code.startsWith('PF1:')) {
      throw const FieldTemplateCodecException(
        FieldTemplateCodecError.unsupportedVersion,
        'Unrecognized share code format (expected PF1: prefix).',
      );
    }

    // Gzip-bomb guard: reject oversized inputs before decompressing.
    if (code.length > kMaxTemplateCodeChars) {
      throw const FieldTemplateCodecException(
        FieldTemplateCodecError.corrupt,
        'Share code exceeds maximum length.',
      );
    }

    try {
      final payload = code.substring(_prefix.length);

      // Re-pad to a multiple of 4.
      final padded = _repad(payload);
      final compressed = base64Url.decode(padded);

      // Fix 1: streaming inflate — abort once output exceeds kMaxTemplateJsonBytes
      // so a gzip bomb never materialises more than ~256 KB.
      final decompressed = _streamingInflate(compressed);

      final jsonStr = utf8.decode(decompressed);
      final dynamic raw = jsonDecode(jsonStr);

      // Validate top-level shape before casts.
      if (raw is! Map) {
        throw const FieldTemplateCodecException(
          FieldTemplateCodecError.corrupt,
          'Template JSON is not an object.',
        );
      }
      final map = raw as Map<String, dynamic>;
      if (map['v'] is! int || map['f'] is! List) {
        throw const FieldTemplateCodecException(
          FieldTemplateCodecError.corrupt,
          'Template JSON missing required fields.',
        );
      }

      // Version check after parsing (so we can read the 'v' field).
      final version = map['v'] as int;
      if (version != 1) {
        throw FieldTemplateCodecException(
          FieldTemplateCodecError.unsupportedVersion,
          'Unsupported template version: $version.',
        );
      }

      final template = FieldTemplate.fromJson(map);
      return validateAndNormalize(template);
    } on FieldTemplateCodecException {
      rethrow;
    } catch (e) {
      throw FieldTemplateCodecException(
        FieldTemplateCodecError.corrupt,
        'Failed to decode share code: $e',
      );
    }
  }

  // Fix 1: streaming inflate with a byte-counting sink.
  // Throws FieldTemplateCodecException.corrupt if the inflated output would
  // exceed kMaxTemplateJsonBytes before fully materialising the buffer.
  static Uint8List _streamingInflate(List<int> compressed) {
    final sink = _BoundedByteSink();
    final converter = ZLibDecoder().startChunkedConversion(sink);
    try {
      converter.add(compressed);
      converter.close();
    } on FieldTemplateCodecException {
      rethrow;
    } catch (e) {
      throw FieldTemplateCodecException(
        FieldTemplateCodecError.corrupt,
        'Decompression failed: $e',
      );
    }
    return sink.toBytes();
  }

  // Validate decoded template and normalize out-of-range parents; throw on
  // invalid structural problems.
  FieldTemplate validateAndNormalize(FieldTemplate t) {
    // Fix 5: version check so direct callers can't bypass the version gate.
    if (t.version != 1) {
      throw FieldTemplateCodecException(
        FieldTemplateCodecError.unsupportedVersion,
        'Unsupported template version: ${t.version}.',
      );
    }

    // Entry count limit.
    if (t.entries.length > kMaxTemplateEntries) {
      throw const FieldTemplateCodecException(
        FieldTemplateCodecError.invalid,
        'Template has too many fields (max $kMaxTemplateEntries).',
      );
    }

    // Field name length.
    for (final e in t.entries) {
      if (e.name.length > kMaxFieldNameChars) {
        throw const FieldTemplateCodecException(
          FieldTemplateCodecError.invalid,
          'A field name exceeds the maximum length.',
        );
      }
    }

    // Fix 2: a known-type entry MUST use compactConfig; rawConfigJson is for
    // unknown types only. Also reject entries that carry both slots.
    for (final e in t.entries) {
      final isKnown = customFieldTypeRegistry.lookupById(e.fieldTypeId) != null;
      if (e.compactConfig != null && e.rawConfigJson != null) {
        throw const FieldTemplateCodecException(
          FieldTemplateCodecError.invalid,
          'Entry has both compactConfig and rawConfigJson.',
        );
      }
      if (isKnown && e.rawConfigJson != null) {
        throw FieldTemplateCodecException(
          FieldTemplateCodecError.invalid,
          'Known field type "${e.fieldTypeId}" must use compactConfig, not rawConfigJson.',
        );
      }
    }

    // Choice option count.
    for (final e in t.entries) {
      final opts = e.compactConfig?['options'];
      if (opts is List && opts.length > kMaxChoiceOptions) {
        throw const FieldTemplateCodecException(
          FieldTemplateCodecError.invalid,
          'A choice field has too many options (max $kMaxChoiceOptions).',
        );
      }
    }

    // Fix 3: validate option structure for known choice configs.
    // Each option must be a JSON object with a String label and, if present,
    // a String colorHex matching ^#[0-9a-fA-F]{6}$.
    final colorHexPattern = RegExp(r'^#[0-9a-fA-F]{6}$');
    for (final e in t.entries) {
      final opts = e.compactConfig?['options'];
      if (opts is List) {
        for (final opt in opts) {
          if (opt is! Map) {
            throw const FieldTemplateCodecException(
              FieldTemplateCodecError.invalid,
              'A choice option is not an object.',
            );
          }
          final label = opt['label'];
          if (label is! String) {
            throw const FieldTemplateCodecException(
              FieldTemplateCodecError.invalid,
              'A choice option has a non-String label.',
            );
          }
          final colorHex = opt['colorHex'];
          if (colorHex != null) {
            if (colorHex is! String) {
              throw const FieldTemplateCodecException(
                FieldTemplateCodecError.invalid,
                'A choice option has a non-String colorHex.',
              );
            }
            if (!colorHexPattern.hasMatch(colorHex)) {
              throw const FieldTemplateCodecException(
                FieldTemplateCodecError.invalid,
                'Invalid colorHex value in choice option.',
              );
            }
          }
        }
      }
    }

    // Fix 4 (validateAndNormalize side): guard out-of-range datePrecision index.
    // The actual field-level guard is in toDomainFields; here we just validate
    // the wire value so untrusted input can't index-crash.
    for (final e in t.entries) {
      final dp = e.datePrecision;
      if (dp != null && (dp < 0 || dp >= DatePrecision.values.length)) {
        throw FieldTemplateCodecException(
          FieldTemplateCodecError.invalid,
          'datePrecision index $dp is out of range.',
        );
      }
    }

    // Depth-2 check: an entry that is BOTH a parent and itself a child.
    final parentIndices = <int>{};
    for (final e in t.entries) {
      if (e.parentIndex != null) parentIndices.add(e.parentIndex!);
    }
    for (var i = 0; i < t.entries.length; i++) {
      final e = t.entries[i];
      if (e.parentIndex != null && parentIndices.contains(i)) {
        throw const FieldTemplateCodecException(
          FieldTemplateCodecError.invalid,
          'Template contains depth > 1 nesting (entries may not be both parent and child).',
        );
      }
    }

    // Determine which indices are groups (for parent-must-be-group check).
    final groupIndices = <int>{};
    for (var i = 0; i < t.entries.length; i++) {
      if (t.entries[i].fieldTypeId == kGroupFieldTypeId) groupIndices.add(i);
    }

    // Normalize: out-of-range parentIndex or non-group parent → promote.
    var needsNormalization = false;
    final normalized = t.entries.map((e) {
      if (e.parentIndex == null) return e;
      final idx = e.parentIndex!;
      if (idx < 0 || idx >= t.entries.length || !groupIndices.contains(idx)) {
        needsNormalization = true;
        return FieldTemplateEntry(
          name: e.name,
          fieldTypeId: e.fieldTypeId,
          parentIndex: null,
          compactConfig: e.compactConfig,
          rawConfigJson: e.rawConfigJson,
          datePrecision: e.datePrecision,
        );
      }
      return e;
    }).toList();

    if (!needsNormalization) return t;
    return FieldTemplate(version: t.version, entries: normalized);
  }

  static String _repad(String s) {
    switch (s.length % 4) {
      case 2:
        return '$s==';
      case 3:
        return '$s=';
      default:
        return s;
    }
  }
}

// Byte-counting sink for streaming inflate. Accumulates output chunks and
// throws FieldTemplateCodecException.corrupt if the running total exceeds
// kMaxTemplateJsonBytes, so a gzip bomb never materialises more than ~256 KB.
class _BoundedByteSink implements Sink<List<int>> {
  final _chunks = <List<int>>[];
  int _total = 0;

  @override
  void add(List<int> chunk) {
    _total += chunk.length;
    if (_total > kMaxTemplateJsonBytes) {
      throw const FieldTemplateCodecException(
        FieldTemplateCodecError.corrupt,
        'Decompressed template exceeds maximum size.',
      );
    }
    _chunks.add(chunk);
  }

  @override
  void close() {}

  Uint8List toBytes() {
    final out = Uint8List(_total);
    var offset = 0;
    for (final chunk in _chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return out;
  }
}

