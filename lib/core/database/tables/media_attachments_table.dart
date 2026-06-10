import 'package:drift/drift.dart';

class MediaAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get messageId => text().withDefault(const Constant(''))();
  TextColumn get memberId => text().withDefault(const Constant(''))();
  TextColumn get tag => text().withDefault(const Constant(''))();
  TextColumn get mediaId => text().withDefault(const Constant(''))();
  TextColumn get mediaType => text().withDefault(const Constant(''))();
  TextColumn get encryptionKeyB64 => text().withDefault(const Constant(''))();
  TextColumn get contentHash => text().withDefault(const Constant(''))();
  TextColumn get plaintextHash => text().withDefault(const Constant(''))();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get width => integer().withDefault(const Constant(0))();
  IntColumn get height => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get blurhash => text().withDefault(const Constant(''))();
  TextColumn get waveformB64 => text().withDefault(const Constant(''))();
  TextColumn get thumbnailMediaId => text().withDefault(const Constant(''))();
  // Thumbnail crypto material (media thumbnails). The thumbnail reuses the
  // main blob's `encryptionKeyB64` (encrypted with a fresh nonce), so it only
  // needs its own ciphertext + plaintext hashes for the integrity-verified
  // download path. Empty when there is no thumbnail (bio/voice/library media).
  TextColumn get thumbnailContentHash =>
      text().withDefault(const Constant(''))();
  TextColumn get thumbnailPlaintextHash =>
      text().withDefault(const Constant(''))();
  TextColumn get sourceUrl => text().withDefault(const Constant(''))();
  TextColumn get previewUrl => text().withDefault(const Constant(''))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
