import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'pluralport_bundle.dart';
import 'pluralport_mapper.dart';

/// Exports current app rows, overlaying edits on retained source records.
/// An absent local row never falls back to its imported snapshot.
class PluralPortExporter {
  PluralPortExporter(this.native, this.systemId);
  final Json native;
  final String systemId;
  final files = <String, Uint8List>{};
  final assets = <Json>[];
  final warnings = <String>[];

  PluralPortBundle build(List<Json> archives) {
    final result = <String, dynamic>{
      'pluralport_version': '0.1',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'producer': {
        'app': 'Prism',
        'app_id': 'prism',
        'exporter_version': '0.1.0',
      },
      'capabilities': {'modules': <String>[]},
      'extensions': <String, dynamic>{},
    };
    final emitted = <String, Set<String>>{};
    final archivedSystems = <Json>[];
    final origins = <Json>[];
    Json? systemBaseline;
    final seenNamespaces = <String>{};
    // Most recent snapshot for an origin wins; repeated imports never duplicate
    // records. Current native values still take precedence over either snapshot.
    final orderedArchives = [...archives]
      ..sort(
        (a, b) => (a['imported_at'] as String? ?? '').compareTo(
          b['imported_at'] as String? ?? '',
        ),
      );
    for (final archive in orderedArchives.reversed) {
      if (archive['kind'] != 'import' ||
          !seenNamespaces.add(archive['namespace'] as String)) {
        continue;
      }
      final envelope = PluralPortMapper.clone(archive['envelope'] as Json);
      final producer = envelope['producer'] as Map;
      if ((producer['app_id'] ?? producer['app']).toString().toLowerCase() !=
          'prism') {
        origins.add({
          'producer': producer,
          'exported_at': envelope['exported_at'],
          'capabilities': envelope['capabilities'],
          'warnings': envelope['warnings'],
          if (archive['readme_base64'] != null)
            'readme_base64': archive['readme_base64'],
        });
      }
      if (archive['systemProfileImported'] == true &&
          PluralPortMapper.rows(envelope, 'systems').firstOrNull?['id'] ==
              systemId) {
        systemBaseline ??= (archive['systemBaseline'] as Map?)
            ?.cast<String, dynamic>();
      }
      final storedFiles = archive['files'] as Map? ?? {};
      for (final entry in storedFiles.entries) {
        final path = entry.key as String;
        final bytes = base64Decode(entry.value as String);
        if (files.containsKey(path) &&
            sha256.convert(files[path]!).toString() !=
                sha256.convert(bytes).toString()) {
          throw FormatException(
            'Retained bundles have conflicting files at $path. Export a native Prism backup to preserve both.',
          );
        }
        files[path] = bytes;
      }
      final liveMedia = PluralPortMapper.rows(
        native,
        'mediaAttachments',
      ).map((r) => r['id']).toSet();
      final mediaBindings = archive['mediaBindings'] as Map? ?? {};
      bool retainedMedia(dynamic message, dynamic asset) =>
          !mediaBindings.containsKey('$message/$asset') ||
          liveMedia.contains(mediaBindings['$message/$asset']);
      for (final message in PluralPortMapper.rows(envelope, 'chat.messages')) {
        if (message['attachment_asset_ids'] is List) {
          message['attachment_asset_ids'] =
              (message['attachment_asset_ids'] as List)
                  .where((asset) => retainedMedia(message['id'], asset))
                  .toList();
        }
      }
      PluralPortMapper.setRows(
        envelope,
        'chat.attachments',
        PluralPortMapper.rows(
          envelope,
          'chat.attachments',
        ).where((a) => retainedMedia(a['message_id'], a['asset_id'])).toList(),
      );
      final bindings = archive['bindings'] as Map;
      final baseline = archive['baseline'] as Map;
      final liveDefinitions = {
        for (final row in PluralPortMapper.rows(native, 'customFields'))
          row['id'] as String: row,
      };
      final liveValues = {
        for (final row in PluralPortMapper.rows(native, 'customFieldValues'))
          row['id'] as String: row,
      };
      bool changed(Json before, Json after) => {
        ...before.keys,
        ...after.keys,
      }.any((key) => canonicalJson(before[key]) != canonicalJson(after[key]));
      bool valueDependsOnEditedDefinition(String valueId) {
        final value = liveValues[valueId];
        final fieldId = value?['customFieldId'];
        if (fieldId is! String) return false;
        final current = liveDefinitions[fieldId];
        final previous = baseline['customFields/$fieldId'];
        return current != null &&
            previous is Map &&
            changed(previous.cast<String, dynamic>(), current);
      }

      Json? baselineDefinitionForValue(String valueId) {
        final value = baseline['customFieldValues/$valueId'];
        final fieldId = value is Map ? value['customFieldId'] : null;
        final definition = fieldId is String
            ? baseline['customFields/$fieldId']
            : null;
        return definition is Map ? definition.cast<String, dynamic>() : null;
      }

      for (final entry in PluralPortMapper.collections.entries) {
        final live = {
          for (final row in PluralPortMapper.rows(native, entry.value))
            row['id'] as String: row,
        };
        final updated = <Json>[];
        for (final source in PluralPortMapper.rows(envelope, entry.key)) {
          final linked = bindings['${entry.key}/${source['id']}'] as List?;
          if (linked == null) {
            updated.add(source);
            continue;
          }
          final survivors = linked
              .where(live.containsKey)
              .cast<String>()
              .toList();
          if (survivors.isEmpty) continue;
          for (final id in survivors) {
            emitted.putIfAbsent(entry.value, () => {}).add(id);
          }
          final unchanged =
              survivors.length == linked.length &&
              survivors.every((id) {
                final before = baseline['${entry.value}/$id'] as Map;
                return !changed(before.cast<String, dynamic>(), live[id]!);
              }) &&
              // Choice IDs are projected through their field definition. A
              // definition edit can change a value's portable label or shape
              // even when the value row itself is unchanged.
              (entry.key != 'custom_field_values' ||
                  !survivors.any(valueDependsOnEditedDefinition));
          if (unchanged) {
            updated.add(source);
            continue;
          }
          // Keep opaque data, replacing only fields represented by Prism. A
          // cleared field is represented by null, so stale source text cannot win.
          for (var i = 0; i < survivors.length; i++) {
            final nativeId = survivors[i];
            final current = convert(entry.key, live[nativeId]!);
            final previous = convert(
              entry.key,
              (baseline['${entry.value}/$nativeId'] as Map)
                  .cast<String, dynamic>(),
              fieldDefinition: entry.key == 'custom_field_values'
                  ? baselineDefinitionForValue(nativeId)
                  : null,
            );
            final copy = PluralPortMapper.clone(source);
            if (entry.key == 'front_periods') {
              final sourceAssignments = (source['assignments'] as List)
                  .cast<Json>();
              final index = linked.indexOf(nativeId);
              final assignment = PluralPortMapper.clone(
                sourceAssignments[index],
              );
              _overlayChanges(
                assignment,
                (previous['assignments'] as List).first as Json,
                (current['assignments'] as List).first as Json,
              );
              copy['assignments'] = [assignment];
              current.remove('assignments');
              previous.remove('assignments');
              copy['id'] = nativeId;
            }
            for (final key in [
              'id',
              'system_id',
              'source_refs',
              'extensions',
            ]) {
              previous.remove(key);
            }
            final projected = Map<String, dynamic>.from(current)
              ..remove('id')
              ..remove('system_id')
              ..remove('source_refs')
              ..remove('extensions');
            _overlayChanges(copy, previous, projected);
            copy['source_refs'] = _refs(
              source['source_refs'],
              current['source_refs'],
            );
            copy['extensions'] = _extensions(
              source['extensions'],
              current['extensions'],
            );
            updated.add(copy);
          }
        }
        PluralPortMapper.setRows(envelope, entry.key, updated);
      }
      archivedSystems.addAll(PluralPortMapper.rows(envelope, 'systems'));
      for (final entry in envelope.entries) {
        if ([
          'systems',
          'producer',
          'capabilities',
          'exported_at',
          'pluralport_version',
          'openplural_version',
          'warnings',
        ].contains(entry.key)) {
          continue;
        }
        _merge(result, entry.key, entry.value);
      }
    }
    for (final entry in PluralPortMapper.collections.entries) {
      final records = PluralPortMapper.rows(result, entry.key);
      for (final row in PluralPortMapper.rows(native, entry.value)) {
        if (emitted[entry.value]?.contains(row['id']) ?? false) continue;
        // Memberless sleep has no honest FrontAssignment. Retain it in the
        // Prism namespace until a shared sleep module is defined.
        if (entry.key == 'front_periods' && row['sessionType'] == 1) continue;
        records.add(convert(entry.key, row));
      }
      PluralPortMapper.setRows(result, entry.key, records);
    }
    final settings =
        PluralPortMapper.rows(native, 'systemSettings').firstOrNull ?? {};
    final system = <String, dynamic>{
      'id': systemId,
      'name': settings['systemName'] ?? 'Prism system',
      'description': settings['systemDescription'],
      'color': settings['systemColor'],
      'tag': settings['systemTag'],
      'avatar_asset_id': _image(settings['systemAvatarData']),
      'privacy': {'visibility': 'private'},
      'source_refs': [
        {'app': 'prism', 'collection': 'systems', 'id': systemId},
      ],
    };
    final originalSystem = archivedSystems
        .where((r) => r['id'] == systemId)
        .firstOrNull;
    final exportedSystem = originalSystem == null
        ? system
        : PluralPortMapper.clone(originalSystem);
    if (originalSystem != null && systemBaseline != null) {
      const settingKeys = {
        'name': 'systemName',
        'description': 'systemDescription',
        'color': 'systemColor',
        'tag': 'systemTag',
        'avatar_asset_id': 'systemAvatarData',
      };
      for (final entry in settingKeys.entries) {
        if (canonicalJson(settings[entry.value]) !=
            canonicalJson(systemBaseline[entry.value])) {
          exportedSystem[entry.key] = system[entry.key];
        }
      }
    }
    exportedSystem['source_refs'] = _refs(
      originalSystem?['source_refs'],
      system['source_refs'],
    );
    result['systems'] = [
      exportedSystem,
      ...archivedSystems.where((r) => r['id'] != systemId),
    ];
    final allAssets = PluralPortMapper.rows(result, 'assets');
    final knownAssetIds = allAssets.map((r) => r['id']).toSet();
    allAssets.addAll(assets.where((r) => knownAssetIds.add(r['id'])));
    result['assets'] = allAssets;
    final extension = result['extensions'] as Json;
    final prism = (extension['prism'] as Map? ?? {}).cast<String, dynamic>();
    extension['prism'] = prism;
    if (origins.isNotEmpty) _merge(prism, 'import_sources', origins);
    final nativeModules = <String, dynamic>{
      for (final key in [
        'polls',
        'pollOptions',
        'habits',
        'habitCompletions',
        'reminders',
        'friends',
        'appPreferences',
        'conversationCategories',
      ])
        if ((native[key] as List? ?? []).isNotEmpty) key: native[key],
      'sleepSessions': [
        ...PluralPortMapper.rows(native, 'sleepSessions'),
        ...PluralPortMapper.rows(
          native,
          'frontSessions',
        ).where((r) => r['sessionType'] == 1),
      ],
    };
    _merge(prism, 'native_modules', nativeModules);
    if ((native['friends'] as List? ?? []).isNotEmpty) {
      warnings.add(
        'sharing_archived: Friend metadata is preserved; connections must be re-established manually.',
      );
    }
    // A Prism export must be safe to import into the same database or send
    // through another app and back. Persist native identity even for unchanged
    // records and opaque records that currently have no native representation.
    for (final path in [
      ...PluralPortMapper.collections.keys,
      'systems',
      'assets',
      'taxonomy_terms',
      'taxonomy_assignments',
      'front_events',
      'chat.attachments',
      'chat.reactions',
      'relationships.types',
      'relationships.edges',
    ]) {
      final unique = <String, Json>{};
      for (final record in PluralPortMapper.rows(result, path)) {
        final id = record['id'] as String;
        final previous = unique[id];
        if (previous != null) {
          previous['source_refs'] = _refs(
            previous['source_refs'],
            record['source_refs'],
          );
          for (final entry in record.entries.where(
            (e) => e.key != 'source_refs',
          )) {
            _merge(previous, entry.key, entry.value);
          }
        } else {
          unique[id] = record;
        }
      }
      for (final record in unique.values) {
        record['source_refs'] = _refs(record['source_refs'], [
          {
            'app': 'prism',
            'collection': PluralPortMapper.collections[path] ?? path,
            'id': record['id'],
          },
        ]);
      }
      PluralPortMapper.setRows(result, path, unique.values.toList());
    }
    _removeDanglingReferences(result);
    result['warnings'] = warnings
        .map(
          (s) => {'level': 'warning', 'code': s.split(':').first, 'message': s},
        )
        .toList();
    (result['capabilities'] as Json)['modules'] = result.entries
        .where(
          (e) =>
              e.value is List && (e.value as List).isNotEmpty ||
              [
                    'chat',
                    'boards',
                    'relationships',
                    'polls',
                    'habits',
                    'reminders',
                    'proxy',
                    'sharing',
                    'safety',
                  ].contains(e.key) &&
                  e.value is Map &&
                  (e.value as Map).isNotEmpty,
        )
        .map(
          (e) => switch (e.key) {
            'group_memberships' => 'groups',
            'custom_field_values' => 'custom_fields',
            'taxonomy_terms' || 'taxonomy_assignments' => 'taxonomy',
            _ => e.key,
          },
        )
        .where((key) => key != 'warnings')
        .toSet()
        .toList();
    return PluralPortBundle(result, files: files);
  }

  Json convert(String path, Json r, {Json? fieldDefinition}) {
    final common = <String, dynamic>{
      'id': r['id'],
      if (r['createdAt'] != null) 'created_at': r['createdAt'],
      'source_refs': [
        {
          'app': 'prism',
          'collection': PluralPortMapper.collections[path],
          'id': r['id'],
        },
      ],
      'extensions': {
        'prism': {
          'native': {
            for (final e in r.entries)
              if (![
                'profilePhotoData',
                'profileHeaderImageData',
                'pkBannerImageData',
                'avatarImageData',
              ].contains(e.key))
                e.key: e.value,
          },
        },
      },
    };
    Json record;
    switch (path) {
      case 'members':
        record = {
          'system_id': systemId,
          'name': r['name'],
          'display_name': r['displayName'],
          'pronouns': r['pronouns'],
          'age': r['age'],
          'description': r['notes'],
          'birthday': r['birthday'] == null
              ? null
              : {
                  'value': r['birthday'],
                  'precision': r['birthday'].toString().length == 5
                      ? 'month_day'
                      : 'day',
                  'year_visible': r['birthday'].toString().length != 5,
                },
          'color': r['customColorEnabled'] == true ? r['customColorHex'] : null,
          'avatar_asset_id': _image(r['profilePhotoData']),
          'banner_asset_id': _image(r['profileHeaderImageData']),
          'created_at': r['createdAt'],
          'sort_order': r['displayOrder'],
          'archived': r['isActive'] == false,
          'proxy_tags': _decode(r['proxyTagsJson'], []),
        };
      case 'groups':
        record = {
          'system_id': systemId,
          'name': r['name'],
          'description': r['description'],
          'color': r['colorHex'],
          'emoji': r['emoji'],
          'parent_group_id': r['parentGroupId'],
          'avatar_asset_id': _image(r['avatarImageData']),
          'sort_order': r['displayOrder'],
        };
      case 'group_memberships':
        record = {'group_id': r['groupId'], 'member_id': r['memberId']};
      case 'notes':
        record = {
          'system_id': systemId,
          'member_id': r['memberId'],
          'title': r['title'],
          'body': r['body'],
          'color': r['colorHex'],
          'entry_date': r['date'].toString().split('T').first,
          'created_at': r['createdAt'],
          'updated_at': r['modifiedAt'],
        };
      case 'custom_fields':
        record = {
          'system_id': systemId,
          'name': r['name'],
          'field_type':
              {
                0: 'text',
                1: 'color',
                2: 'date',
                3: 'markdown',
                4: 'select',
              }[r['fieldType']] ??
              'json',
          'date_precision': {
            0: 'day',
            2: 'month_day',
            3: 'month',
            4: 'year',
          }[r['datePrecision']],
          'sort_order': r['displayOrder'],
        };
      case 'custom_field_values':
        record = {
          'field_id': r['customFieldId'],
          'subject_type': 'member',
          'subject_id': r['memberId'],
          'value': r['value'],
        };
      case 'front_periods':
        record = {
          'system_id': systemId,
          'started_at': r['startTime'],
          'ended_at': r['endTime'],
          'assignments': [
            {
              'member_id': r['headmateId'],
              'front_role': 'member',
              'note': r['notes'],
            },
          ],
          'source_kind': 'interval',
        };
      case 'front_comments':
        record = {
          'system_id': systemId,
          'front_period_id': r['sessionId'],
          'target_time': r['timestamp'],
          'body': r['body'],
          'created_at': r['createdAt'],
        };
      case 'chat.conversations':
        record = {
          'system_id': systemId,
          'kind': r['isDirectMessage'] == true
              ? 'direct_message'
              : 'internal_chat',
          'direct_message': r['isDirectMessage'] == true,
          'title': r['title'],
          'emoji': r['emoji'],
          'description': r['description'],
          'creator_member_id': r['creatorId'],
          'participant_member_ids': r['includesAllMembers'] == true
              ? []
              : r['participantIds'],
          'archived': r['archivedForEveryone'] == true,
          'created_at': r['createdAt'],
          'sort_order': r['displayOrder'],
        };
      case 'chat.messages':
        record = {
          'conversation_id': r['conversationId'],
          'author_member_id': r['authorId'],
          'body': r['content'],
          'created_at': r['timestamp'],
          'edited_at': r['editedAt'],
          'reply_to_message_id': r['replyToId'],
          'system_message': r['isSystemMessage'] == true,
        };
      case 'boards.posts':
        record = {
          'system_id': systemId,
          'target_member_id': r['targetMemberId'],
          'author_member_id': r['authorId'],
          'title': r['title'],
          'body': r['body'],
          'audience': r['audience'],
          'created_at': r['createdAt'],
          'written_at': r['writtenAt'],
          'edited_at': r['editedAt'],
        };
      default:
        throw ArgumentError.value(path);
    }
    if (path == 'custom_fields') {
      final config = _decode(r['typeConfigJson'], null);
      if ((r['fieldTypeId'] == 'choice' || r['fieldType'] == 4) &&
          config is Map) {
        record['field_type'] = config['allowsMultiple'] == true
            ? 'multiselect'
            : 'select';
        record['options'] = (config['options'] as List? ?? [])
            .whereType<Map>()
            .where((o) => o['isDeleted'] != true)
            .map((o) => o['label'])
            .toList();
      } else if (r['fieldTypeId'] != null &&
          !['text', 'color', 'date', 'longText'].contains(r['fieldTypeId'])) {
        record['field_type'] = 'json';
      }
    }
    if (path == 'custom_field_values') {
      final definition =
          fieldDefinition ??
          PluralPortMapper.rows(
            native,
            'customFields',
          ).where((f) => f['id'] == r['customFieldId']).firstOrNull;
      final config = _decode(definition?['typeConfigJson'], null);
      if (config is Map && config['runtimeType'] == 'choice') {
        final value = _decode(r['value'], null);
        final names = {
          for (final o
              in (config['options'] as List? ?? []).whereType<Map>().where(
                (o) => o['isDeleted'] != true,
              ))
            o['id']: o['label'],
        };
        final selected = value is Map
            ? (value['options'] as List? ?? [])
            : const [];
        final labels = selected
            .where(names.containsKey)
            .map((id) => names[id])
            .toList();
        if (value is Map && value['other'] is String) {
          labels.add(value['other']);
        }
        record['value'] = config['allowsMultiple'] == true
            ? labels
            : labels.firstOrNull;
      } else if (definition?['fieldTypeId'] != null &&
          ![
            'text',
            'color',
            'date',
            'longText',
          ].contains(definition?['fieldTypeId'])) {
        record['value'] = _decode(r['value'], r['value']);
      }
    }
    return {...common, ...record};
  }

  static void _overlayChanges(Json target, Json before, Json after) {
    for (final key in {...before.keys, ...after.keys}) {
      if (canonicalJson(before[key]) == canonicalJson(after[key])) continue;
      if (before[key] is Json && after[key] is Json && target[key] is Json) {
        _overlayChanges(
          target[key] as Json,
          before[key] as Json,
          after[key] as Json,
        );
      } else {
        target[key] = after[key];
      }
    }
  }

  void _removeDanglingReferences(Json envelope) {
    Set<dynamic> ids(String path) =>
        PluralPortMapper.rows(envelope, path).map((r) => r['id']).toSet();
    final members = ids('members'),
        groups = ids('groups'),
        fields = ids('custom_fields');
    // Local deletions can leave historical records in native exports. Remove
    // dead optional links; records that require a deleted parent are omitted.
    for (final path in PluralPortMapper.collections.keys) {
      final records = <Json>[];
      for (final row in PluralPortMapper.rows(envelope, path)) {
        var keep = true;
        if (path == 'group_memberships') {
          keep =
              members.contains(row['member_id']) &&
              groups.contains(row['group_id']);
        }
        if (path == 'custom_field_values') {
          keep =
              fields.contains(row['field_id']) &&
              (row['subject_type'] != 'member' ||
                  members.contains(row['subject_id']));
        }
        if (path == 'front_periods') {
          final assignments = (row['assignments'] as List)
              .where((a) => members.contains((a as Map)['member_id']))
              .toList();
          row['assignments'] = assignments;
          keep = assignments.isNotEmpty;
        }
        if (!keep) {
          warnings.add(
            'deleted_reference: $path record omitted after its parent was deleted.',
          );
          continue;
        }
        for (final key in [
          'member_id',
          'author_member_id',
          'creator_member_id',
          'target_member_id',
        ]) {
          if (row[key] != null && !members.contains(row[key])) row[key] = null;
        }
        if (row['parent_group_id'] != null &&
            !groups.contains(row['parent_group_id'])) {
          row['parent_group_id'] = null;
        }
        for (final key in ['participant_member_ids', 'author_member_ids']) {
          if (row[key] is List) {
            row[key] = (row[key] as List).where(members.contains).toList();
          }
        }
        records.add(row);
      }
      PluralPortMapper.setRows(envelope, path, records);
    }
    final periods = ids('front_periods'),
        conversations = ids('chat.conversations');
    for (final r in PluralPortMapper.rows(envelope, 'front_comments')) {
      if (r['front_period_id'] != null &&
          !periods.contains(r['front_period_id'])) {
        r['front_period_id'] = null;
      }
    }
    PluralPortMapper.setRows(
      envelope,
      'chat.messages',
      PluralPortMapper.rows(
        envelope,
        'chat.messages',
      ).where((r) => conversations.contains(r['conversation_id'])).toList(),
    );
    final messages = ids('chat.messages');
    for (final r in PluralPortMapper.rows(envelope, 'chat.messages')) {
      if (r['reply_to_message_id'] != null &&
          !messages.contains(r['reply_to_message_id'])) {
        r['reply_to_message_id'] = null;
      }
    }
  }

  String? _image(dynamic b64) {
    if (b64 is! String || b64.isEmpty) return null;
    final bytes = base64Decode(b64);
    final hash = sha256.convert(bytes).toString();
    final path = 'assets/$hash';
    files[path] = bytes;
    final id = PluralPortMapper.stableId('prism/assets', hash);
    assets.add({
      'id': id,
      'kind': 'image',
      'bundle_path': path,
      'size_bytes': bytes.length,
      'sha256': hash,
    });
    return id;
  }

  static dynamic _decode(dynamic value, dynamic fallback) {
    if (value == null) return fallback;
    try {
      return jsonDecode(value as String);
    } catch (_) {
      return fallback;
    }
  }

  static List<dynamic> _refs(dynamic a, dynamic b) {
    final seen = <String>{};
    return [
      ...a as List? ?? [],
      ...b as List? ?? [],
    ].where((v) => seen.add(canonicalJson(v))).toList();
  }

  static Json _extensions(dynamic a, dynamic b) {
    final result = Map<String, dynamic>.from(a as Map? ?? const {});
    for (final e in (b as Json? ?? {}).entries) {
      result[e.key] = e.value is Map && result[e.key] is Map
          ? {...result[e.key] as Map, ...e.value as Map}
          : e.value;
    }
    return result;
  }

  void _merge(Json target, String key, dynamic value) {
    if (!target.containsKey(key)) {
      target[key] = value;
      return;
    }
    final current = target[key];
    if (canonicalJson(current) == canonicalJson(value)) return;
    if (current is List && value is List) {
      final seen = current.map(canonicalJson).toSet();
      current.addAll(value.where((v) => seen.add(canonicalJson(v))));
      return;
    }
    if (current is Json && value is Json) {
      for (final e in value.entries) {
        _merge(current, e.key, e.value);
      }
      return;
    }
    if (canonicalJson(current) == canonicalJson(value)) return;
    // Conflicting opaque values retain their boundaries rather than being
    // silently overwritten or combined into a shape neither source specified.
    final ext =
        target.putIfAbsent('pluralport_preserved_conflicts', () => <dynamic>[])
            as List;
    ext.add({'key': key, 'value': value});
    warnings.add('preserved_conflict: $key');
  }
}
