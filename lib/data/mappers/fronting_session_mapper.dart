import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;

class FrontingSessionMapper {
  FrontingSessionMapper._();

  static domain.FrontingSession toDomain(FrontingSession row) {
    List<String> coFronterIds = [];
    if (row.coFronterIds.isNotEmpty) {
      try {
        coFronterIds =
            (jsonDecode(row.coFronterIds) as List).cast<String>();
      } catch (e) {
        ErrorReportingService.instance.report(
          'Failed to parse coFronterIds JSON in session ${row.id}: $e',
          severity: ErrorSeverity.warning,
        );
      }
    }

    return domain.FrontingSession(
      id: row.id,
      startTime: row.startTime,
      endTime: row.endTime,
      memberId: row.memberId,
      coFronterIds: coFronterIds,
      notes: row.notes,
      // Confidence is stored as int index. Safe lookup with fallback prevents
      // crashes if an enum value is ever removed or reordered.
      confidence: row.confidence != null
          ? domain.FrontConfidence.values.firstWhere(
              (e) => e.index == row.confidence!,
              orElse: () => domain.FrontConfidence.unsure,
            )
          : null,
      pluralkitUuid: row.pluralkitUuid,
    );
  }

  static FrontingSessionsCompanion toCompanion(
      domain.FrontingSession model) {
    return FrontingSessionsCompanion(
      id: Value(model.id),
      startTime: Value(model.startTime),
      endTime: Value(model.endTime),
      memberId: Value(model.memberId),
      coFronterIds: Value(jsonEncode(model.coFronterIds)),
      notes: Value(model.notes),
      confidence: Value(model.confidence?.index),
      pluralkitUuid: Value(model.pluralkitUuid),
    );
  }
}
