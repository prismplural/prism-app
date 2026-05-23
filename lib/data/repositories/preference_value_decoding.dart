import 'dart:convert';

import 'package:prism_plurality/domain/preferences/preference_definition.dart';

T decodePreferenceValue<T>({
  required PreferenceDefinition<T> definition,
  required String valueType,
  required String? valueJson,
  required bool isDeleted,
}) {
  if (isDeleted ||
      valueType != definition.codec.valueType ||
      valueJson == null) {
    return definition.defaultValue;
  }

  try {
    return definition.codec.decode(jsonDecode(valueJson));
  } catch (_) {
    return definition.defaultValue;
  }
}

String encodePreferenceValue<T>(PreferenceDefinition<T> definition, T value) {
  definition.validate(value);
  return jsonEncode(definition.codec.encode(value));
}
