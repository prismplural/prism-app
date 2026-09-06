import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

/// A content-addressed, synced archive. A partial sync must never look like an
/// empty archive: re-export fails until all chunks pass the digest check.
class PluralPortPreservation with SyncRecordMixin {
  PluralPortPreservation(this.db);
  final AppDatabase db;
  @override
  ffi.PrismSyncHandle? get syncHandle => null;
  @override
  AppDatabase get syncOutboxDatabase => db;
  static const chunkSize = 48 * 1024;
  static const maxCharacters = 384 * 1024 * 1024;

  Future<void> retain(Map<String, dynamic> document) async {
    final encoded = base64Encode(utf8.encode(jsonEncode(document)));
    if (encoded.length > maxCharacters) {
      throw const FormatException(
        'PluralPort preservation archive is too large.',
      );
    }
    final digest = sha256.convert(ascii.encode(encoded)).toString();
    final count = (encoded.length / chunkSize).ceil();
    await runSyncedWrite(() async {
      for (var index = 0; index < count; index++) {
        final id = '$digest:$index';
        final row = await (db.select(
          db.pluralPortUnsupported,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row != null) continue;
        final end = ((index + 1) * chunkSize).clamp(0, encoded.length);
        final payload = encoded.substring(index * chunkSize, end);
        await db
            .into(db.pluralPortUnsupported)
            .insert(
              PluralPortUnsupportedCompanion.insert(
                id: id,
                documentId: digest,
                chunkIndex: index,
                chunkCount: count,
                payload: payload,
              ),
            );
        await syncRecordCreate(
          'plural_port_unsupported',
          id,
          fields(digest, index, count, payload),
        );
      }
    });
  }

  static Map<String, dynamic> fields(
    String documentId,
    int index,
    int count,
    String payload,
  ) {
    return {
      'document_id': documentId,
      'chunk_index': index,
      'chunk_count': count,
      'payload': payload,
      'is_deleted': false,
    };
  }

  Future<List<Map<String, dynamic>>> documents() async {
    final rows = await (db.select(
      db.pluralPortUnsupported,
    )..where((t) => t.isDeleted.equals(false))).get();
    final groups = <String, List<PluralPortUnsupportedRow>>{};
    for (final row in rows) {
      groups.putIfAbsent(row.documentId, () => []).add(row);
    }
    final documents = <Map<String, dynamic>>[];
    for (final entry in groups.entries) {
      final chunks = entry.value
        ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
      final count = chunks.first.chunkCount;
      if (count <= 0 ||
          count > (maxCharacters / chunkSize).ceil() ||
          chunks.length != count) {
        throw const FormatException(
          'Preserved PluralPort data is incomplete. Wait for sync to finish.',
        );
      }
      for (var i = 0; i < count; i++) {
        if (chunks[i].chunkIndex != i ||
            chunks[i].chunkCount != count ||
            chunks[i].payload.length > chunkSize) {
          throw const FormatException('Invalid PluralPort preservation chunk.');
        }
      }
      final payload = chunks.map((r) => r.payload).join();
      if (sha256.convert(ascii.encode(payload)).toString() != entry.key) {
        throw const FormatException(
          'Preserved PluralPort data failed its integrity check.',
        );
      }
      documents.add(
        jsonDecode(utf8.decode(base64Decode(payload))) as Map<String, dynamic>,
      );
    }
    return documents;
  }
}
