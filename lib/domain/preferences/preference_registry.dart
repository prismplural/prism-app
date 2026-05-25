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

/// Minimum minutes between a front log and the next fronting reminder.
/// 0 disables; longer gaps belong in the reminder interval itself.
const frontingReminderSuppressMinutesPreference = PreferenceDefinition<int>(
  key: 'fronting.reminder_suppress_minutes',
  scope: PreferenceScope.appSynced,
  defaultValue: 5,
  codec: IntPreferenceCodec(min: 0, max: 60),
  introducedInAppVersion: '0.9.5',
  introducedInSchemaVersion: 27,
);

final appPreferenceRegistry = PreferenceRegistry(const [
  hideTotalMemberCountPreference,
  frontingReminderSuppressMinutesPreference,
]);
final memberProfilePreferenceRegistry = PreferenceRegistry(const []);
