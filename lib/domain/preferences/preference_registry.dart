import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
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

/// How composer surfaces (chat, board post) pick the default "acting as"
/// member. Stored as the [ComposerDefaultMember.storageValue] string. Synced so
/// the preference follows the user across devices.
const composerDefaultMemberPreference = PreferenceDefinition<String>(
  key: 'fronting.composer_default_member',
  scope: PreferenceScope.appSynced,
  defaultValue: 'latest_fronter',
  codec: StringPreferenceCodec(
    allowedValues: {'latest_fronter', 'last_used', 'ask_each_time'},
  ),
  introducedInAppVersion: '0.10.2',
  introducedInSchemaVersion: 30,
);

/// Dims the app behind modal side sheets.
const dimBackgroundBehindSheetsPreference = PreferenceDefinition<bool>(
  key: 'accessibility.dim_background_behind_sheets',
  scope: PreferenceScope.appSynced,
  defaultValue: false,
  codec: BoolPreferenceCodec(),
  introducedInAppVersion: '0.12.0',
  introducedInSchemaVersion: 31,
);

/// Prefers centered sheets for modal surfaces on wide windows.
const forceCenteredSheetsPreference = PreferenceDefinition<bool>(
  key: 'accessibility.force_centered_sheets',
  scope: PreferenceScope.appSynced,
  defaultValue: false,
  codec: BoolPreferenceCodec(),
  introducedInAppVersion: '0.12.0',
  introducedInSchemaVersion: 31,
);

/// App-wide text letter spacing adjustment, in logical pixels.
const typographyLetterSpacingMin = -1.0;
const typographyLetterSpacingMax = 1.0;
const typographyLetterSpacingDivisions = 20;

const typographyLetterSpacingPreference = PreferenceDefinition<double>(
  key: 'accessibility.typography_letter_spacing',
  scope: PreferenceScope.appSynced,
  defaultValue: 0.0,
  codec: DoublePreferenceCodec(
    min: typographyLetterSpacingMin,
    max: typographyLetterSpacingMax,
  ),
  introducedInAppVersion: '0.12.1',
  introducedInSchemaVersion: 31,
);

/// Full vs. truncated text for labels revealed when the nav bar's More menu
/// expands. Only consulted in "labels when opened" mode — the always-visible and
/// never cases encode their treatment in [NavBarLabelDisplayMode]. Default
/// `false` keeps the historical truncated-on-reveal behavior. Synced.
const navBarExpandedLabelsFullPreference = PreferenceDefinition<bool>(
  key: 'navigation.expanded_labels_full',
  scope: PreferenceScope.appSynced,
  defaultValue: false,
  codec: BoolPreferenceCodec(),
  introducedInAppVersion: '0.13.1',
  introducedInSchemaVersion: 38,
);

final appPreferenceRegistry = PreferenceRegistry(const [
  hideTotalMemberCountPreference,
  frontingReminderSuppressMinutesPreference,
  composerDefaultMemberPreference,
  dimBackgroundBehindSheetsPreference,
  forceCenteredSheetsPreference,
  typographyLetterSpacingPreference,
  navBarExpandedLabelsFullPreference,
]);
final memberProfilePreferenceRegistry = PreferenceRegistry(const []);
