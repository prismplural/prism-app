import 'package:prism_plurality/domain/preferences/preference_codec.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_entity_id.dart';

final class PreferenceRegistry {
  PreferenceRegistry(Iterable<PreferenceDefinition<dynamic>> definitions)
    : definitions = List.unmodifiable(definitions) {
    final seen = <String>{};
    for (final definition in definitions) {
      assertValidPreferenceKey(definition.key);
      if (!seen.add(definition.key)) {
        throw StateError('Duplicate preference key: ${definition.key}');
      }
    }
  }

  final List<PreferenceDefinition<dynamic>> definitions;
}

const hideTotalMemberCountPreference = PreferenceDefinition<bool>(
  key: 'privacy.hide_total_member_count',
  scope: PreferenceScope.appSynced,
  defaultValue: false,
  codec: BoolPreferenceCodec(),
  introducedInAppVersion: '0.9.4',
  introducedInSchemaVersion: 27,
);

final appPreferenceRegistry = PreferenceRegistry(const [
  hideTotalMemberCountPreference,
]);
final memberProfilePreferenceRegistry = PreferenceRegistry(const []);
