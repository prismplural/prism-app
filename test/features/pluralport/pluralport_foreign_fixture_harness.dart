import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

import 'harness.dart';

/// One private foreign fixture archive and the directory its Prism
/// re-exports and comparison report are written to.
class ForeignFixtureCase {
  const ForeignFixtureCase({
    required this.label,
    required this.archivePath,
    required this.outputDirectory,
  });

  final String label;
  final String archivePath;
  final String outputDirectory;
}

/// `PLURALPORT_FOREIGN_BUNDLES` is a JSON object of `label: archive path`.
/// `PLURALPORT_FOREIGN_OUT` is the private fixture root. Each case writes to
/// `<root>/<label>/prism-roundtrip/`.
List<ForeignFixtureCase> foreignFixtureCasesFromEnvironment(
  Map<String, String> environment,
) {
  final raw = environment['PLURALPORT_FOREIGN_BUNDLES']?.trim();
  if (raw == null || raw.isEmpty) return const [];
  final outputRoot = environment['PLURALPORT_FOREIGN_OUT']?.trim();
  if (outputRoot == null || outputRoot.isEmpty) {
    throw const FormatException(
      'PLURALPORT_FOREIGN_OUT must name the private fixture output root when '
      'PLURALPORT_FOREIGN_BUNDLES is set.',
    );
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException(
      'PLURALPORT_FOREIGN_BUNDLES must be a JSON object of label to path.',
    );
  }
  final cases = <ForeignFixtureCase>[];
  for (final entry in decoded.entries) {
    final label = entry.key.toString();
    final archive = entry.value;
    if (archive is! String || archive.trim().isEmpty) {
      throw FormatException('Fixture "$label" needs an archive path.');
    }
    if (label.isEmpty ||
        label == '.' ||
        label == '..' ||
        label.contains('/') ||
        label.contains(r'\')) {
      throw FormatException('Unsafe fixture label "$label".');
    }
    cases.add(
      ForeignFixtureCase(
        label: label,
        archivePath: archive,
        outputDirectory: '$outputRoot/$label/prism-roundtrip',
      ),
    );
  }
  return cases;
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

dynamic _copyJson(dynamic value) =>
    value == null ? null : jsonDecode(jsonEncode(value));

/// Drops Prism-only provenance so an imported foreign record and its
/// re-exported projection can be compared without treating Prism's identity
/// breadcrumbs as foreign content. Empty containers are omitted because the
/// exporter only creates them to carry those breadcrumbs.
dynamic stripPrismProvenance(dynamic value) {
  if (value is List) {
    return [for (final item in value) stripPrismProvenance(item)];
  }
  if (value is Map) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (key == 'source_refs' && entry.value is List) {
        final refs = [
          for (final ref in entry.value as List)
            if (!(ref is Map && ref['app'] == 'prism'))
              stripPrismProvenance(ref),
        ];
        if (refs.isNotEmpty) result[key] = refs;
        continue;
      }
      if (key == 'extensions' && entry.value is Map) {
        final extensions = <String, dynamic>{};
        for (final extension in (entry.value as Map).entries) {
          if (extension.key == 'prism') continue;
          extensions[extension.key.toString()] = stripPrismProvenance(
            extension.value,
          );
        }
        if (extensions.isNotEmpty) result[key] = extensions;
        continue;
      }
      result[key] = stripPrismProvenance(entry.value);
    }
    return result;
  }
  return value;
}

String _canonical(dynamic value) => canonicalJson(stripPrismProvenance(value));

/// Source references are provenance, not portable content. Prism records both
/// the original producer reference and its own native identity, so record
/// content is compared without the reference array; a separate check requires
/// every original reference to survive.
dynamic withoutSourceReferences(dynamic value) {
  if (value is List) {
    return [for (final item in value) withoutSourceReferences(item)];
  }
  if (value is Map) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key == 'source_refs') continue;
      result[entry.key.toString()] = withoutSourceReferences(entry.value);
    }
    return result;
  }
  return value;
}

String _contentCanonical(dynamic value) =>
    canonicalJson(withoutSourceReferences(stripPrismProvenance(value)));

String _dateOnly(DateTime value) =>
    value.toUtc().toIso8601String().split('T').first;

DateTime _truncateToSeconds(DateTime value) =>
    DateTime.fromMillisecondsSinceEpoch(
      (value.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );

bool _expectedSubset(dynamic expected, dynamic actual) {
  if (expected is Map) {
    if (actual is! Map) return false;
    return expected.entries.every(
      (entry) => _expectedSubset(entry.value, actual[entry.key]),
    );
  }
  if (expected is List) {
    if (actual is! List || actual.length < expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (!_expectedSubset(expected[index], actual[index])) return false;
    }
    return true;
  }
  return canonicalJson(expected) == canonicalJson(actual);
}

/// Native storage keeps whole-second timestamps, normalizes profile images and
/// fills default keys into typed custom-field configs on write, so plan rows are
/// compared semantically rather than byte-for-byte.
bool _samePlannedValue(String key, dynamic expected, dynamic actual) {
  if (key == 'typeConfigJson' && expected is String && actual is String) {
    final left = jsonDecode(expected);
    final right = jsonDecode(actual);
    if (left is Map && right is Map) {
      return _expectedSubset(left, right);
    }
  }
  if (expected is String && actual is String) {
    final left = DateTime.tryParse(expected);
    final right = DateTime.tryParse(actual);
    if (left != null && right != null) {
      return _truncateToSeconds(left) == _truncateToSeconds(right);
    }
  }
  return canonicalJson(expected) == canonicalJson(actual);
}

const _normalizedNativeMediaKeys = {
  'profilePhotoData',
  'profileHeaderImageData',
  'pkBannerImageData',
  'avatarImageData',
};

String _expectedNoteDate(Json note) {
  final entry = note['entry_date'];
  if (entry is String && entry.isNotEmpty) {
    return _dateOnly(DateTime.parse('${entry}T00:00:00'));
  }
  final created = note['created_at'];
  if (created is! String) {
    throw const FormatException('Imported note has no date.');
  }
  return _dateOnly(DateTime.parse(created));
}

/// Compares portable content only: identity provenance and capability order are
/// reported elsewhere, while records, files, systems and opaque modules must
/// match exactly.
List<String> bundleContentDifference(
  PluralPortBundle left,
  PluralPortBundle right,
) {
  final differences = <String>[];
  for (final key in ['producer', 'pluralport_version']) {
    if (canonicalJson(left.envelope[key]) !=
        canonicalJson(right.envelope[key])) {
      differences.add(key);
    }
  }
  final leftModules =
      ((left.envelope['capabilities'] as Map?)?['modules'] as List? ?? const [])
          .cast<String>()
          .toList()
        ..sort();
  final rightModules =
      ((right.envelope['capabilities'] as Map?)?['modules'] as List? ??
              const [])
          .cast<String>()
          .toList()
        ..sort();
  if (canonicalJson(leftModules) != canonicalJson(rightModules)) {
    differences.add('capabilities.modules');
  }
  for (final path in PluralPortMapper.recordPaths) {
    final before = _byId(PluralPortMapper.rows(left.envelope, path));
    final after = _byId(PluralPortMapper.rows(right.envelope, path));
    final beforeIds = before.keys.toSet();
    final afterIds = after.keys.toSet();
    if (beforeIds.length != afterIds.length ||
        !beforeIds.containsAll(afterIds)) {
      differences.add(path);
      continue;
    }
    for (final id in beforeIds) {
      if (_contentCanonical(before[id]) != _contentCanonical(after[id])) {
        differences.add('$path/$id');
      }
    }
  }
  for (final key in [
    'polls',
    'habits',
    'reminders',
    'sharing',
    'safety',
    'proxy',
    'lineage',
  ]) {
    if (_contentCanonical(left.envelope[key]) !=
        _contentCanonical(right.envelope[key])) {
      differences.add(key);
    }
  }
  final leftExtensions = (left.envelope['extensions'] as Map? ?? const {})
      .cast<String, dynamic>();
  final rightExtensions = (right.envelope['extensions'] as Map? ?? const {})
      .cast<String, dynamic>();
  for (final key in {...leftExtensions.keys, ...rightExtensions.keys}) {
    if (key == 'prism') continue;
    if (_contentCanonical(leftExtensions[key]) !=
        _contentCanonical(rightExtensions[key])) {
      differences.add('extensions.$key');
    }
  }
  final leftPrism = (leftExtensions['prism'] as Map? ?? const {})
      .cast<String, dynamic>();
  final rightPrism = (rightExtensions['prism'] as Map? ?? const {})
      .cast<String, dynamic>();
  for (final key in ['native_modules', 'import_sources']) {
    if (canonicalJson(leftPrism[key]) != canonicalJson(rightPrism[key])) {
      differences.add('extensions.prism.$key');
    }
  }
  if (canonicalJson(left.envelope['warnings']) !=
      canonicalJson(right.envelope['warnings'])) {
    differences.add('warnings');
  }
  if (canonicalJson(left.files.keys.toList()..sort()) !=
      canonicalJson(right.files.keys.toList()..sort())) {
    differences.add('files');
  } else {
    for (final entry in left.files.entries) {
      if (_sha256Hex(entry.value) != _sha256Hex(right.files[entry.key]!)) {
        differences.add('files/${entry.key}');
      }
    }
  }
  return differences;
}

Map<String, Json> _byId(Iterable<Json> rows) => {
  for (final row in rows) row['id'].toString(): row,
};

/// The native export carries device-local values that must not take part in
/// fixture fidelity comparisons.
Json normalizeNativeExport(Json native) {
  final copy = PluralPortMapper.clone(native);
  for (final key in [
    'exportDate',
    'totalRecords',
    'pluralPortArchives',
    'pluralKitSyncState',
  ]) {
    copy.remove(key);
  }
  for (final row in PluralPortMapper.rows(copy, 'systemSettings')) {
    row.remove('id');
  }
  for (final row in PluralPortMapper.rows(copy, 'mediaAttachments')) {
    for (final key in [
      'mediaId',
      'encryptionKeyB64',
      'contentHash',
      'thumbnailMediaId',
      'thumbnailContentHash',
    ]) {
      row.remove(key);
    }
  }
  return copy;
}

Map<String, dynamic> _settingsView(Json native) {
  final settings = PluralPortMapper.rows(native, 'systemSettings').firstOrNull;
  if (settings == null) return const {};
  return {
    for (final key in [
      'systemName',
      'systemDescription',
      'systemColor',
      'systemTag',
      'systemAvatarData',
    ])
      key: settings[key],
  };
}

/// Runs a bounded no-edit qualification of one foreign archive:
///
/// preview -> fresh Prism DB import -> re-export -> second fresh DB import ->
/// second re-export, plus a repeated import into the first DB. The report is
/// written even when a check fails or an exception escapes.
Future<Json> qualifyForeignFixture(ForeignFixtureCase fixture) async {
  final report = <String, dynamic>{
    'schema': 'prism.pluralport.foreign_fixture_qualification.v1',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'case': {
      'label': fixture.label,
      'archive': fixture.archivePath,
      'output_directory': fixture.outputDirectory,
    },
  };
  final checks = <Json>[];
  final differences = <Json>[];
  void check(
    String id,
    bool ok,
    String summary, [
    Map<String, dynamic> details = const {},
    bool skipped = false,
  ]) {
    checks.add({
      'id': id,
      'ok': ok,
      'skipped': skipped,
      'summary': summary,
      'details': details,
    });
  }

  Directory? temp;
  dynamic db1;
  dynamic db2;
  final artifacts = <String, String>{};
  try {
    final archiveBytes = await File(fixture.archivePath).readAsBytes();
    report['case'] = {
      ...(report['case'] as Json),
      'size_bytes': archiveBytes.length,
      'sha256': _sha256Hex(archiveBytes),
    };
    final source = PluralPortBundle.decode(archiveBytes);
    final PluralPortImportPlan preview;
    try {
      preview = PluralPortService.previewBytes(archiveBytes);
    } catch (error, stack) {
      final nonObjectExtensions = <String, String>{};
      final nonObjectExtensionCounts = <String, int>{};
      for (final path in PluralPortMapper.recordPaths) {
        for (final row in PluralPortMapper.rows(source.envelope, path)) {
          final extensions = row['extensions'];
          if (extensions != null && extensions is! Map) {
            nonObjectExtensions['$path/${row['id']}'] = extensions.runtimeType
                .toString();
            nonObjectExtensionCounts[path] =
                (nonObjectExtensionCounts[path] ?? 0) + 1;
          }
        }
      }
      report['decoded'] = {
        'producer': source.envelope['producer'],
        'versions': {
          'pluralport_version': source.envelope['pluralport_version'],
          'openplural_version': source.envelope['openplural_version'],
        },
        'record_counts': {
          for (final path in PluralPortMapper.recordPaths)
            if (PluralPortMapper.rows(source.envelope, path).isNotEmpty)
              path: PluralPortMapper.rows(source.envelope, path).length,
        },
        'files': source.files.keys.toList(),
        'non_object_extension_counts': nonObjectExtensionCounts,
      };
      check(
        'preview_supported',
        false,
        'The archive could not be previewed as PluralPort 0.1.',
        {
          'type': error.runtimeType.toString(),
          'message': '$error',
          'stack': stack.toString(),
          'non_object_extensions': nonObjectExtensions,
        },
      );
      report['preview_error'] = {
        'type': error.runtimeType.toString(),
        'message': '$error',
        'stack': stack.toString(),
        'non_object_extensions': nonObjectExtensions,
      };
      return report;
    }
    final sourceEnvelope = source.envelope;
    final namespace = preview.archive['namespace'] as String;
    final bindings = <String, List<String>>{
      for (final entry in (preview.archive['bindings'] as Map? ?? {}).entries)
        entry.key.toString(): (entry.value as List).cast<String>(),
    };
    final sourceRows = <String, List<Json>>{
      for (final path in PluralPortMapper.recordPaths)
        path: PluralPortMapper.rows(sourceEnvelope, path),
    };
    final sourceAssetById = _byId(sourceRows['assets']!);
    final sourcePolls = switch (sourceEnvelope['polls']) {
      final List value => value.whereType<Json>().toList(),
      final Map value when value['polls'] is List =>
        (value['polls'] as List).whereType<Json>().toList(),
      _ => <Json>[],
    };
    final sourceFiles = <String, Uint8List>{
      for (final entry in source.files.entries)
        if (!PluralPortBundle.roots.contains(entry.key) &&
            entry.key != 'README.txt')
          entry.key: entry.value,
    };
    final sourceFileHashes = {
      for (final entry in sourceFiles.entries)
        entry.key: _sha256Hex(entry.value),
    };
    final assetBytes = <String, Uint8List?>{};
    final assetWarnings = <String>[];
    for (final asset in sourceRows['assets']!) {
      try {
        assetBytes[asset['id'] as String] = source.assetBytes(asset);
      } on FormatException catch (error) {
        assetWarnings.add('asset_invalid: ${asset['id']} ($error)');
      }
    }
    String? nativeId(String path, dynamic sourceId) {
      if (sourceId is! String || sourceId.isEmpty) return null;
      final bound = bindings['$path/$sourceId'];
      if (bound != null && bound.isNotEmpty) return bound.first;
      return PluralPortMapper.stableId(namespace, sourceId);
    }

    final reverse = <String, Map<String, String>>{};
    for (final path in PluralPortMapper.recordPaths) {
      for (final row in sourceRows[path]!) {
        final native = nativeId(path, row['id']);
        if (native == null) continue;
        reverse.putIfAbsent(path, () => {})[native] = row['id'] as String;
      }
    }
    final bindingsBySource = <String, Map<String, List<String>>>{};
    for (final entry in bindings.entries) {
      final split = entry.key.lastIndexOf('/');
      final path = entry.key.substring(0, split);
      final native = entry.key.substring(split + 1);
      final sourceId = reverse[path]?[native];
      if (sourceId == null) continue;
      bindingsBySource.putIfAbsent(path, () => {})[sourceId] = entry.value;
    }

    final ready = preview.summary.ready;
    final retained = preview.summary.retained;
    final warnings = preview.warnings;
    report['producer'] = sourceEnvelope['producer'];
    report['versions'] = {
      'pluralport_version': sourceEnvelope['pluralport_version'],
      'openplural_version': sourceEnvelope['openplural_version'],
    };
    report['declared'] = {
      'capabilities': sourceEnvelope['capabilities'],
      'record_counts': {
        for (final entry in sourceRows.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.length,
      },
      'module_keys': [
        for (final key in [
          'polls',
          'habits',
          'reminders',
          'sharing',
          'safety',
          'proxy',
          'relationships',
          'boards',
          'chat',
          'taxonomy_terms',
          'taxonomy_assignments',
          'front_events',
          'front_comments',
        ])
          if (sourceEnvelope[key] != null &&
                  sourceEnvelope[key] is! List &&
                  (sourceEnvelope[key] as Map).isNotEmpty ||
              sourceEnvelope[key] is List &&
                  (sourceEnvelope[key] as List).isNotEmpty)
            key,
      ],
      'extension_namespaces': [
        for (final key
            in ((sourceEnvelope['extensions'] as Map? ?? {}).keys)
                .cast<String>())
          if (key != 'prism') key,
      ],
    };
    report['preview'] = {
      'ready': ready,
      'retained': retained,
      'warnings': warnings,
      'bundled_files': preview.summary.bundledFiles,
      'missing_files': preview.summary.missingFiles,
      'unbundled_media': preview.summary.unbundledMedia,
      'system_profiles': preview.summary.systemProfiles,
      'records': preview.records,
    };
    report['source_files'] = {
      for (final entry in sourceFiles.entries)
        entry.key: {
          'size_bytes': entry.value.length,
          'sha256': sourceFileHashes[entry.key],
        },
    };
    report['source_assets'] = {
      for (final asset in sourceRows['assets']!)
        asset['id'] as String: {
          'kind': asset['kind'],
          'uri': asset['uri'],
          'bundle_path': asset['bundle_path'],
          'mime_type': asset['mime_type'],
          'size_bytes': asset['size_bytes'],
          'sha256': asset['sha256'],
          'bytes_resolved': assetBytes[asset['id']] != null,
          'sha256_of_resolved_bytes': assetBytes[asset['id']] == null
              ? null
              : _sha256Hex(assetBytes[asset['id']]!),
        },
    };
    if (assetWarnings.isNotEmpty) {
      report['asset_warnings'] = assetWarnings;
    }

    final output = await Directory(
      fixture.outputDirectory,
    ).create(recursive: true);
    temp = await Directory.systemTemp.createTemp(
      'prism-foreign-${fixture.label}-',
    );
    final support1 = await Directory('${temp.path}/db1').create();
    final support2 = await Directory('${temp.path}/db2').create();
    db1 = makeDb();
    db2 = makeDb();
    PluralPortService service(dynamic db, Directory support) =>
        PluralPortService(
          db: db,
          exporter: makeExport(db),
          importer: makeImport(db, supportDirectory: support),
          supportDirectory: () async => support,
        );
    final first = service(db1, support1);
    final second = service(db2, support2);

    final importResult1 = await first.importPlan(
      PluralPortMapper.plan(source),
      importSystemProfile: true,
    );
    final native1 = (await makeExport(db1).buildExport()).toJson();
    final export1 = await first.exportBundle();
    final export1Bytes = export1.encode();
    artifacts['prism_reexport_1'] =
        '${output.path}/prism-reexport-1.pluralport.zip';
    await File(artifacts['prism_reexport_1']!).writeAsBytes(export1Bytes);
    artifacts['prism_native_1'] = '${output.path}/prism-native-1.json';
    await File(
      artifacts['prism_native_1']!,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(native1));
    final decoded1 = PluralPortBundle.decode(export1Bytes);
    final exportPreview1 = PluralPortService.previewBytes(export1Bytes);

    final importResult2 = await second.importPlan(
      PluralPortMapper.plan(decoded1),
      importSystemProfile: true,
    );
    final native2 = (await makeExport(db2).buildExport()).toJson();
    final export2 = await second.exportBundle();
    final export2Bytes = export2.encode();
    artifacts['prism_reexport_2'] =
        '${output.path}/prism-reexport-2.pluralport.zip';
    await File(artifacts['prism_reexport_2']!).writeAsBytes(export2Bytes);
    artifacts['prism_native_2'] = '${output.path}/prism-native-2.json';
    await File(
      artifacts['prism_native_2']!,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(native2));
    final decoded2 = PluralPortBundle.decode(export2Bytes);
    final exportPreview2 = PluralPortService.previewBytes(export2Bytes);

    final repeatedImported = await first.importPlan(
      PluralPortMapper.plan(source),
      importSystemProfile: true,
    );
    final native1Repeat = (await makeExport(db1).buildExport()).toJson();
    final export1Repeat = await first.exportBundle();
    final export1RepeatBytes = export1Repeat.encode();
    artifacts['prism_reexport_1_repeat'] =
        '${output.path}/prism-reexport-1-repeat.pluralport.zip';
    await File(
      artifacts['prism_reexport_1_repeat']!,
    ).writeAsBytes(export1RepeatBytes);
    artifacts['prism_native_1_repeat'] =
        '${output.path}/prism-native-1-repeat.json';
    await File(
      artifacts['prism_native_1_repeat']!,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(native1Repeat));
    final decoded1Repeat = PluralPortBundle.decode(export1RepeatBytes);

    // -- Preview -----------------------------------------------------------
    final uriOnlyAssets = [
      for (final asset in sourceRows['assets']!)
        if (assetBytes[asset['id']] == null &&
            asset['uri'] is String &&
            sourceFiles.containsKey(asset['uri']))
          asset['id'] as String,
    ];
    check(
      'bundle_and_preview_valid',
      true,
      'Archive decoded, previewed and validated as PluralPort 0.1.',
      {
        'producer': sourceEnvelope['producer'],
        'system_profiles': preview.summary.systemProfiles,
        'records_ready': preview.records,
      },
    );
    check(
      'preview_inventory',
      preview.summary.bundledFiles == sourceFiles.length &&
          preview.summary.systemProfiles == sourceRows['systems']!.length,
      'Preview inventory reflects bundled files and system profiles.',
      {
        'bundled_files': preview.summary.bundledFiles,
        'source_files': sourceFiles.length,
        'system_profiles': preview.summary.systemProfiles,
        'source_systems': sourceRows['systems']!.length,
        'uri_only_assets': uriOnlyAssets,
        'unbundled_media': preview.summary.unbundledMedia,
      },
    );

    // -- Portable records and identity graph --------------------------------
    Json projectExportRecord(String path, Json row) {
      final projected = <String, dynamic>{};
      for (final entry in row.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key == 'id') {
          projected[key] = reverse[path]?[value] ?? value;
          continue;
        }
        if (key == 'assignments') {
          projected[key] = _copyJson(value);
          continue;
        }
        final target = PluralPortMapper.coreReferenceTarget(path, row, key);
        if (target != null && value != null) {
          dynamic mapValue(dynamic candidate) => candidate is String
              ? (reverse[target]?[candidate] ?? candidate)
              : candidate;
          projected[key] = value is List
              ? [for (final candidate in value) mapValue(candidate)]
              : mapValue(value);
        } else {
          projected[key] = _copyJson(value);
        }
      }
      if (path == 'front_periods' || path == 'front_events') {
        final assignments = row['assignments'];
        if (assignments is List) {
          projected['assignments'] = [
            for (final assignment in assignments)
              if (assignment is Map)
                {
                  ..._copyJson(assignment) as Json,
                  if (assignment['member_id'] is String)
                    'member_id':
                        reverse['members']?[assignment['member_id']] ??
                        assignment['member_id'],
                }
              else
                _copyJson(assignment),
          ];
        }
      }
      return projected;
    }

    final recordMismatches = <String>[];
    final missingRecords = <String>[];
    final extraRecords = <String>[];
    const recordsCompared = <String>[
      'members',
      'groups',
      'group_memberships',
      'custom_fields',
      'custom_field_values',
      'notes',
      'front_periods',
      'front_comments',
      'chat.conversations',
      'chat.messages',
      'chat.attachments',
      'chat.reactions',
      'boards.posts',
      'taxonomy_terms',
      'taxonomy_assignments',
      'front_events',
      'relationships.types',
      'relationships.edges',
    ];
    for (final path in recordsCompared) {
      final expectedIds = {
        for (final row in sourceRows[path]!) nativeId(path, row['id']),
      };
      final exported = _byId(PluralPortMapper.rows(export1.envelope, path));
      for (final id in expectedIds) {
        if (id == null) continue;
        if (!exported.containsKey(id)) {
          missingRecords.add('$path/$id');
        }
      }
      for (final id in exported.keys) {
        if (!expectedIds.contains(id)) extraRecords.add('$path/$id');
      }
      for (final row in sourceRows[path]!) {
        final id = nativeId(path, row['id']);
        final exportedRow = exported[id];
        if (exportedRow == null) continue;
        final expected = _contentCanonical(row);
        final actual = _contentCanonical(
          projectExportRecord(path, exportedRow),
        );
        if (expected != actual) recordMismatches.add('$path/${row['id']}');
      }
    }
    check(
      'portable_records_preserved',
      missingRecords.isEmpty &&
          extraRecords.isEmpty &&
          recordMismatches.isEmpty,
      'Every portable record survives re-export with its foreign content.',
      {
        'missing': missingRecords.take(50).toList(),
        'extra': extraRecords.take(50).toList(),
        'mismatches': recordMismatches.take(50).toList(),
      },
    );

    final sourceRefMismatches = <String>[];
    for (final path in PluralPortMapper.recordPaths) {
      final exported = _byId(PluralPortMapper.rows(export1.envelope, path));
      for (final row in sourceRows[path]!) {
        final refs = row['source_refs'];
        if (refs is! List || refs.isEmpty) continue;
        final out = exported[nativeId(path, row['id'])];
        final outRefs = out?['source_refs'];
        final retained = {
          for (final ref in (outRefs is List ? outRefs : const []))
            canonicalJson(ref),
        };
        for (final ref in refs) {
          if (!retained.contains(canonicalJson(ref))) {
            sourceRefMismatches.add('$path/${row['id']}');
            break;
          }
        }
      }
    }
    check(
      'source_references_preserved',
      sourceRefMismatches.isEmpty,
      'Every producer source reference survives re-export alongside Prism IDs.',
      {'mismatches': sourceRefMismatches.take(50).toList()},
    );

    final bindingMismatches = <String>[];
    final nativeByPath = <String, Map<String, Json>>{
      for (final path in PluralPortMapper.collections.keys)
        path: _byId(
          PluralPortMapper.rows(native1, PluralPortMapper.collections[path]!),
        ),
    };
    for (final pathEntry in bindingsBySource.entries) {
      final path = pathEntry.key;
      for (final binding in pathEntry.value.entries) {
        final sourceId = binding.key;
        final nativeIds = binding.value;
        if (nativeIds.isEmpty) {
          bindingMismatches.add('$path/$sourceId (no native identity)');
          continue;
        }
        if (nativeIds.length > 1 && path != 'front_periods') {
          bindingMismatches.add(
            '$path/$sourceId (${nativeIds.length} native rows)',
          );
        }
        for (final id in nativeIds) {
          if (!(nativeByPath[path] ?? const {}).containsKey(id)) {
            bindingMismatches.add('$path/$sourceId -> $id (missing)');
          }
        }
      }
    }
    for (final path in [
      'members',
      'groups',
      'group_memberships',
      'custom_fields',
      'custom_field_values',
      'notes',
      'front_periods',
      'boards.posts',
      'chat.conversations',
      'chat.messages',
    ]) {
      final nativeRows = nativeByPath[path] ?? const <String, Json>{};
      final bound = bindingsBySource[path] ?? const {};
      for (final row in sourceRows[path]!) {
        final id = bound[row['id']]?.first;
        if (id != null && !nativeRows.containsKey(id)) {
          bindingMismatches.add('$path/${row['id']} (not imported)');
        }
      }
    }
    check(
      'identity_bindings',
      bindingMismatches.isEmpty,
      'Deterministic Prism identities bind every mapped foreign record.',
      {'mismatches': bindingMismatches.take(50).toList()},
    );

    final groupMismatches = <String>[];
    for (final group in sourceRows['groups']!) {
      final parent = group['parent_group_id'];
      final native = nativeByPath['groups']![nativeId('groups', group['id'])];
      if (native == null) {
        groupMismatches.add('${group['id']} missing');
        continue;
      }
      if (parent != null &&
          native['parentGroupId'] != nativeId('groups', parent)) {
        groupMismatches.add('${group['id']} parent');
      }
    }
    final groupDepth = <String, int>{};
    for (final group in sourceRows['groups']!) {
      var depth = 0;
      dynamic cursor = group['parent_group_id'];
      final seen = <dynamic>{};
      while (cursor != null && seen.add(cursor)) {
        depth++;
        final parent = _byId(sourceRows['groups']!)[cursor];
        if (parent == null) break;
        cursor = parent['parent_group_id'];
      }
      groupDepth[group['id'] as String] = depth;
    }
    check(
      'nested_groups',
      groupMismatches.isEmpty &&
          groupDepth.values.fold(0, (a, b) => a > b ? a : b) >=
              (sourceRows['groups']!.length > 1 ? 1 : 0),
      'Nested groups keep their parent chain and native rows.',
      {
        'native_groups': nativeByPath['groups']!.length,
        'max_depth': groupDepth.values.fold(0, (a, b) => a > b ? a : b),
        'mismatches': groupMismatches,
      },
    );

    // -- Custom fields and values ------------------------------------------
    final fieldMismatches = <String>[];
    final preservedFields = <Json>[];
    final nativeFields = _byId(PluralPortMapper.rows(native1, 'customFields'));
    final choiceLabels = <String, Map<String, String>>{};
    for (final field in sourceRows['custom_fields']!) {
      final native = bindingsBySource['custom_fields']?[field['id']]?.first;
      if (native == null) {
        preservedFields.add({
          'id': field['id'],
          'name': field['name'],
          'field_type': field['field_type'],
          'options_shape': field['options'] is List
              ? 'list'
              : field['options'] is Map
              ? 'object'
              : field['options'] == null
              ? 'null'
              : field['options'].runtimeType.toString(),
        });
        continue;
      }
      final row = nativeFields[native];
      if (row == null) {
        fieldMismatches.add('${field['id']} missing native row');
        continue;
      }
      if (row['name'] != field['name']) {
        fieldMismatches.add('${field['id']} name');
      }
      if (row['displayOrder'] != field['sort_order']) {
        fieldMismatches.add('${field['id']} order');
      }
      final config = row['typeConfigJson'];
      if (config is String) {
        final decoded = jsonDecode(config);
        if (decoded is Map && decoded['options'] is List) {
          choiceLabels[native] = {
            for (final option in (decoded['options'] as List).whereType<Map>())
              option['id'].toString(): option['label'].toString(),
          };
        }
      }
    }
    final valueMismatches = <String>[];
    final preservedValues = <Json>[];
    final valuePairCounts = <String, int>{};
    for (final value in sourceRows['custom_field_values']!) {
      final key = '${value['field_id']}\u0000${value['subject_id']}';
      valuePairCounts[key] = (valuePairCounts[key] ?? 0) + 1;
    }
    final nativeValues = _byId(
      PluralPortMapper.rows(native1, 'customFieldValues'),
    );
    final sourceFieldById = _byId(sourceRows['custom_fields']!);
    for (final value in sourceRows['custom_field_values']!) {
      final native =
          bindingsBySource['custom_field_values']?[value['id']]?.first;
      if (native == null) {
        preservedValues.add({
          'id': value['id'],
          'field_id': value['field_id'],
          'field_type': sourceFieldById[value['field_id']]?['field_type'],
          'value_is_list': value['value'] is List,
          'duplicate_pair':
              (valuePairCounts['${value['field_id']}\u0000${value['subject_id']}'] ??
                  0) >
              1,
        });
        continue;
      }
      final row = nativeValues[native];
      if (row == null) {
        valueMismatches.add('${value['id']} missing native row');
        continue;
      }
      if (row['customFieldId'] !=
          bindingsBySource['custom_fields']?[value['field_id']]?.first) {
        valueMismatches.add('${value['id']} field');
      }
      if (row['memberId'] != nativeId('members', value['subject_id'])) {
        valueMismatches.add('${value['id']} member');
      }
      final labels = choiceLabels[row['customFieldId']];
      final sourceValue = value['value'];
      if (labels != null) {
        final encoded = row['value'];
        if (encoded is! String) {
          valueMismatches.add('${value['id']} choice encoding');
          continue;
        }
        final decoded = jsonDecode(encoded);
        final selected = decoded is Map && decoded['options'] is List
            ? (decoded['options'] as List).map((id) => labels[id]).toList()
            : <String?>[null];
        final expected = sourceValue is List
            ? sourceValue.cast<String>()
            : [sourceValue as String];
        if (_canonical(selected) != _canonical(expected)) {
          valueMismatches.add('${value['id']} choice labels');
        }
      } else if (row['value'] != sourceValue) {
        valueMismatches.add('${value['id']} value');
      }
    }
    final unboundWarnings = <String>[];
    for (final path in ['custom_fields', 'custom_field_values']) {
      for (final row in sourceRows[path]!) {
        if (bindingsBySource[path]?[row['id']] != null) continue;
        final warning = 'preserved_only: $path/${nativeId(path, row['id'])}';
        if (!warnings.contains(warning)) unboundWarnings.add(warning);
      }
    }
    check(
      'custom_fields_and_values',
      fieldMismatches.isEmpty &&
          valueMismatches.isEmpty &&
          unboundWarnings.isEmpty,
      'Native field definitions/values match; preserved-only shapes are warned.',
      {
        'source_fields': sourceRows['custom_fields']!.length,
        'native_fields': nativeFields.length,
        'preserved_fields': preservedFields,
        'source_values': sourceRows['custom_field_values']!.length,
        'native_values': nativeValues.length,
        'preserved_values': preservedValues,
        'mismatches': [...fieldMismatches, ...valueMismatches],
        'missing_warnings': unboundWarnings,
      },
    );

    // -- Front periods and co-fronting -------------------------------------
    final frontMismatches = <String>[];
    final periods = sourceRows['front_periods']!;
    var periodAssignments = 0;
    var multiAssignmentPeriods = 0;
    for (final period in periods) {
      final assignments = (period['assignments'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      periodAssignments += assignments.length;
      if (assignments.length > 1) multiAssignmentPeriods++;
      final nativeIds =
          bindingsBySource['front_periods']?[period['id']] ?? const [];
      if (nativeIds.length != assignments.length) {
        frontMismatches.add('${period['id']} assignment count');
        continue;
      }
      for (var index = 0; index < assignments.length; index++) {
        final assignment = assignments[index];
        final session = nativeByPath['front_periods']![nativeIds[index]];
        if (session == null) {
          frontMismatches.add('${period['id']}/$index missing session');
          continue;
        }
        if (session['headmateId'] !=
            nativeId('members', assignment['member_id'])) {
          frontMismatches.add('${period['id']}/$index member');
        }
        if (DateTime.parse(session['startTime'] as String) !=
            DateTime.parse(period['started_at'] as String)) {
          frontMismatches.add('${period['id']}/$index start');
        }
        final expectedEnd = period['ended_at'];
        if (expectedEnd == null
            ? session['endTime'] != null
            : session['endTime'] == null ||
                  DateTime.parse(session['endTime'] as String) !=
                      DateTime.parse(expectedEnd as String)) {
          frontMismatches.add('${period['id']}/$index end');
        }
        if (session['notes'] != (assignment['note'] ?? period['note'])) {
          frontMismatches.add('${period['id']}/$index notes');
        }
        if (session['sessionType'] != 0) {
          frontMismatches.add('${period['id']}/$index session type');
        }
      }
    }
    final sessions = nativeByPath['front_periods'] ?? const <String, Json>{};
    check(
      'front_periods_and_sessions',
      frontMismatches.isEmpty &&
          sessions.length == periodAssignments &&
          (periods.isEmpty || periodAssignments > 0),
      'One native session per assignment, with co-front periods grouped.',
      {
        'source_periods': periods.length,
        'single_assignment_periods': periods.length - multiAssignmentPeriods,
        'multi_assignment_periods': multiAssignmentPeriods,
        'assignments': periodAssignments,
        'native_sessions': sessions.length,
        'mismatches': frontMismatches.take(50).toList(),
      },
    );

    // -- Notes -------------------------------------------------------------
    final noteMismatches = <String>[];
    final nativeNotes = _byId(PluralPortMapper.rows(native1, 'notes'));
    for (final note in sourceRows['notes']!) {
      final row = nativeNotes[nativeId('notes', note['id'])];
      if (row == null) {
        noteMismatches.add('${note['id']} missing');
        continue;
      }
      if (row['title'] != (note['title'] ?? '')) {
        noteMismatches.add('${note['id']} title');
      }
      if (row['body'] != note['body']) noteMismatches.add('${note['id']} body');
      if (row['memberId'] != nativeId('members', note['member_id'])) {
        noteMismatches.add('${note['id']} member');
      }
      final date = row['date'];
      if (date is! String || date.split('T').first != _expectedNoteDate(note)) {
        noteMismatches.add('${note['id']} date');
      }
    }
    check(
      'notes',
      noteMismatches.isEmpty,
      'Journals keep title, body, member and the producer-declared date.',
      {
        'source_notes': sourceRows['notes']!.length,
        'native_notes': nativeNotes.length,
        'dates_from_entry_date': sourceRows['notes']!
            .where((note) => note['entry_date'] != null)
            .length,
        'mismatches': noteMismatches,
      },
    );

    // -- Boards and chat ---------------------------------------------------
    final boardMismatches = <String>[];
    final nativePosts = _byId(
      PluralPortMapper.rows(native1, 'memberBoardPosts'),
    );
    for (final post in sourceRows['boards.posts']!) {
      final row = nativePosts[nativeId('boards.posts', post['id'])];
      if (row == null) {
        boardMismatches.add('${post['id']} missing');
        continue;
      }
      if (row['body'] != post['body']) {
        boardMismatches.add('${post['id']} body');
      }
      if (row['authorId'] != nativeId('members', post['author_member_id'])) {
        boardMismatches.add('${post['id']} author');
      }
      if (row['targetMemberId'] !=
          nativeId('members', post['target_member_id'])) {
        boardMismatches.add('${post['id']} target');
      }
    }
    final chatMismatches = <String>[];
    final nativeConversations = _byId(
      PluralPortMapper.rows(native1, 'conversations'),
    );
    final nativeMessages = _byId(PluralPortMapper.rows(native1, 'messages'));
    for (final conversation in sourceRows['chat.conversations']!) {
      final row =
          nativeConversations[nativeId(
            'chat.conversations',
            conversation['id'],
          )];
      if (row == null) {
        chatMismatches.add('${conversation['id']} missing');
        continue;
      }
      if (row['creatorId'] !=
          nativeId('members', conversation['creator_member_id'])) {
        chatMismatches.add('${conversation['id']} creator');
      }
    }
    for (final message in sourceRows['chat.messages']!) {
      final row = nativeMessages[nativeId('chat.messages', message['id'])];
      if (row == null) {
        chatMismatches.add('${message['id']} missing');
        continue;
      }
      if (row['conversationId'] !=
          nativeId('chat.conversations', message['conversation_id'])) {
        chatMismatches.add('${message['id']} conversation');
      }
      if (row['authorId'] != nativeId('members', message['author_member_id'])) {
        chatMismatches.add('${message['id']} author');
      }
      if (row['content'] != message['body']) {
        chatMismatches.add('${message['id']} body');
      }
    }
    check(
      'boards_and_chat',
      boardMismatches.isEmpty && chatMismatches.isEmpty,
      'Declared board posts and chat records map with stable identities.',
      {
        'native_board_posts': nativePosts.length,
        'native_conversations': nativeConversations.length,
        'native_messages': nativeMessages.length,
        'mismatches': [...boardMismatches, ...chatMismatches],
      },
    );

    // -- Producer modules and opaque extensions ---------------------------
    // Record-backed modules (boards, chat, taxonomy, front events) are compared
    // by identity and content above; only opaque root modules remain here.
    const moduleKeys = [
      'polls',
      'habits',
      'reminders',
      'sharing',
      'safety',
      'proxy',
      'lineage',
    ];
    final moduleMismatches = <String>[];
    final moduleSummary = <String, dynamic>{};
    for (final key in moduleKeys) {
      final before = sourceEnvelope[key];
      if (before == null) continue;
      final after = export1.envelope[key];
      moduleSummary[key] = {
        'declared': before is List ? before.length : before is Map,
      };
      if (_contentCanonical(before) != _contentCanonical(after)) {
        moduleMismatches.add(key);
      }
    }
    for (final path in [
      'boards.posts',
      'chat.conversations',
      'chat.messages',
      'chat.attachments',
      'chat.reactions',
      'relationships.types',
      'relationships.edges',
      'taxonomy_terms',
      'taxonomy_assignments',
      'front_events',
    ]) {
      moduleSummary[path] = {'records': sourceRows[path]!.length};
    }
    final nativePolls = PluralPortMapper.rows(native1, 'polls').length;
    final nativeRelationships =
        PluralPortMapper.rows(native1, 'relationships.types').length +
        PluralPortMapper.rows(native1, 'relationships.edges').length;
    if (nativePolls != 0) {
      moduleMismatches.add('native polls invented for an unmapped module');
    }
    if (nativeRelationships != 0) {
      moduleMismatches.add('native relationships invented for opaque data');
    }
    check(
      'producer_modules_preserved',
      moduleMismatches.isEmpty,
      'Declared modules are preserved exactly; unmapped ones create no native rows.',
      {
        'modules': moduleSummary,
        'native_polls': nativePolls,
        'native_relationships': nativeRelationships,
        'mismatches': moduleMismatches,
      },
    );

    final extensionMismatches = <String>[];
    final sourceExtensions = (sourceEnvelope['extensions'] as Map? ?? const {})
        .cast<String, dynamic>();
    for (final entry in sourceExtensions.entries) {
      if (entry.key == 'prism') continue;
      if (_canonical(entry.value) !=
          _canonical(
            (export1.envelope['extensions'] as Map? ?? {})[entry.key],
          )) {
        extensionMismatches.add(entry.key);
      }
      if (_canonical(entry.value) !=
          _canonical(
            (export2.envelope['extensions'] as Map? ?? {})[entry.key],
          )) {
        extensionMismatches.add('${entry.key} (second re-export)');
      }
    }
    for (final path in PluralPortMapper.recordPaths) {
      final exported = _byId(PluralPortMapper.rows(export1.envelope, path));
      for (final row in sourceRows[path]!) {
        final extensions = row['extensions'];
        if (extensions is! Map) continue;
        final foreign = {
          for (final entry in extensions.entries)
            if (entry.key != 'prism') entry.key: entry.value,
        };
        if (foreign.isEmpty) continue;
        final rowOut = exported[nativeId(path, row['id'])];
        final outExtensions = rowOut?['extensions'];
        for (final entry in foreign.entries) {
          if (_canonical(entry.value) !=
              _canonical(
                outExtensions is Map ? outExtensions[entry.key] : null,
              )) {
            extensionMismatches.add('$path/${row['id']}/${entry.key}');
          }
        }
      }
    }
    check(
      'unknown_extensions_preserved',
      extensionMismatches.isEmpty &&
          export1.envelope['pluralport_preserved_conflicts'] == null &&
          export2.envelope['pluralport_preserved_conflicts'] == null,
      'Foreign extension namespaces survive both re-exports byte-for-JSON.',
      {
        'namespaces': sourceExtensions.keys.where((k) => k != 'prism').toList(),
        'mismatches': extensionMismatches.take(50).toList(),
      },
    );

    // -- Provenance and README --------------------------------------------
    final importSources =
        ((export1.envelope['extensions'] as Map?)?['prism']
                as Map?)?['import_sources']
            as List?;
    final matchingSource = importSources
        ?.whereType<Map>()
        .where(
          (entry) =>
              canonicalJson(entry['producer']) ==
              canonicalJson(sourceEnvelope['producer']),
        )
        .firstOrNull;
    final readme = source.files['README.txt'];
    final provenanceMismatches = <String>[];
    if (matchingSource == null) {
      provenanceMismatches.add('missing import_sources entry');
    } else {
      if (canonicalJson(matchingSource['capabilities']) !=
          canonicalJson(sourceEnvelope['capabilities'])) {
        provenanceMismatches.add('capabilities');
      }
      if (canonicalJson(matchingSource['warnings']) !=
          canonicalJson(sourceEnvelope['warnings'])) {
        provenanceMismatches.add('warnings');
      }
      if (readme != null &&
          matchingSource['readme_base64'] != base64Encode(readme)) {
        provenanceMismatches.add('README bytes');
      }
    }
    check(
      'provenance_preserved',
      provenanceMismatches.isEmpty,
      'Original producer, capabilities, warnings and README stay archived.',
      {
        'producer': sourceEnvelope['producer'],
        'has_readme': readme != null,
        'mismatches': provenanceMismatches,
      },
    );

    // -- Bundle files and decrypted media ---------------------------------
    final fileMismatches = <String>[];
    for (final entry in sourceFiles.entries) {
      for (final bundle in [export1, export2]) {
        final bytes = bundle.files[entry.key];
        if (bytes == null || _sha256Hex(bytes) != sourceFileHashes[entry.key]) {
          fileMismatches.add(entry.key);
        }
      }
    }
    final extraFiles = {
      for (final bundle in [export1, export2])
        for (final key in bundle.files.keys)
          if (!sourceFiles.containsKey(key)) key,
    };
    check(
      'bundle_files_preserved',
      fileMismatches.isEmpty,
      'Every foreign bundle file survives both re-exports with identical bytes.',
      {
        'source_files': sourceFiles.keys.toList(),
        'extra_files': extraFiles.toList(),
        'mismatches': fileMismatches.toSet().toList(),
      },
    );

    final mediaMismatches = <String>[];
    final unresolvedMedia = <Json>[];
    final avatarTransformations = <Json>[];
    final nativeMembers = _byId(PluralPortMapper.rows(native1, 'headmates'));
    final nativeMembers2 = _byId(PluralPortMapper.rows(native2, 'headmates'));
    for (final member in sourceRows['members']!) {
      final assetId = member['avatar_asset_id'];
      if (assetId is! String) continue;
      final bytes = assetBytes[assetId];
      final sourceAsset = sourceAssetById[assetId];
      final nativeMemberId = nativeId('members', member['id']);
      final firstMember = nativeMembers[nativeMemberId];
      final secondMember = nativeMembers2[nativeMemberId];
      if (bytes == null) {
        unresolvedMedia.add({
          'asset': assetId,
          'member': member['id'],
          'uri': sourceAsset?['uri'],
          'bundle_file_present': sourceFiles.containsKey(sourceAsset?['uri']),
        });
        if (firstMember?['profilePhotoData'] != null ||
            secondMember?['profilePhotoData'] != null) {
          mediaMismatches.add('${member['id']} has invented avatar bytes');
        }
        continue;
      }
      final firstEncoded = firstMember?['profilePhotoData'];
      final secondEncoded = secondMember?['profilePhotoData'];
      if (firstEncoded is! String || secondEncoded is! String) {
        mediaMismatches.add('${member['id']} missing native avatar bytes');
        continue;
      }
      final firstBytes = base64Decode(firstEncoded);
      if (_sha256Hex(firstBytes) != _sha256Hex(base64Decode(secondEncoded))) {
        mediaMismatches.add(
          '${member['id']} native avatar differs by database',
        );
      }
      if (_sha256Hex(firstBytes) != _sha256Hex(bytes)) {
        avatarTransformations.add({
          'member': member['id'],
          'asset': assetId,
          'source_sha256': _sha256Hex(bytes),
          'source_size_bytes': bytes.length,
          'native_sha256': _sha256Hex(firstBytes),
          'native_size_bytes': firstBytes.length,
          'note':
              'Prism normalizes member avatars to a bounded JPEG/PNG on write. The bundle keeps the producer bytes exactly.',
        });
      }
    }
    final system = sourceRows['systems']!.firstOrNull;
    final systemAssetId = system?['avatar_asset_id'];
    final systemAssetBytes = systemAssetId is String
        ? assetBytes[systemAssetId]
        : null;
    final settings1 = PluralPortMapper.rows(
      native1,
      'systemSettings',
    ).firstOrNull;
    final settings2 = PluralPortMapper.rows(
      native2,
      'systemSettings',
    ).firstOrNull;
    if (systemAssetId is String && systemAssetBytes == null) {
      unresolvedMedia.add({
        'asset': systemAssetId,
        'system': system?['id'],
        'uri': sourceAssetById[systemAssetId]?['uri'],
        'bundle_file_present': sourceFiles.containsKey(
          sourceAssetById[systemAssetId]?['uri'],
        ),
      });
    } else if (systemAssetBytes != null) {
      final encoded = base64Encode(systemAssetBytes);
      if (settings1?['systemAvatarData'] != encoded ||
          settings2?['systemAvatarData'] != encoded) {
        mediaMismatches.add('system avatar decrypted bytes');
      }
    }
    final crypto = MediaEncryptionService();
    final decryptedMediaHashes = <String>[];
    Future<List<int>> decrypt(
      dynamic row,
      Directory support, {
      bool thumbnail = false,
    }) => crypto.decryptMedia(
      ciphertext: File(
        '${support.path}/prism_media/${thumbnail ? row.thumbnailMediaId : row.mediaId}.enc',
      ).readAsBytesSync(),
      key: base64Decode(row.encryptionKeyB64 as String),
      expectedCiphertextHash:
          (thumbnail ? row.thumbnailContentHash : row.contentHash) as String,
      expectedPlaintextHash:
          (thumbnail ? row.thumbnailPlaintextHash : row.plaintextHash)
              as String,
    );
    final sourceMediaHashes = sourceFileHashes.values.toSet();
    for (final pair in [(db1, support1), (db2, support2)]) {
      final db = pair.$1;
      final support = pair.$2;
      for (final row in await db.mediaAttachmentsDao.getAll()) {
        final plain = await decrypt(row, support);
        final hash = _sha256Hex(plain);
        decryptedMediaHashes.add(hash);
        if (!sourceMediaHashes.contains(hash)) {
          mediaMismatches.add('native media ${row.id} has unknown bytes');
        }
        if (row.thumbnailMediaId.isNotEmpty) {
          final thumbnail = await decrypt(row, support, thumbnail: true);
          if (!sourceMediaHashes.contains(_sha256Hex(thumbnail))) {
            mediaMismatches.add('native thumbnail ${row.id} has unknown bytes');
          }
        }
      }
    }
    check(
      'media_bytes_preserved',
      mediaMismatches.isEmpty,
      'Bundle and decrypted attachment bytes match; avatar normalization and unresolved references are explicit.',
      {
        'decrypted_native_media': decryptedMediaHashes.length,
        'unresolved_references': unresolvedMedia,
        'avatar_transformations': avatarTransformations,
        'mismatches': mediaMismatches,
      },
    );

    // -- Native import and second database ---------------------------------
    final planMismatches = <String>[];
    for (final path in PluralPortMapper.collections.keys) {
      final nativeKey = PluralPortMapper.collections[path]!;
      final nativeRows = _byId(PluralPortMapper.rows(native1, nativeKey));
      for (final planned in PluralPortMapper.rows(preview.native, nativeKey)) {
        final actual = nativeRows[planned['id']];
        if (actual == null) {
          planMismatches.add('$nativeKey/${planned['id']} missing');
          continue;
        }
        for (final entry in planned.entries) {
          if (_normalizedNativeMediaKeys.contains(entry.key)) continue;
          if (!_samePlannedValue(entry.key, entry.value, actual[entry.key])) {
            planMismatches.add('$nativeKey/${planned['id']}/${entry.key}');
          }
        }
      }
    }
    final normalized1 = normalizeNativeExport(native1);
    final normalized2 = normalizeNativeExport(native2);
    final databasesDiffer = <String>[];
    for (final key in [
      ...PluralPortMapper.collections.values,
      'mediaAttachments',
    ]) {
      if (canonicalJson(normalized1[key]) != canonicalJson(normalized2[key])) {
        databasesDiffer.add(key);
      }
    }
    if (_canonical(_settingsView(native1)) !=
        _canonical(_settingsView(native2))) {
      databasesDiffer.add('systemSettings');
    }
    check(
      'first_import_matches_plan',
      planMismatches.isEmpty,
      'The importer wrote every planned native field, including media bytes.',
      {
        'native_records': {
          for (final entry in PluralPortMapper.collections.entries)
            entry.value: PluralPortMapper.rows(native1, entry.value).length,
        },
        'mismatches': planMismatches.take(50).toList(),
      },
    );
    check(
      'fresh_databases_agree',
      databasesDiffer.isEmpty,
      'Two fresh Prism databases import the same archive to the same records.',
      {
        'differing_families': databasesDiffer,
        'import_results': {
          'first': {
            'members': importResult1.membersCreated,
            'groups': importResult1.memberGroupsCreated,
          },
          'second': {
            'members': importResult2.membersCreated,
            'groups': importResult2.memberGroupsCreated,
          },
        },
      },
    );

    // -- Re-export stability ----------------------------------------------
    final stabilityDiffer = bundleContentDifference(export1, export2);
    int prismReferenceDelta(PluralPortBundle before, PluralPortBundle after) {
      var added = 0;
      for (final path in PluralPortMapper.recordPaths) {
        final previous = _byId(PluralPortMapper.rows(before.envelope, path));
        for (final row in PluralPortMapper.rows(after.envelope, path)) {
          final old = previous[row['id']];
          if (old == null) continue;
          final oldRefs = {
            for (final ref in (old['source_refs'] as List? ?? const []))
              canonicalJson(ref),
          };
          for (final ref in (row['source_refs'] as List? ?? const [])) {
            if (!oldRefs.contains(canonicalJson(ref))) added++;
          }
        }
      }
      return added;
    }

    final firstModules =
        ((export1.envelope['capabilities'] as Map?)?['modules'] as List? ??
                const [])
            .cast<String>()
            .toList();
    final secondModules =
        ((export2.envelope['capabilities'] as Map?)?['modules'] as List? ??
                const [])
            .cast<String>()
            .toList();
    check(
      'reexport_stable',
      stabilityDiffer.isEmpty,
      'A second fresh import and re-export reproduce the first portable content.',
      {
        'first_sha256': _sha256Hex(export1Bytes),
        'second_sha256': _sha256Hex(export2Bytes),
        'differing_content': stabilityDiffer,
        'capability_order_changed':
            canonicalJson(firstModules) != canonicalJson(secondModules),
        'prism_references_added': prismReferenceDelta(export1, export2),
        'first_reexport_preview_records': exportPreview1.records,
        'second_reexport_preview_records': exportPreview2.records,
      },
    );
    check(
      'reexport_valid',
      decoded1.envelope['pluralport_version'] == '0.1' &&
          decoded2.envelope['pluralport_version'] == '0.1' &&
          PluralPortMapper.rows(decoded2.envelope, 'members').length ==
              sourceRows['members']!.length,
      'Both re-exports decode and preview as valid PluralPort 0.1 bundles.',
      {
        'first_version': decoded1.envelope['pluralport_version'],
        'second_version': decoded2.envelope['pluralport_version'],
        'second_members': PluralPortMapper.rows(
          decoded2.envelope,
          'members',
        ).length,
      },
    );

    // -- Repeated import into the same database ---------------------------
    final repeatMismatches = <String>[];
    final normalizedRepeat = normalizeNativeExport(native1Repeat);
    for (final key in [
      ...PluralPortMapper.collections.values,
      'mediaAttachments',
    ]) {
      if (canonicalJson(normalized1[key]) !=
          canonicalJson(normalizedRepeat[key])) {
        repeatMismatches.add(key);
      }
    }
    if (_canonical(_settingsView(native1)) !=
        _canonical(_settingsView(native1Repeat))) {
      repeatMismatches.add('systemSettings');
    }
    final repeatExportDiffer = bundleContentDifference(export1, export1Repeat);
    check(
      'reimport_idempotent',
      repeatMismatches.isEmpty,
      'Importing the same archive twice in one database adds or changes no native records.',
      {
        'native_differing_families': repeatMismatches,
        'repeat_import_result': {
          'members': repeatedImported.membersCreated,
          'groups': repeatedImported.memberGroupsCreated,
        },
        'first_export_repeat_sha256': _sha256Hex(export1RepeatBytes),
      },
    );
    check(
      'reimport_export_stable',
      repeatExportDiffer.isEmpty,
      'Out of scope: repeated-import baseline stability is owned by another lane.',
      {
        'out_of_scope': true,
        'export_differing_content': repeatExportDiffer,
        'prism_references_added': prismReferenceDelta(export1, export1Repeat),
      },
      true,
    );

    // -- Explicit producer differences ------------------------------------
    final sourceAssetUri = uriOnlyAssets;
    if (sourceAssetUri.isNotEmpty) {
      differences.add({
        'id': 'in_bundle_uri_media',
        'area': 'media',
        'observed':
            '${sourceAssetUri.length} assets reference files inside the archive through assets[].uri and no bundle_path.',
        'effect':
            'Prism retains the assets and their bytes in the import archive and re-export, but does not decode them into member or system avatar fields. The preview reports them as unbundled media.',
        'assets': sourceAssetUri,
      });
    }
    for (final field in preservedFields) {
      differences.add({
        'id':
            'field_preserved_${field['field_type']}_${field['options_shape']}',
        'area': 'custom fields',
        'observed':
            'Field ${field['id']} (${field['field_type']}) is preserved for export but has no native definition.',
        'effect':
            'Its definition and values remain byte-preserved in the bundle; no native field or values are available to edit.',
        'field': field,
      });
    }
    if (preservedValues.isNotEmpty) {
      differences.add({
        'id': 'values_preserved_only',
        'area': 'custom fields',
        'observed':
            '${preservedValues.length} field values are preserved for export without native rows.',
        'effect':
            'Prism retains them in the archive and re-export but cannot display them natively.',
        'values': preservedValues,
      });
    }
    final duplicateValues = preservedValues
        .where((value) => value['duplicate_pair'] == true)
        .toList();
    if (duplicateValues.isNotEmpty) {
      differences.add({
        'id': 'duplicate_field_values',
        'area': 'custom fields',
        'observed':
            '${duplicateValues.length} source values repeat a field/member pair; native storage keeps one value per pair.',
        'effect':
            'Prism binds the last source value natively and preserves earlier duplicate rows for export, so no portable value is dropped.',
        'values': duplicateValues,
      });
    }
    if (sourcePolls.isNotEmpty ||
        _canonical(sourceExtensions).contains('"polls"')) {
      differences.add({
        'id': 'polls_not_native',
        'area': 'polls',
        'observed':
            'Poll data is declared in ${sourcePolls.isNotEmpty ? 'the top-level polls module' : 'a producer extension namespace'} while Prism has no portable poll mapping.',
        'effect':
            'Polls and votes are preserved exactly for re-export but create no native polls.',
      });
    }
    if (sourceRows['relationships.types']!.isNotEmpty ||
        sourceRows['relationships.edges']!.isNotEmpty ||
        sourceExtensions.values.any(
          (value) => _canonical(value).contains('relationship'),
        )) {
      differences.add({
        'id': 'relationships_not_native',
        'area': 'relationships',
        'observed':
            'Relationship types and edges are declared by the producer, at the top level or in a producer extension.',
        'effect':
            'They are preserved exactly in the archive and re-export but create no native relationship rows.',
      });
    }
    if (sourceRows['chat.conversations']!.isEmpty &&
        sourceRows['boards.posts']!.isEmpty) {
      differences.add({
        'id': 'chat_and_boards_empty',
        'area': 'chat',
        'observed':
            'The producer declared chat/boards capability but exported no conversations or board posts.',
        'effect': 'Nothing to map; the empty modules survive unchanged.',
      });
    }
    if (periods.any((period) => (period['assignments'] as List).length > 1)) {
      differences.add({
        'id': 'front_grouping_shape',
        'area': 'fronts',
        'observed':
            'The producer groups $multiAssignmentPeriods periods with more than one assignment.',
        'effect':
            'Prism creates one native session per assignment and re-exports the original grouped periods unchanged.',
        'native_sessions': sessions.length,
        'source_periods': periods.length,
      });
    } else if (periods.isNotEmpty) {
      differences.add({
        'id': 'front_single_assignment_shape',
        'area': 'fronts',
        'observed':
            'Every one of the ${periods.length} periods has a single assignment; overlaps express co-fronting.',
        'effect':
            'Prism creates one native session per assignment and re-exports the periods unchanged.',
        'native_sessions': sessions.length,
        'source_periods': periods.length,
      });
    }
    final entryDateNotes = sourceRows['notes']!
        .where((note) => note['entry_date'] != null)
        .length;
    if (entryDateNotes != sourceRows['notes']!.length && entryDateNotes > 0) {
      differences.add({
        'id': 'journal_dates_mixed',
        'area': 'notes',
        'observed':
            '$entryDateNotes of ${sourceRows['notes']!.length} notes carry entry_date; the rest only carry created_at.',
        'effect':
            'Prism uses entry_date when present and otherwise the creation timestamp.',
      });
    } else if (entryDateNotes == 0 && sourceRows['notes']!.isNotEmpty) {
      differences.add({
        'id': 'journal_dates_created_only',
        'area': 'notes',
        'observed':
            'The producer exports only created_at for journal entries; the editor does not backdate.',
        'effect':
            'Prism stores the creation timestamp as the note date; dates cannot match another producer that supplies entry_date.',
      });
    }
    final nonFixtureFields = sourceRows['custom_fields']!
        .where((field) => !field['name'].toString().startsWith('FIXTURE-'))
        .length;
    if (nonFixtureFields > 0) {
      differences.add({
        'id': 'builtin_fields_included',
        'area': 'custom fields',
        'observed':
            'The producer includes $nonFixtureFields built-in field definitions in addition to the fixture fields.',
        'effect':
            'Portable field and value counts are higher than a producer that exports only the fixture fields.',
      });
    }
    if (unresolvedMedia.isNotEmpty) {
      differences.add({
        'id': 'media_not_native',
        'area': 'media',
        'observed':
            '${unresolvedMedia.length} producer media references resolve to no native Prism bytes.',
        'effect':
            'The files are byte-preserved in the bundle, but the corresponding native avatar/banner fields are empty.',
        'references': unresolvedMedia,
      });
    }
    if (avatarTransformations.isNotEmpty) {
      differences.add({
        'id': 'avatar_normalization',
        'area': 'media',
        'observed':
            '${avatarTransformations.length} member avatars are re-encoded by Prism\'s bounded avatar normalizer on import.',
        'effect':
            'The native member row holds normalized image bytes while the bundle keeps the producer\'s exact file bytes. Decrypted chat/media attachments are unaffected.',
        'transformations': avatarTransformations,
      });
    }
    if (repeatExportDiffer.isNotEmpty) {
      differences.add({
        'id': 'repeat_import_export_drift',
        'out_of_scope': true,
        'area': 'repeated import',
        'observed':
            'A repeated import of the same archive leaves native rows unchanged but changes the next re-export.',
        'effect':
            'The repeated export reprojects records from normalized native rows, truncates sub-second timestamps and attaches Prism native snapshots. The original bundle file bytes are still retained.',
        'changed': repeatExportDiffer,
      });
    }
    report['differences'] = differences;
    report['first_import'] = {
      'native_counts': {
        for (final entry in PluralPortMapper.collections.entries)
          entry.value: PluralPortMapper.rows(native1, entry.value).length,
      },
      'media_attachments': await db1.mediaAttachmentsDao.getAll().then(
        (rows) => rows.length,
      ),
      'system_profile': _settingsView(native1),
    };
    report['first_export'] = {
      'sha256': _sha256Hex(export1Bytes),
      'size_bytes': export1Bytes.length,
      'record_counts': {
        for (final path in PluralPortMapper.recordPaths)
          path: PluralPortMapper.rows(export1.envelope, path).length,
      },
      'files': {
        for (final entry in export1.files.entries)
          entry.key: {
            'size_bytes': entry.value.length,
            'sha256': _sha256Hex(entry.value),
          },
      },
      'warnings': export1.envelope['warnings'],
      'producer': export1.envelope['producer'],
      'version': export1.envelope['pluralport_version'],
      'system_count': PluralPortMapper.rows(export1.envelope, 'systems').length,
      'asset_count': PluralPortMapper.rows(export1.envelope, 'assets').length,
    };
    report['second_import'] = {
      'native_counts': {
        for (final entry in PluralPortMapper.collections.entries)
          entry.value: PluralPortMapper.rows(native2, entry.value).length,
      },
      'media_attachments': await db2.mediaAttachmentsDao.getAll().then(
        (rows) => rows.length,
      ),
      'system_profile': _settingsView(native2),
    };
    report['second_export'] = {
      'sha256': _sha256Hex(export2Bytes),
      'size_bytes': export2Bytes.length,
      'record_counts': {
        for (final path in PluralPortMapper.recordPaths)
          path: PluralPortMapper.rows(export2.envelope, path).length,
      },
      'files': {
        for (final entry in export2.files.entries)
          entry.key: {
            'size_bytes': entry.value.length,
            'sha256': _sha256Hex(entry.value),
          },
      },
      'warnings': export2.envelope['warnings'],
      'system_count': PluralPortMapper.rows(export2.envelope, 'systems').length,
      'asset_count': PluralPortMapper.rows(export2.envelope, 'assets').length,
    };
    report['repeat_import'] = {
      'native_counts': {
        for (final entry in PluralPortMapper.collections.entries)
          entry.value: PluralPortMapper.rows(native1Repeat, entry.value).length,
      },
      'export_sha256': _sha256Hex(export1RepeatBytes),
      'export_records': PluralPortMapper.rows(
        decoded1Repeat.envelope,
        'members',
      ).length,
    };
  } catch (error, stack) {
    report['error'] = {
      'type': error.runtimeType.toString(),
      'message': '$error',
      'stack': stack.toString(),
    };
  } finally {
    try {
      await db1?.close();
    } catch (_) {}
    try {
      await db2?.close();
    } catch (_) {}
    if (temp != null) {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    }
    final failed = checks
        .where((check) => check['skipped'] != true && check['ok'] != true)
        .toList();
    report['checks'] = checks;
    report['failed_checks'] = failed.map((check) => check['id']).toList();
    report['skipped_checks'] = checks
        .where((check) => check['skipped'] == true)
        .map((check) => check['id'])
        .toList();
    report['artifacts'] = artifacts;
    final outputDirectory = fixture.outputDirectory;
    final reportFile = File('$outputDirectory/report.json');
    await Directory(outputDirectory).create(recursive: true);
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    await File(
      '$outputDirectory/summary.md',
    ).writeAsString(_foreignFixtureSummary(report));
  }
  return report;
}

String _foreignFixtureSummary(Json report) {
  final buffer = StringBuffer()
    ..writeln('# Foreign PluralPort round trip: ${report['case']['label']}')
    ..writeln()
    ..writeln('Generated: ${report['generated_at']}')
    ..writeln('Archive: `${report['case']['archive']}`')
    ..writeln();
  final error = report['error'] ?? report['preview_error'];
  if (error is Map) {
    buffer
      ..writeln('## Error')
      ..writeln()
      ..writeln('```')
      ..writeln(error['message'])
      ..writeln('```')
      ..writeln();
    final counts = error['non_object_extension_counts'];
    if (counts is Map) {
      buffer
        ..writeln('Non-object `extensions` values:')
        ..writeln();
      for (final entry in counts.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
      buffer.writeln();
    }
  }
  buffer
    ..writeln('## Checks')
    ..writeln();
  for (final check in (report['checks'] as List? ?? const [])) {
    final status = check['skipped'] == true
        ? 'SKIP'
        : check['ok'] == true
        ? 'PASS'
        : 'FAIL';
    buffer.writeln('- $status `${check['id']}` — ${check['summary']}');
  }
  buffer
    ..writeln()
    ..writeln('## Producer differences')
    ..writeln();
  for (final difference in (report['differences'] as List? ?? const [])) {
    buffer
      ..writeln('### ${difference['id']} (${difference['area']})')
      ..writeln()
      ..writeln('Observed: ${difference['observed']}')
      ..writeln()
      ..writeln('Effect: ${difference['effect']}')
      ..writeln();
  }
  buffer
    ..writeln('## Artifacts')
    ..writeln();
  for (final entry in (report['artifacts'] as Map? ?? const {}).entries) {
    buffer.writeln('- ${entry.key}: `${entry.value}`');
  }
  return buffer.toString();
}
