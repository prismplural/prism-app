import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';

void main() {
  test('app registry includes hide total member count preference', () {
    expect(
      appPreferenceRegistry.definitions,
      contains(hideTotalMemberCountPreference),
    );
    expect(
      hideTotalMemberCountPreference.key,
      'privacy.hide_total_member_count',
    );
    expect(hideTotalMemberCountPreference.scope, PreferenceScope.appSynced);
    expect(hideTotalMemberCountPreference.defaultValue, isFalse);
  });

  test('accessibility preferences are current synced app preferences', () {
    for (final definition in [
      dimBackgroundBehindSheetsPreference,
      forceCenteredSheetsPreference,
    ]) {
      expect(appPreferenceRegistry.definitions, contains(definition));
      expect(definition.scope, PreferenceScope.appSynced);
      expect(definition.defaultValue, isFalse);
      expect(definition.introducedInAppVersion, '0.12.0');
      expect(
        definition.introducedInSchemaVersion,
        AppDatabase.currentSchemaVersion,
      );
    }
  });
}
