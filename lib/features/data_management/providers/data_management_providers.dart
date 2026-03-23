import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/data_management/services/data_export_service.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';

final dataExportServiceProvider = Provider<DataExportService>((ref) {
  return DataExportService(
    memberRepository: ref.watch(memberRepositoryProvider),
    frontingSessionRepository: ref.watch(frontingSessionRepositoryProvider),
    conversationRepository: ref.watch(conversationRepositoryProvider),
    chatMessageRepository: ref.watch(chatMessageRepositoryProvider),
    pollRepository: ref.watch(pollRepositoryProvider),
    sleepSessionRepository: ref.watch(sleepSessionRepositoryProvider),
    systemSettingsRepository: ref.watch(systemSettingsRepositoryProvider),
    habitRepository: ref.watch(habitRepositoryProvider),
    pluralKitSyncDao: ref.watch(pluralKitSyncDaoProvider),
  );
});

final dataImportServiceProvider = Provider<DataImportService>((ref) {
  return DataImportService(
    db: ref.watch(databaseProvider),
    memberRepository: ref.watch(memberRepositoryProvider),
    frontingSessionRepository: ref.watch(frontingSessionRepositoryProvider),
    conversationRepository: ref.watch(conversationRepositoryProvider),
    chatMessageRepository: ref.watch(chatMessageRepositoryProvider),
    pollRepository: ref.watch(pollRepositoryProvider),
    sleepSessionRepository: ref.watch(sleepSessionRepositoryProvider),
    systemSettingsRepository: ref.watch(systemSettingsRepositoryProvider),
    habitRepository: ref.watch(habitRepositoryProvider),
    pluralKitSyncDao: ref.watch(pluralKitSyncDaoProvider),
  );
});
