import 'package:drift/drift.dart';

class MediaAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get messageId => text().withDefault(const Constant(''))();
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
  TextColumn get sourceUrl => text().withDefault(const Constant(''))();
  TextColumn get previewUrl => text().withDefault(const Constant(''))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
