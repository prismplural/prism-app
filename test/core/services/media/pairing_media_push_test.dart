import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/services/media/pairing_media_push.dart';

void main() {
  // Fakes / observation.
  late List<PairingMediaRef> candidates;
  late Set<String> held; // ids the inviter holds in cache
  late Set<String> present; // ids the relay already serves
  Object? batchError;
  late bool uploadCommits;
  Object? uploadError;
  late List<String> uploaded;

  PairingMediaPush build({int maxBlobs = 200, int batchChunkSize = 1024}) {
    return PairingMediaPush(
      maxBlobs: maxBlobs,
      batchChunkSize: batchChunkSize,
      candidates: () async => candidates,
      holdsCiphertext: (id) async =>
          held.contains(id) ? Uint8List.fromList([1, 2, 3]) : null,
      batchExists: (ids) async {
        if (batchError != null) throw batchError!;
        return ids.where(present.contains).toList();
      },
      upload: (id, hash, data) async {
        if (uploadError != null) throw uploadError!;
        uploaded.add(id);
        return uploadCommits;
      },
    );
  }

  PairingMediaRef ref(String id) =>
      PairingMediaRef(mediaId: id, contentHash: 'h-$id');

  setUp(() {
    candidates = [];
    held = {};
    present = {};
    batchError = null;
    uploadCommits = true;
    uploadError = null;
    uploaded = [];
  });

  test('pushes only held, relay-absent blobs', () async {
    candidates = [ref('a'), ref('b'), ref('c')];
    held = {'a', 'b'}; // c not held
    present = {'b'}; // b already on relay
    final pushed = await build().run();
    expect(uploaded, ['a'], reason: 'a is held + absent; b present; c not held');
    expect(pushed, 1);
  });

  test('skips a chunk it cannot confirm via batch-exists (no blind push)',
      () async {
    candidates = [ref('a'), ref('b')];
    held = {'a', 'b'};
    batchError = Exception('no handle');
    final pushed = await build().run();
    expect(uploaded, isEmpty, reason: 'can\'t confirm presence ⇒ push nothing');
    expect(pushed, 0);
  });

  test('dedupes by mediaId, preserving priority order', () async {
    // Thumbnail-first ordering with the same id appearing twice.
    candidates = [ref('t1'), ref('t1'), ref('full1')];
    held = {'t1', 'full1'};
    await build().run();
    expect(uploaded, ['t1', 'full1']);
  });

  test('honours the maxBlobs cap (thumbnail-first wins the budget)', () async {
    candidates = [ref('t1'), ref('t2'), ref('full1')];
    held = {'t1', 't2', 'full1'};
    await build(maxBlobs: 2).run();
    expect(uploaded, ['t1', 't2'], reason: 'only the first 2 candidates fit');
  });

  test('an uncommitted (in-progress) upload is not counted', () async {
    candidates = [ref('a')];
    held = {'a'};
    uploadCommits = false; // 202 in-progress
    final pushed = await build().run();
    expect(uploaded, ['a']);
    expect(pushed, 0, reason: 'only committed uploads count');
  });

  test('a transient upload throw is swallowed; the run continues', () async {
    candidates = [ref('a'), ref('b')];
    held = {'a', 'b'};
    uploadError = Exception('rate limited');
    final pushed = await build().run();
    expect(pushed, 0);
  });

  test('empty candidate set is a quiet no-op', () async {
    final pushed = await build().run();
    expect(uploaded, isEmpty);
    expect(pushed, 0);
  });

  test('chunks batch-exists by batchChunkSize', () async {
    candidates = [ref('a'), ref('b'), ref('c')];
    held = {'a', 'b', 'c'};
    present = {};
    final chunks = <int>[];
    final push = PairingMediaPush(
      batchChunkSize: 2,
      candidates: () async => candidates,
      holdsCiphertext: (id) async => Uint8List.fromList([0]),
      batchExists: (ids) async {
        chunks.add(ids.length);
        return const [];
      },
      upload: (id, hash, data) async {
        uploaded.add(id);
        return true;
      },
    );
    await push.run();
    expect(chunks, [2, 1], reason: '3 ids in chunks of 2');
    expect(uploaded, ['a', 'b', 'c']);
  });
}
