import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';

void main() {
  test('storageValues matches the registry codec allow-list', () {
    expect(
      composerDefaultMemberPreference.codec.isValid('latest_fronter'),
      isTrue,
    );
    for (final v in ComposerDefaultMember.values) {
      expect(
        composerDefaultMemberPreference.codec.isValid(v.storageValue),
        isTrue,
        reason: '${v.storageValue} should be an allowed value',
      );
    }
  });

  test('registry default decodes to latestFronter', () {
    expect(
      ComposerDefaultMember.fromStorage(
        composerDefaultMemberPreference.defaultValue,
      ),
      ComposerDefaultMember.latestFronter,
    );
  });

  test('fromStorage falls back to default for unknown/null values', () {
    expect(ComposerDefaultMember.fromStorage(null),
        ComposerDefaultMember.defaultValue);
    expect(ComposerDefaultMember.fromStorage('bogus'),
        ComposerDefaultMember.defaultValue);
  });

  test('round-trips every enum value through its storage string', () {
    for (final v in ComposerDefaultMember.values) {
      expect(ComposerDefaultMember.fromStorage(v.storageValue), v);
    }
  });

  test('registry includes the composer default preference', () {
    expect(
      appPreferenceRegistry.definitions,
      contains(composerDefaultMemberPreference),
    );
  });
}
