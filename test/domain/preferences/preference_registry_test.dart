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

  test('typography letter spacing is an accessibility app preference', () {
    expect(
      appPreferenceRegistry.definitions,
      contains(typographyLetterSpacingPreference),
    );
    expect(
      typographyLetterSpacingPreference.key,
      'accessibility.typography_letter_spacing',
    );
    expect(typographyLetterSpacingPreference.scope, PreferenceScope.appSynced);
    expect(typographyLetterSpacingPreference.defaultValue, 0.0);
    expect(typographyLetterSpacingPreference.codec.isValid(-0.5), isTrue);
    expect(typographyLetterSpacingPreference.codec.isValid(2.0), isTrue);
    expect(typographyLetterSpacingPreference.codec.isValid(-0.6), isFalse);
    expect(typographyLetterSpacingPreference.codec.isValid(2.1), isFalse);
    expect(typographyLetterSpacingPreference.introducedInAppVersion, '0.12.1');
    expect(
      typographyLetterSpacingPreference.introducedInSchemaVersion,
      AppDatabase.currentSchemaVersion,
    );
  });
}
