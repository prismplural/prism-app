import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:prism_plurality/core/database/database_providers.dart';

// ── Record-count providers ─────────────────────────────────

final memberCountProvider = FutureProvider<int>((ref) {
  return ref.watch(memberRepositoryProvider).getCount();
});

final sessionCountProvider = FutureProvider<int>((ref) {
  return ref.watch(frontingSessionRepositoryProvider).getCount();
});

final conversationCountProvider = FutureProvider<int>((ref) {
  return ref.watch(conversationRepositoryProvider).getCount();
});

final pollCountProvider = FutureProvider<int>((ref) {
  return ref.watch(pollRepositoryProvider).getCount();
});

/// Placeholder — HLC tracking removed (sync now managed by Rust layer).
final crdtLatestHlcProvider = FutureProvider<String?>((ref) async {
  return null;
});

final dbPathProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'prism.db');
});
