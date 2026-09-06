import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// v0.1 transport. Filenames are hints; the envelope is authoritative.
class PluralPortBundle {
  PluralPortBundle(this.envelope, {Map<String, Uint8List>? files})
    : files = files ?? {};

  final Map<String, dynamic> envelope;
  final Map<String, Uint8List> files;
  static const maxUpload = 128 * 1024 * 1024;
  static const maxExpanded = 256 * 1024 * 1024;
  static const maxJson = 32 * 1024 * 1024;
  static const maxAsset = 32 * 1024 * 1024;
  static const maxEntries = 10000;
  static const roots = ['pluralport.json', 'openplural.json'];

  static PluralPortBundle decode(Uint8List bytes) {
    if (bytes.length > maxUpload) {
      throw const FormatException('PluralPort file exceeds 128 MiB.');
    }
    final files = <String, Uint8List>{};
    if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      // Bound the advertised central directory before allocating its entries.
      final view = ByteData.sublistView(bytes);
      var end = -1;
      for (
        var i = bytes.length - 22;
        i >= 0 && i >= bytes.length - 65557;
        i--
      ) {
        if (view.getUint32(i, Endian.little) == 0x06054b50 &&
            i + 22 + view.getUint16(i + 20, Endian.little) == bytes.length) {
          end = i;
          break;
        }
      }
      if (end < 0 ||
          view.getUint16(end + 10, Endian.little) > maxEntries ||
          view.getUint32(end + 12, Endian.little) > 16 * 1024 * 1024) {
        throw const FormatException(
          'Invalid or oversized ZIP central directory.',
        );
      }
      final directory = ZipDirectory()..read(InputMemoryStream(bytes));
      if (directory.filePosition < 0 ||
          directory.numberOfThisDisk != 0 ||
          directory.fileHeaders.length > maxEntries) {
        throw const FormatException('Invalid or oversized PluralPort ZIP.');
      }
      final names = <String>{};
      var total = 0;
      // Check every central/local header BEFORE touching compressed content.
      for (final h in directory.fileHeaders) {
        final name = h.filename;
        final normalized = safePath(name, directory: name.endsWith('/'));
        if (!names.add(normalized) ||
            h.file?.filename != name ||
            ((h.externalFileAttributes >> 16) & 0xf000) == 0xa000 ||
            (h.generalPurposeBitFlag & 1) != 0 ||
            (h.file!.flags & 1) != 0 ||
            ![0, 8].contains(h.compressionMethod) ||
            h.file!.compressionMethod !=
                (h.compressionMethod == 8
                    ? CompressionType.deflate
                    : CompressionType.none)) {
          throw const FormatException('Unsafe or unsupported ZIP entry.');
        }
        total += h.uncompressedSize;
        if (h.uncompressedSize > maxAsset || total > maxExpanded) {
          throw const FormatException(
            'PluralPort ZIP expands beyond its limit.',
          );
        }
      }
      for (final h in directory.fileHeaders) {
        if (h.filename.endsWith('/')) continue;
        final output = _BoundedOutput(h.uncompressedSize);
        final compressed = h.file!.getRawContent();
        if (h.compressionMethod == 0) {
          output.writeBytes(compressed);
        } else {
          // archive's IO decodeStream buffers its entire output until close.
          // Feed dart:io directly so declared-size limits apply while inflating.
          final decoder = io.ZLibDecoder(
            raw: true,
          ).startChunkedConversion(_InflateSink(output));
          for (var offset = 0; offset < compressed.length; offset += 1024) {
            decoder.add(
              Uint8List.sublistView(
                compressed,
                offset,
                (offset + 1024).clamp(0, compressed.length),
              ),
            );
          }
          decoder.close();
        }
        final content = output.getBytes();
        if (content.length != h.uncompressedSize ||
            getCrc32(content) != h.crc32) {
          throw const FormatException('ZIP entry failed its integrity check.');
        }
        files[h.filename] = content;
      }
      final documents = roots.where(files.containsKey).toList();
      if (documents.isEmpty) {
        throw const FormatException(
          'ZIP needs pluralport.json or openplural.json at its root.',
        );
      }
      final first = _json(files[documents.first]!);
      for (final other in documents.skip(1)) {
        JsonNormalizer.normalize(first);
        final second = _json(files[other]!);
        JsonNormalizer.normalize(second);
        if (canonicalJson(first) != canonicalJson(second)) {
          throw const FormatException(
            'PluralPort and OpenPlural JSON files disagree.',
          );
        }
      }
      return PluralPortBundle(first, files: files)..validateVersion();
    }
    return PluralPortBundle(_json(bytes))..validateVersion();
  }

  void validateVersion() {
    final current = envelope['pluralport_version'];
    final legacy = envelope['openplural_version'];
    if (current != null && legacy != null && current != legacy) {
      throw const FormatException('PluralPort version keys disagree.');
    }
    if ((current ?? legacy) != '0.1') {
      throw const FormatException(
        'Unsupported PluralPort version. Expected 0.1.',
      );
    }
    if (envelope['producer'] is! Map) {
      throw const FormatException('PluralPort producer must be an object.');
    }
  }

  /// Resolve only explicitly referenced files. Never fetch external URIs.
  Uint8List? assetBytes(Map<String, dynamic> asset) {
    final sheaf = (asset['extensions'] as Map?)?['sheaf'];
    final path =
        asset['bundle_path'] ?? (sheaf is Map ? sheaf['bundle_path'] : null);
    final sources = <Uint8List>[];
    if (path != null) {
      final data = files[safePath(path as String)];
      if (data != null) sources.add(data);
    }
    final b64 = asset['data_base64'];
    if (b64 is String) {
      if (b64.length > maxAsset * 4 ~/ 3 + 4) {
        throw const FormatException('Inline asset exceeds its limit.');
      }
      sources.add(base64Decode(b64));
    }
    final uri = asset['data_uri'];
    if (uri is String) {
      if (uri.length > maxAsset * 4 ~/ 3 + 1024) {
        throw const FormatException('Inline asset exceeds its limit.');
      }
      sources.add(Uri.parse(uri).data!.contentAsBytes());
    }
    if (sources.isEmpty) return null;
    final result = sources.first;
    final digest = sha256.convert(result).toString();
    if (result.length > maxAsset ||
        (asset['size_bytes'] != null && asset['size_bytes'] != result.length) ||
        (asset['sha256'] != null &&
            asset['sha256'].toString().toLowerCase() != digest) ||
        sources.skip(1).any((s) => sha256.convert(s).toString() != digest)) {
      throw const FormatException('Asset sources, size or hash disagree.');
    }
    return result;
  }

  Uint8List encode() {
    final archive = Archive();
    final json = Map<String, dynamic>.from(envelope)
      ..remove('openplural_version')
      ..['pluralport_version'] = '0.1';
    final content = utf8.encode(jsonEncode(json));
    if (content.length > maxJson) {
      throw const FormatException('PluralPort JSON exceeds 32 MiB.');
    }
    archive.add(ArchiveFile('pluralport.json', content.length, content));
    final readme = utf8.encode(
      'PluralPort v0.1 export from Prism.\nThis ZIP is not encrypted.\n',
    );
    archive.add(ArchiveFile('README.txt', readme.length, readme));
    var total = content.length + readme.length;
    for (final entry in files.entries) {
      final path = safePath(entry.key);
      if (roots.contains(path) || path == 'README.txt') continue;
      total += entry.value.length;
      if (entry.value.length > maxAsset ||
          total > maxExpanded ||
          archive.length >= maxEntries) {
        throw const FormatException('PluralPort bundle exceeds its limit.');
      }
      archive.add(ArchiveFile(path, entry.value.length, entry.value));
    }
    final bytes = ZipEncoder().encode(archive);
    if (bytes.length > maxUpload) {
      throw const FormatException('PluralPort ZIP exceeds 128 MiB.');
    }
    return Uint8List.fromList(bytes);
  }

  static Map<String, dynamic> _json(Uint8List bytes) {
    if (bytes.length > maxJson) {
      throw const FormatException('PluralPort JSON exceeds 32 MiB.');
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('PluralPort JSON must be an object.');
    }
    return json;
  }

  static String safePath(String name, {bool directory = false}) {
    final path = directory && name.endsWith('/')
        ? name.substring(0, name.length - 1)
        : name;
    if (path.isEmpty ||
        path.contains('\\') ||
        path.contains(':') ||
        path.codeUnits.any((c) => c < 32) ||
        path.split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
      throw const FormatException('Unsafe PluralPort bundle path.');
    }
    return path;
  }
}

String canonicalJson(Object? value) {
  Object? sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sorted(v[k])};
    }
    if (v is List) return v.map(sorted).toList();
    return v;
  }

  return jsonEncode(sorted(value));
}

class _BoundedOutput extends OutputMemoryStream {
  _BoundedOutput(this.limit);
  final int limit;
  void _check(int n) {
    if (length + n > limit) {
      throw const FormatException('ZIP entry exceeds its declared size.');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}

class JsonNormalizer {
  static void normalize(Map<String, dynamic> json) {
    PluralPortBundle(json).validateVersion();
    json['pluralport_version'] =
        json['pluralport_version'] ?? json['openplural_version'];
    json.remove('openplural_version');
  }
}

class _InflateSink implements Sink<List<int>> {
  _InflateSink(this.output);
  final _BoundedOutput output;
  @override
  void add(List<int> data) => output.writeBytes(data);
  @override
  void close() {}
}
