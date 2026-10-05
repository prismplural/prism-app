import '../../../domain/preferences/preference_entity_id.dart';
import '../../../domain/preferences/preference_registry.dart';
import '../services/pluralport_mapper.dart';

/// Counts describe the mapped file, before existing records and tombstones are
/// checked by the importer. File inventory is separate from native record counts.
class PluralPortImportSummary {
  PluralPortImportSummary(
    Map<String, dynamic> native,
    Map<String, dynamic> archive,
    List<String> warnings,
  ) {
    final envelope = (archive['envelope'] as Map).cast<String, dynamic>();
    final bindings = archive['bindings'] as Map? ?? const {};
    for (final entry in nativeSections.entries) {
      final count = PluralPortMapper.rows(native, entry.key).length;
      if (count > 0) ready[entry.value] = count;
    }
    for (final entry in portableSections.entries) {
      final count = PluralPortMapper.rows(envelope, entry.key)
          .where((row) => !bindings.containsKey('${entry.key}/${row['id']}'))
          .length;
      if (count > 0) retained[entry.value] = count;
    }
    systemProfiles = PluralPortMapper.rows(envelope, 'systems').length;

    final modules =
        ((envelope['extensions'] as Map?)?['prism'] as Map?)?['native_modules'];
    final knownKeys = appPreferenceRegistry.definitions
        .map((definition) => PreferenceEntityId.app(definition.key))
        .toSet();
    if (modules is Map) {
      final settings = (modules['systemSettings'] as List? ?? const [])
          .whereType<Map>();
      final preferences = (modules['appPreferences'] as List? ?? const [])
          .whereType<Map>();
      hasPreferences =
          settings.any(
            (row) =>
                row.keys.any(PluralPortMapper.portableSettingKeys.contains),
          ) ||
          preferences.any((row) => knownKeys.contains(row['key']));

      if (settings.any(
            (row) => row.keys.any(
              (key) => !PluralPortMapper.portableSettingKeys.contains(key),
            ),
          ) ||
          preferences.any((row) => !knownKeys.contains(row['key'])) ||
          modules.keys.any(
            (key) => !{
              ...PluralPortMapper.nativeModuleKeys,
              'systemSettings',
              'appPreferences',
            }.contains(key),
          )) {
        hasOtherData = true;
      }
    }
    // These optional modules have no native mapping. A module may be an object
    // rather than an array, so do not manufacture a record count from its keys.
    for (final key in [
      'polls',
      'habits',
      'reminders',
      'sharing',
      'safety',
      'proxy',
    ]) {
      final value = envelope[key];
      if (_hasContent(value)) {
        retained[key] = value is List ? value.length : null;
      }
    }
    const knownRootKeys = {
      'pluralport_version',
      'openplural_version',
      'exported_at',
      'producer',
      'capabilities',
      'lineage',
      'warnings',
      'extensions',
      'systems',
      'assets',
      'chat',
      'boards',
      'relationships',
      'polls',
      'habits',
      'reminders',
      'sharing',
      'safety',
      'proxy',
    };
    hasOtherData =
        hasOtherData ||
        envelope.entries.any(
          (entry) =>
              !knownRootKeys.contains(entry.key) &&
              !portableSections.containsKey(entry.key) &&
              _hasContent(entry.value),
        );
    void inspectExtensions(dynamic value) {
      if (value is Map) {
        final extensions = value['extensions'];
        if (extensions is Map &&
            extensions.entries.any(
              (entry) => entry.key != 'prism' && _hasContent(entry.value),
            )) {
          hasOtherData = true;
        }
        for (final item in value.values) {
          inspectExtensions(item);
        }
      } else if (value is List) {
        for (final item in value) {
          inspectExtensions(item);
        }
      }
    }

    inspectExtensions(envelope);
    if (hasOtherData) retained['extraData'] = null;

    bundledFiles = (archive['files'] as Map? ?? const {}).length;
    missingFiles = warnings
        .where((warning) => warning.startsWith('asset_bundle_missing:'))
        .length;
    unbundledMedia = warnings
        .where((warning) => warning.startsWith('asset_uri_only:'))
        .length;
  }

  final ready = <String, int>{};
  final retained = <String, int?>{};
  int systemProfiles = 0;
  bool get hasSystemProfile => systemProfiles > 0;
  bool hasPreferences = false;
  bool hasOtherData = false;
  int bundledFiles = 0;
  int missingFiles = 0;
  int unbundledMedia = 0;

  static bool _hasContent(dynamic value) =>
      value != null &&
      !(value is List && value.isEmpty) &&
      !(value is Map && value.isEmpty);

  static const nativeSections = {
    'headmates': 'members',
    'memberGroups': 'groups',
    'memberGroupEntries': 'memberships',
    'customFields': 'fields',
    'customFieldValues': 'fieldValues',
    'notes': 'notes',
    'frontSessions': 'fronts',
    'frontSessionComments': 'frontComments',
    'conversations': 'conversations',
    'messages': 'messages',
    'memberBoardPosts': 'boardPosts',
    'polls': 'polls',
    'pollOptions': 'pollOptions',
    'habits': 'habits',
    'habitCompletions': 'habitCompletions',
    'reminders': 'reminders',
    'friends': 'friends',
    'conversationCategories': 'conversationCategories',
    'sleepSessions': 'sleep',
  };
  static const portableSections = {
    'members': 'members',
    'groups': 'groups',
    'group_memberships': 'memberships',
    'custom_fields': 'fields',
    'custom_field_values': 'fieldValues',
    'notes': 'notes',
    'front_periods': 'fronts',
    'front_comments': 'frontComments',
    'chat.conversations': 'conversations',
    'chat.messages': 'messages',
    'boards.posts': 'boardPosts',
    'front_events': 'frontEvents',
    'taxonomy_terms': 'taxonomyTerms',
    'taxonomy_assignments': 'taxonomyAssignments',
    'chat.reactions': 'reactions',
    'relationships.types': 'relationshipTypes',
    'relationships.edges': 'relationships',
  };
}
