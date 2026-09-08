import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'pluralport_bundle.dart';

typedef Json = Map<String, dynamic>;

/// Translation is separate from persistence: malformed references are rejected
/// before any app rows or retained metadata are written.
class PluralPortMapper {
  static const collections = {
    'members': 'headmates',
    'groups': 'memberGroups',
    'group_memberships': 'memberGroupEntries',
    'custom_fields': 'customFields',
    'custom_field_values': 'customFieldValues',
    'notes': 'notes',
    'front_periods': 'frontSessions',
    'front_comments': 'frontSessionComments',
    'chat.conversations': 'conversations',
    'chat.messages': 'messages',
    'boards.posts': 'memberBoardPosts',
  };

  /// Every file-local record identity. JSON nested under these rows is opaque
  /// unless it appears in [coreReferenceTarget].
  static final recordPaths = [
    ...collections.keys,
    'systems',
    'assets',
    'taxonomy_terms',
    'taxonomy_assignments',
    'front_events',
    'chat.attachments',
    'chat.reactions',
    'relationships.types',
    'relationships.edges',
  ];

  /// Declared top-level references, keyed by the record array that owns them.
  /// This deliberately is not a global key list: a field called `member_id` in
  /// an option, value, extension, or future module is arbitrary JSON.
  static const coreReferences = <String, Map<String, String>>{
    'systems': {
      'parent_system_id': 'systems',
      'avatar_asset_id': 'assets',
      'banner_asset_id': 'assets',
    },
    'members': {
      'system_id': 'systems',
      'avatar_asset_id': 'assets',
      'banner_asset_id': 'assets',
    },
    'groups': {
      'system_id': 'systems',
      'parent_group_id': 'groups',
      'avatar_asset_id': 'assets',
    },
    'group_memberships': {'group_id': 'groups', 'member_id': 'members'},
    'taxonomy_terms': {
      'system_id': 'systems',
      'parent_term_id': 'taxonomy_terms',
    },
    'taxonomy_assignments': {'term_id': 'taxonomy_terms'},
    'custom_fields': {'system_id': 'systems'},
    'custom_field_values': {'field_id': 'custom_fields'},
    'notes': {
      'system_id': 'systems',
      'member_id': 'members',
      'author_member_ids': 'members',
      'attachment_asset_ids': 'assets',
    },
    'front_periods': {'system_id': 'systems'},
    'front_events': {'system_id': 'systems'},
    'front_comments': {
      'system_id': 'systems',
      'front_period_id': 'front_periods',
      'front_event_id': 'front_events',
      'author_member_id': 'members',
    },
    'chat.conversations': {
      'system_id': 'systems',
      'creator_member_id': 'members',
      'participant_member_ids': 'members',
    },
    'chat.messages': {
      'conversation_id': 'chat.conversations',
      'author_member_id': 'members',
      'reply_to_message_id': 'chat.messages',
      'attachment_asset_ids': 'assets',
    },
    'chat.attachments': {'message_id': 'chat.messages', 'asset_id': 'assets'},
    'chat.reactions': {'message_id': 'chat.messages', 'member_id': 'members'},
    'boards.posts': {
      'system_id': 'systems',
      'target_member_id': 'members',
      'author_member_id': 'members',
    },
    'relationships.types': {'system_id': 'systems'},
    'relationships.edges': {
      'system_id': 'systems',
      'type_id': 'relationships.types',
      'from_member_id': 'members',
      'to_member_id': 'members',
    },
  };

  static List<Json> rows(Json envelope, String path) {
    dynamic value = envelope;
    for (final key in path.split('.')) {
      value = value is Map ? value[key] : null;
    }
    if (value == null) return [];
    if (value is! List || value.any((e) => e is! Map<String, dynamic>)) {
      throw FormatException('$path must contain an array of records.');
    }
    return value.cast<Json>();
  }

  static void setRows(Json target, String path, List<Json> value) {
    final keys = path.split('.');
    var parent = target;
    for (final key in keys.take(keys.length - 1)) {
      parent = (parent.putIfAbsent(key, () => <String, dynamic>{}) as Map)
          .cast<String, dynamic>();
    }
    parent[keys.last] = value;
  }

  static Json clone(Json value) => jsonDecode(jsonEncode(value)) as Json;
  static String stableId(String namespace, String id) =>
      const Uuid().v5(Namespace.url.value, '$namespace/$id');

  static PluralPortImportPlan plan(PluralPortBundle bundle) {
    bundle.validateVersion();
    final source = clone(bundle.envelope);
    final producer = source['producer'] as Map;
    final systems = rows(source, 'systems');
    final origin = canonicalJson([
      producer['app_id'] ?? producer['app'],
      systems.map((s) => s['source_refs'] ?? s['id']).toList(),
    ]);
    final namespace = sha256.convert(utf8.encode(origin)).toString();
    final ids = <String, String>{};
    for (final path in recordPaths) {
      for (final row in rows(source, path)) {
        final id = row['id'];
        if (id is! String || id.isEmpty || ids.containsKey(id)) {
          throw FormatException('Missing or duplicate file-local ID in $path.');
        }
        final refs = row['source_refs'];
        final nativeRefs = refs is List
            ? refs.whereType<Map>().where(
                (ref) =>
                    ref['app'] == 'prism' &&
                    ref['collection'] == (collections[path] ?? path) &&
                    ref['id'] is String,
              )
            : const <Map>[];
        ids[id] = nativeRefs.isEmpty
            ? stableId(namespace, id)
            : nativeRefs.firstWhere(
                    (ref) => ref['id'] == id,
                    orElse: () => nativeRefs.first,
                  )['id']
                  as String;
      }
    }
    if (ids.values.toSet().length != ids.length) {
      throw const FormatException(
        'Multiple records claim the same Prism identity.',
      );
    }
    final document = _remapCoreGraph(source, ids);
    for (final path in recordPaths) {
      final before = rows(source, path);
      final after = rows(document, path);
      for (var i = 0; i < before.length; i++) {
        final refs = List<dynamic>.from(after[i]['source_refs'] as List? ?? []);
        refs.add({
          'app': producer['app_id'] ?? producer['app'] ?? 'unknown',
          'collection': path,
          'id': before[i]['id'],
        });
        after[i]['source_refs'] = refs;
      }
    }
    // Opaque extension data may reference additional bundle files. Retain their
    // paths and bytes too; never guess which foreign files are disposable.
    final assetFiles = <String, String>{
      for (final entry in bundle.files.entries)
        if (!PluralPortBundle.roots.contains(entry.key) &&
            entry.key != 'README.txt')
          entry.key: base64Encode(entry.value),
    };
    final warnings = <String>[];
    var assetTotal = 0;
    final originalAssets = rows(source, 'assets');
    final mappedAssets = rows(document, 'assets');
    for (var i = 0; i < originalAssets.length; i++) {
      final bytes = bundle.assetBytes(originalAssets[i]);
      final asset = mappedAssets[i];
      if (bytes != null) {
        assetTotal += bytes.length;
        if (assetTotal > PluralPortBundle.maxExpanded) {
          throw const FormatException('Assets exceed the expanded size limit.');
        }
        final path =
            originalAssets[i]['bundle_path'] as String? ??
            (((originalAssets[i]['extensions'] as Map?)?['sheaf']
                    as Map?)?['bundle_path']
                as String?) ??
            'assets/${sha256.convert(bytes)}';
        assetFiles[path] = base64Encode(bytes);
        asset
          ..['sha256'] = sha256.convert(bytes).toString()
          ..['size_bytes'] = bytes.length
          ..['bundle_path'] = path
          ..remove('data_base64')
          ..remove('data_uri');
      } else {
        if (originalAssets[i]['bundle_path'] != null ||
            ((originalAssets[i]['extensions'] as Map?)?['sheaf']
                    as Map?)?['bundle_path'] !=
                null) {
          warnings.add('asset_bundle_missing: ${originalAssets[i]['id']}');
        } else {
          warnings.add(
            'asset_uri_only: ${originalAssets[i]['id']} (URL retained; not downloaded)',
          );
        }
      }
    }
    for (final asset in mappedAssets) {
      if (!['image', 'audio'].contains(asset['kind'])) {
        warnings.add('asset_archived_only: ${asset['id']}');
      }
    }
    _validateReferences(document);
    final native = emptyNative();
    final baseline = <String, dynamic>{};
    final bindings = <String, dynamic>{};
    final assets = {for (final a in mappedAssets) a['id'] as String: a};
    String? image(dynamic id) {
      final asset = assets[id];
      if (asset == null) return null;
      final mime = asset['mime_type'] as String?;
      if (mime != null && !mime.startsWith('image/')) return null;
      return assetFiles[asset['bundle_path']];
    }

    for (final entry in collections.entries) {
      final imported = <Json>[];
      for (final portable in rows(document, entry.key)) {
        final mapped = _toNative(entry.key, portable, image);
        if (entry.key == 'custom_field_values') {
          final definition = rows(
            native,
            'customFields',
          ).where((f) => f['id'] == portable['field_id']).firstOrNull;
          if (definition?['fieldTypeId'] == 'choice') {
            final config =
                jsonDecode(definition!['typeConfigJson'] as String) as Map;
            final options = {
              for (final o in (config['options'] as List).cast<Map>())
                o['label']: o['id'],
            };
            final value = portable['value'];
            final selected = value is List
                ? value
                : value == null
                ? []
                : [value];
            mapped.clear();
            if (portable['subject_type'] == 'member' &&
                selected.every(options.containsKey)) {
              mapped.add({
                'id': portable['id'],
                'customFieldId': portable['field_id'],
                'memberId': portable['subject_id'],
                'value': jsonEncode({
                  'options': selected.map((v) => options[v]).toList(),
                }),
              });
            }
          }
        }
        final prism = (portable['extensions'] as Map?)?['prism'];
        final extra = prism is Map ? prism['native'] : null;
        if (extra is Map) {
          const allowed = {
            'emoji',
            'customColorEnabled',
            'customColorHex',
            'markdownEnabled',
            'profileHeaderSource',
            'profileHeaderLayout',
            'profileHeaderVisible',
            'nameStyleFont',
            'nameStyleBold',
            'nameStyleItalic',
            'nameStyleColorMode',
            'nameStyleColorHex',
            'isAlwaysFronting',
            'fieldType',
            'fieldTypeId',
            'typeConfigJson',
            'datePrecision',
            'groupType',
            'filterRules',
            'sortState',
            'confidence',
            'quality',
          };
          if (mapped.isEmpty &&
              entry.key == 'custom_fields' &&
              extra['fieldType'] is int) {
            mapped.add({
              'id': portable['id'],
              'name': portable['name'],
              'fieldType': extra['fieldType'],
              'displayOrder': (portable['sort_order'] as num?)?.toInt() ?? 0,
              'createdAt': time(
                portable['created_at'],
                fallback: '1970-01-01T00:00:00.000Z',
              ),
            });
          }
          for (final row in mapped) {
            for (final key in allowed) {
              if (!row.containsKey(key) && extra.containsKey(key)) {
                row[key] = extra[key];
              }
            }
          }
        }
        if (mapped.isEmpty) {
          warnings.add('preserved_only: ${entry.key}/${portable['id']}');
          continue;
        }
        imported.addAll(mapped);
        bindings['${entry.key}/${portable['id']}'] = mapped
            .map((r) => r['id'])
            .toList();
        for (final row in mapped) {
          baseline['${entry.value}/${row['id']}'] = row;
        }
      }
      native[entry.value] = imported;
    }
    final supportedFields = rows(
      native,
      'customFields',
    ).map((r) => r['id']).toSet();
    final supportedConversations = rows(
      native,
      'conversations',
    ).map((r) => r['id']).toSet();
    for (final entry in {
      'custom_field_values': 'customFieldValues',
      'chat.messages': 'messages',
    }.entries) {
      final retained = <Json>[];
      for (final row in rows(native, entry.value)) {
        final supported = entry.key == 'custom_field_values'
            ? supportedFields.contains(row['customFieldId'])
            : supportedConversations.contains(row['conversationId']);
        if (supported) {
          retained.add(row);
        } else {
          bindings.remove('${entry.key}/${row['id']}');
          warnings.add('preserved_only: ${entry.key}/${row['id']}');
        }
      }
      native[entry.value] = retained;
    }
    // Event-only timelines can be preserved without inventing a second history
    // when a file contains both events and periods.
    for (final key in [
      'front_events',
      'taxonomy_terms',
      'taxonomy_assignments',
      'polls',
      'habits',
      'reminders',
      'sharing',
      'relationships',
      'safety',
      'proxy',
    ]) {
      final value = document[key];
      if (value != null && value is! List ||
          value is List && value.isNotEmpty) {
        warnings.add('module_archived_only: $key');
      }
    }
    if (systems.length > 1) {
      warnings.add('preserved_only: additional system profiles');
    }
    return PluralPortImportPlan(native, {
      'kind': 'import',
      'namespace': namespace,
      'envelope': document,
      if (bundle.files['README.txt'] case final readme?)
        'readme_base64': base64Encode(readme),
      'files': assetFiles,
      'bindings': bindings,
      'baseline': baseline,
    }, warnings);
  }

  static Json _remapCoreGraph(Json source, Map<String, String> ids) {
    final document = clone(source);
    for (final path in recordPaths) {
      for (final record in rows(document, path)) {
        record['id'] = ids[record['id']] ?? record['id'];
        for (final key in record.keys.toList()) {
          if (coreReferenceTarget(path, record, key) == null) continue;
          record[key] = _remapReference(record[key], ids);
        }
        if (path == 'front_periods' || path == 'front_events') {
          final assignments = record['assignments'];
          if (assignments is List) {
            for (final assignment in assignments.whereType<Map>()) {
              if (assignment['member_id'] is String) {
                assignment['member_id'] =
                    ids[assignment['member_id']] ?? assignment['member_id'];
              }
            }
          }
        }
      }
    }
    return document;
  }

  static dynamic _remapReference(dynamic value, Map<String, String> ids) {
    if (value is String) return ids[value] ?? value;
    if (value is List) {
      return [
        for (final item in value) item is String ? ids[item] ?? item : item,
      ];
    }
    return value;
  }

  /// Returns a target only when [key] is a declared reference on [path].
  /// Typed subject references are intentionally resolved from their owning row;
  /// no inference is made from keys inside a payload.
  static String? coreReferenceTarget(String path, Json record, String key) {
    final direct = coreReferences[path]?[key];
    if (direct != null) return direct;
    if (key != 'subject_id') return null;
    return switch (path) {
      'custom_field_values' => switch (record['subject_type']) {
        'member' => 'members',
        'system' => 'systems',
        _ => null,
      },
      'taxonomy_assignments' => switch (record['subject_type']) {
        'member' => 'members',
        'note' => 'notes',
        'asset' => 'assets',
        'front_period' => 'front_periods',
        'custom' => null,
        _ => null,
      },
      _ => null,
    };
  }

  static Json emptyNative() => {
    'formatVersion': '1.0',
    'version': '1.0',
    'appName': 'PluralPort',
    'exportDate': DateTime.now().toUtc().toIso8601String(),
    'totalRecords': 0,
    for (final key in {
      ...collections.values,
      'systemSettings',
      'sleepSessions',
      'polls',
      'pollOptions',
      'habits',
      'habitCompletions',
    })
      key: <Json>[],
  };

  static String time(dynamic value, {String? fallback}) {
    if (value == null && fallback != null) return fallback;
    if (value is! String || DateTime.tryParse(value) == null) {
      throw const FormatException('Invalid PluralPort timestamp.');
    }
    return DateTime.parse(value).toUtc().toIso8601String();
  }

  static List<Json> _toNative(
    String path,
    Json r,
    String? Function(dynamic) image,
  ) {
    final id = r['id'];
    final created = r['created_at'] == null
        ? '1970-01-01T00:00:00.000Z'
        : time(r['created_at']);
    switch (path) {
      case 'members':
        return [
          {
            'id': id,
            'name': r['name'] ?? r['display_name'] ?? 'Unnamed member',
            'displayName': r['display_name'],
            'pronouns': r['pronouns'],
            'age': r['age'],
            'notes': r['description'],
            'birthday': (r['birthday'] as Map?)?['value'],
            'profilePhotoData': image(r['avatar_asset_id']),
            'profileHeaderImageData': image(r['banner_asset_id']),
            'isActive': r['archived'] != true, 'createdAt': created,
            'displayOrder': (r['sort_order'] as num?)?.toInt() ?? 0,
            'customColorEnabled': r['color'] != null,
            'customColorHex': r['color'],
            'proxyTagsJson': jsonEncode(r['proxy_tags'] ?? []),
            // Cross-app imports must not automatically create links to a live PK account.
            'pluralkitSyncIgnored': true,
          },
        ];
      case 'groups':
        return [
          {
            'id': id,
            'name': r['name'],
            'description': r['description'],
            'colorHex': r['color'],
            'emoji': r['emoji'],
            'avatarImageData': image(r['avatar_asset_id']),
            'parentGroupId': r['parent_group_id'],
            'createdAt': created,
            'displayOrder': (r['sort_order'] as num?)?.toInt() ?? 0,
          },
        ];
      case 'group_memberships':
        return [
          {'id': id, 'groupId': r['group_id'], 'memberId': r['member_id']},
        ];
      case 'notes':
        return [
          {
            'id': id,
            'title': r['title'] ?? '',
            'body': r['body'],
            'memberId': r['member_id'],
            'colorHex': r['color'],
            'createdAt': created,
            'modifiedAt': time(r['updated_at'], fallback: created),
            'date': time(r['entry_date'], fallback: created),
          },
        ];
      case 'front_periods':
        final assignments = (r['assignments'] as List).cast<Json>();
        if (assignments.isEmpty) return [];
        return [
          for (var i = 0; i < assignments.length; i++)
            {
              'id': i == 0 ? id : stableId(id as String, 'assignment/$i'),
              'headmateId': assignments[i]['member_id'],
              'sessionType': 0,
              'startTime': time(r['started_at']),
              'endTime': r['ended_at'] == null ? null : time(r['ended_at']),
              'notes': assignments[i]['note'] ?? r['note'],
            },
        ];
      case 'front_comments':
        if (r['front_period_id'] == null) return [];
        return [
          {
            'id': id,
            'sessionId': r['front_period_id'],
            'body': r['body'],
            'timestamp': time(r['target_time']),
            'createdAt': created,
          },
        ];
      case 'custom_fields':
        if (['select', 'multiselect'].contains(r['field_type']) &&
            r['options'] is List &&
            (r['options'] as List).every((o) => o is String)) {
          final options = (r['options'] as List)
              .cast<String>()
              .toSet()
              .toList();
          return [
            {
              'id': id,
              'name': r['name'],
              'fieldType': 4,
              'fieldTypeId': 'choice',
              'createdAt': created,
              'displayOrder': (r['sort_order'] as num?)?.toInt() ?? 0,
              'typeConfigJson': jsonEncode({
                'runtimeType': 'choice',
                'allowsMultiple': r['field_type'] == 'multiselect',
                'options': [
                  for (var i = 0; i < options.length; i++)
                    {
                      'id': stableId(id as String, options[i]),
                      'label': options[i],
                      'sortOrder': i,
                    },
                ],
              }),
            },
          ];
        }
        const types = {'text': 0, 'markdown': 3, 'color': 1, 'date': 2};
        if (!types.containsKey(r['field_type'])) return [];
        return [
          {
            'id': id,
            'name': r['name'],
            'fieldType': types[r['field_type']],
            'datePrecision': {
              'day': 0,
              'month_day': 2,
              'month': 3,
              'year': 4,
            }[r['date_precision']],
            'displayOrder': (r['sort_order'] as num?)?.toInt() ?? 0,
            'createdAt': created,
          },
        ];
      case 'custom_field_values':
        if (r['subject_type'] != 'member' || r['value'] is! String) return [];
        return [
          {
            'id': id,
            'customFieldId': r['field_id'],
            'memberId': r['subject_id'],
            'value': r['value'],
          },
        ];
      case 'chat.conversations':
        if (![
          'internal_chat',
          'direct_message',
          'unknown',
        ].contains(r['kind'])) {
          return [];
        }
        return [
          {
            'id': id,
            'createdAt': created,
            'lastActivityAt': created,
            'title': r['title'],
            'emoji': r['emoji'],
            'description': r['description'],
            'creatorId': r['creator_member_id'],
            'participantIds': r['participant_member_ids'] ?? [],
            'includesAllMembers':
                (r['participant_member_ids'] as List? ?? []).isEmpty,
            'isDirectMessage':
                r['direct_message'] == true || r['kind'] == 'direct_message',
            'archivedForEveryone': r['archived'] == true,
            'displayOrder': (r['sort_order'] as num?)?.toInt() ?? 0,
          },
        ];
      case 'chat.messages':
        return [
          {
            'id': id,
            'conversationId': r['conversation_id'],
            'authorId': r['author_member_id'],
            'content': r['body'],
            'timestamp': created,
            'editedAt': r['edited_at'],
            'replyToId': r['reply_to_message_id'],
            'isSystemMessage': r['system_message'] == true,
          },
        ];
      case 'boards.posts':
        return [
          {
            'id': id,
            'targetMemberId': r['target_member_id'],
            'authorId': r['author_member_id'],
            'title': r['title'],
            'body': r['body'],
            'createdAt': created,
            'writtenAt': time(r['written_at'], fallback: created),
            'editedAt': r['edited_at'],
            'audience': r['audience'] == 'public' ? 'public' : 'private',
            'isDeleted': r['deleted_at'] != null,
          },
        ];
    }
    return [];
  }

  static void _validateReferences(Json doc) {
    final sets = <String, Set<String>>{
      for (final path in recordPaths)
        path: rows(doc, path).map((r) => r['id'] as String).toSet(),
    };
    for (final path in recordPaths) {
      for (final record in rows(doc, path)) {
        for (final key in record.keys) {
          final target = coreReferenceTarget(path, record, key);
          if (target == null || record[key] == null) continue;
          final refs = record[key] is List
              ? record[key] as List
              : [record[key]];
          for (final ref in refs) {
            if (ref is! String || !sets[target]!.contains(ref)) {
              throw FormatException('Unresolved $key.');
            }
          }
        }
        if (path == 'front_periods' || path == 'front_events') {
          final assignments = record['assignments'];
          if (assignments is! List ||
              (path == 'front_periods' && assignments.isEmpty)) {
            throw FormatException(
              path == 'front_periods'
                  ? 'Front periods need member assignments; memberless sleep belongs in extensions.'
                  : 'Front events need an assignments array.',
            );
          }
          for (final assignment in assignments) {
            if (assignment is! Map ||
                assignment['member_id'] is! String ||
                !sets['members']!.contains(assignment['member_id'])) {
              throw const FormatException(
                'Unresolved front assignment member_id.',
              );
            }
          }
        }
      }
    }
    for (final assignment in rows(doc, 'taxonomy_assignments')) {
      for (final key in ['term_id', 'subject_type', 'subject_id']) {
        final value = assignment[key];
        if (value is! String || value.isEmpty) {
          throw FormatException('Taxonomy assignments need a $key.');
        }
      }
    }
    for (final entry in {
      'groups': 'parent_group_id',
      'systems': 'parent_system_id',
      'taxonomy_terms': 'parent_term_id',
    }.entries) {
      final parents = {
        for (final r in rows(doc, entry.key)) r['id']: r[entry.value],
      };
      final complete = <dynamic>{};
      for (final id in parents.keys) {
        final visiting = <dynamic>{};
        dynamic cursor = id;
        while (cursor != null && !complete.contains(cursor)) {
          if (!visiting.add(cursor)) {
            throw FormatException('Cycle in ${entry.key} hierarchy.');
          }
          cursor = parents[cursor];
        }
        complete.addAll(visiting);
      }
    }
    for (final p in rows(doc, 'front_periods')) {
      final start = DateTime.parse(time(p['started_at']));
      if (p['ended_at'] != null &&
          DateTime.parse(time(p['ended_at'])).isBefore(start)) {
        throw const FormatException('Front period ends before it starts.');
      }
    }
  }
}

class PluralPortImportPlan {
  PluralPortImportPlan(this.native, this.archive, this.warnings);
  final Json native;
  final Json archive;
  final List<String> warnings;
  int get records => PluralPortMapper.collections.values.fold(
    0,
    (n, key) => n + (native[key] as List).length,
  );
}
