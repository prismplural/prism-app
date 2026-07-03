import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/preferences/member_name_presentation.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';

void main() {
  test('app registry includes hide member counts preference', () {
    expect(
      appPreferenceRegistry.definitions,
      contains(hideMemberCountsPreference),
    );
    expect(hideMemberCountsPreference.key, 'privacy.hide_total_member_count');
    expect(hideMemberCountsPreference.scope, PreferenceScope.appSynced);
    expect(hideMemberCountsPreference.defaultValue, isFalse);
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
      // These prefs shipped with schema v31 (0.12.0). Pin to that fixed
      // version rather than currentSchemaVersion — introducedInSchemaVersion
      // is historical, so coupling it to "current" breaks on every later bump.
      expect(definition.introducedInSchemaVersion, 31);
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
    expect(typographyLetterSpacingPreference.codec.isValid(-1.0), isTrue);
    expect(typographyLetterSpacingPreference.codec.isValid(1.0), isTrue);
    expect(typographyLetterSpacingPreference.codec.isValid(-1.1), isFalse);
    expect(typographyLetterSpacingPreference.codec.isValid(1.1), isFalse);
    expect(typographyLetterSpacingPreference.introducedInAppVersion, '0.12.1');
    // Shipped at schema v31; pin to the historical version so a later schema
    // bump doesn't break this (see the accessibility-prefs test above).
    expect(typographyLetterSpacingPreference.introducedInSchemaVersion, 31);
  });

  test('member name presentation preference is a synced app preference', () {
    expect(
      appPreferenceRegistry.definitions,
      contains(memberNamePresentationPreference),
    );
    expect(memberNamePresentationPreference.key, 'members.name_presentation');
    expect(memberNamePresentationPreference.scope, PreferenceScope.appSynced);
    expect(
      MemberNamePresentation.tryParse(
        memberNamePresentationPreference.defaultValue,
      ),
      MemberNamePresentation.fullName,
    );
    for (final presentation in MemberNamePresentation.values) {
      expect(
        memberNamePresentationPreference.codec.isValid(
          presentation.storageValue,
        ),
        isTrue,
        reason: '${presentation.storageValue} should be an allowed value',
      );
    }
    expect(memberNamePresentationPreference.codec.isValid('unknown'), isFalse);
    expect(memberNamePresentationPreference.introducedInAppVersion, '0.14.0');
    expect(memberNamePresentationPreference.introducedInSchemaVersion, 39);
  });

  test('system terms preference is a synced app preference', () {
    expect(appPreferenceRegistry.definitions, contains(systemTermsPreference));
    expect(systemTermsPreference.key, 'terminology.system_terms');
    expect(systemTermsPreference.scope, PreferenceScope.appSynced);
    expect(systemTermsPreference.defaultValue, SystemTerms.unset);
    expect(
      systemTermsPreference.codec.isValid(
        const SystemTerms.custom(singular: 'collective', plural: 'collectives'),
      ),
      isTrue,
    );
    expect(
      systemTermsPreference.codec.isValid(
        const SystemTerms.preset(SystemTermPreset.collective),
      ),
      isTrue,
    );
    expect(
      systemTermsPreference.codec.isValid(
        const SystemTerms(singular: 'collective'),
      ),
      isFalse,
    );
    expect(systemTermsPreference.introducedInAppVersion, '0.14.0');
    expect(systemTermsPreference.introducedInSchemaVersion, 40);
  });
}
