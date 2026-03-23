import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/sleep_session.dart' as domain;

class SleepSessionMapper {
  SleepSessionMapper._();

  static domain.SleepSession toDomain(SleepSession row) {
    return domain.SleepSession(
      id: row.id,
      startTime: row.startTime,
      endTime: row.endTime,
      // Quality is stored as int index. Safe lookup with fallback.
      quality: domain.SleepQuality.values.firstWhere(
        (e) => e.index == row.quality,
        orElse: () => domain.SleepQuality.unknown,
      ),
      notes: row.notes,
      isHealthKitImport: row.isHealthKitImport,
    );
  }

  static SleepSessionsCompanion toCompanion(
      domain.SleepSession model) {
    return SleepSessionsCompanion(
      id: Value(model.id),
      startTime: Value(model.startTime),
      endTime: Value(model.endTime),
      quality: Value(model.quality.index),
      notes: Value(model.notes),
      isHealthKitImport: Value(model.isHealthKitImport),
    );
  }
}
