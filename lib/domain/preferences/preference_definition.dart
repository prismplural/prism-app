import 'package:prism_plurality/domain/preferences/preference_codec.dart';

enum PreferenceScope { appSynced, memberProfileSynced, deviceLocal }

enum PreferenceMigrationStatus { native, bridgedFromLegacy, legacyFallback }

class PreferenceValidationException implements Exception {
  const PreferenceValidationException(this.key, this.message);

  final String key;
  final String message;

  @override
  String toString() => 'PreferenceValidationException($key): $message';
}

class PreferenceCapabilityException implements Exception {
  const PreferenceCapabilityException(this.key, this.capability);

  final String key;
  final String capability;

  @override
  String toString() =>
      'PreferenceCapabilityException($key): requires $capability';
}

abstract interface class PreferenceCapabilityGate {
  bool canWrite(PreferenceDefinition<dynamic> definition);
}

final class LegacyPreferenceColumn {
  const LegacyPreferenceColumn({required this.table, required this.column});

  final String table;
  final String column;
}

final class PreferenceDefinition<T> {
  const PreferenceDefinition({
    required this.key,
    required this.scope,
    required this.defaultValue,
    required this.codec,
    required this.introducedInAppVersion,
    required this.introducedInSchemaVersion,
    this.minReaderCapability,
    this.legacyColumn,
    this.migrationStatus = PreferenceMigrationStatus.native,
  });

  final String key;
  final PreferenceScope scope;
  final T defaultValue;
  final PreferenceCodec<T> codec;
  final String introducedInAppVersion;
  final int introducedInSchemaVersion;
  final String? minReaderCapability;
  final LegacyPreferenceColumn? legacyColumn;
  final PreferenceMigrationStatus migrationStatus;

  void validate(T value) {
    if (!codec.isValid(value)) {
      throw PreferenceValidationException(key, 'Invalid preference value');
    }
  }
}
