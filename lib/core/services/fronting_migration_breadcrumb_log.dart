library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

@immutable
class FrontingMigrationBreadcrumb {
  const FrontingMigrationBreadcrumb({
    required this.timestamp,
    required this.kind,
    required this.reason,
    required this.count,
    this.data = const <String, dynamic>{},
  });

  final DateTime timestamp;
  final String kind;
  final String reason;
  final int count;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'kind': kind,
    'reason': reason,
    'count': count,
    if (data.isNotEmpty) 'data': data,
  };

  factory FrontingMigrationBreadcrumb.fromJson(Map<String, dynamic> json) {
    return FrontingMigrationBreadcrumb(
      timestamp: DateTime.parse(json['ts'] as String),
      kind: json['kind'] as String? ?? 'unknown',
      reason: json['reason'] as String? ?? 'unknown',
      count: (json['count'] as num?)?.toInt() ?? 0,
      data: json['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['data'] as Map<String, dynamic>)
          : const <String, dynamic>{},
    );
  }

  String get summary {
    switch (kind) {
      case 'rescued_active_orphans':
        return 'Fronting migration rescued $count active orphan rows';
      case 'purged_deleted_orphans':
        return 'Fronting migration purged $count deleted orphan rows';
      default:
        return 'Fronting migration breadcrumb: $kind ($count)';
    }
  }
}

class FrontingMigrationBreadcrumbLog {
  FrontingMigrationBreadcrumbLog._();

  static final FrontingMigrationBreadcrumbLog instance =
      FrontingMigrationBreadcrumbLog._();

  static const int _maxEntries = 50;
  static const String _fileName = 'fronting_migration_breadcrumbs.json';

  Future<void>? _inflight;

  Future<void> append(FrontingMigrationBreadcrumb breadcrumb) async {
    final pending = _inflight ?? Future<void>.value();
    final next = pending.then((_) => _appendUnsafe(breadcrumb));
    _inflight = next;
    try {
      await next;
    } finally {
      if (identical(_inflight, next)) {
        _inflight = null;
      }
    }
  }

  Future<void> _appendUnsafe(FrontingMigrationBreadcrumb breadcrumb) async {
    try {
      final file = await _file();
      final existing = await _readUnsafe(file);
      final updated = [...existing, breadcrumb];
      final overflow = updated.length - _maxEntries;
      final trimmed = overflow > 0 ? updated.sublist(overflow) : updated;
      await file.writeAsString(
        jsonEncode(trimmed.map((entry) => entry.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('[FrontingMigrationBreadcrumbLog] append failed: $e');
    }
  }

  Future<List<FrontingMigrationBreadcrumb>> readAll() async {
    try {
      final file = await _file();
      return _readUnsafe(file);
    } catch (e) {
      debugPrint('[FrontingMigrationBreadcrumbLog] readAll failed: $e');
      return const <FrontingMigrationBreadcrumb>[];
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[FrontingMigrationBreadcrumbLog] clear failed: $e');
    }
  }

  Future<List<FrontingMigrationBreadcrumb>> _readUnsafe(File file) async {
    if (!await file.exists()) {
      return const <FrontingMigrationBreadcrumb>[];
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const <FrontingMigrationBreadcrumb>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <FrontingMigrationBreadcrumb>[];
    }
    return decoded
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .map(FrontingMigrationBreadcrumb.fromJson)
        .toList();
  }

  Future<File> _file() async {
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    return File('${dir.path}/$_fileName');
  }
}
