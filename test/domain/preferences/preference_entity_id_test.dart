import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/preferences/preference_entity_id.dart';

void main() {
  test('app preference id is the canonical key', () {
    expect(
      PreferenceEntityId.app('appearance.sidebar_density'),
      'appearance.sidebar_density',
    );
  });

  test('member profile preference id is stable and delimiter-safe', () {
    expect(
      PreferenceEntityId.memberProfile(
        'member:one/slash',
        'profile.header.visible',
      ),
      'bWVtYmVyOm9uZS9zbGFzaA:profile.header.visible',
    );
  });

  test('rejects keys with uppercase, spaces, or colons', () {
    expect(
      () => PreferenceEntityId.app('Appearance.Mode'),
      throwsArgumentError,
    );
    expect(
      () => PreferenceEntityId.app('appearance mode'),
      throwsArgumentError,
    );
    expect(
      () => PreferenceEntityId.app('appearance:mode'),
      throwsArgumentError,
    );
  });
}
