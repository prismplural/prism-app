import 'dart:convert';

final RegExp _preferenceKeyPattern = RegExp(
  r'^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)*$',
);

bool isValidPreferenceKey(String key) => _preferenceKeyPattern.hasMatch(key);

void assertValidPreferenceKey(String key) {
  if (isValidPreferenceKey(key)) return;
  throw ArgumentError.value(
    key,
    'key',
    'Preference keys must be lowercase dotted identifiers without spaces or colons.',
  );
}

final class PreferenceEntityId {
  const PreferenceEntityId._();

  static String app(String key) {
    assertValidPreferenceKey(key);
    return key;
  }

  static String memberProfile(String memberId, String key) {
    assertValidPreferenceKey(key);
    final encodedMemberId = base64Url
        .encode(utf8.encode(memberId))
        .replaceAll('=', '');
    return '$encodedMemberId:$key';
  }
}
