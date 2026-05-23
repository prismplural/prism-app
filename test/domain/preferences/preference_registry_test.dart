import 'package:flutter_test/flutter_test.dart';
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
}
