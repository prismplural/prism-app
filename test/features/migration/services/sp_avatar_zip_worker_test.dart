import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prism_plurality/features/migration/services/sp_avatar_zip_worker.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sp-avatar-worker-test-');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'packs selected file-backed images and reports scan statistics',
    () async {
      final alice = _jpegBytes(220, 20, 20);
      final system = _jpegBytes(20, 220, 20);
      final zip = await _writeZip(tempDir, [
        ('nested/sp-alice.jpg', alice),
        ('sp-system.jpg', system),
        ('sp-unmatched.jpg', _jpegBytes(20, 20, 220)),
        ('notes.txt', Uint8List.fromList([1, 2, 3])),
      ]);

      final session = await const SpAvatarZipWorkerRunner().start(
        SpAvatarZipWorkerTask(
          filePath: zip.path,
          prismMemberIdBySpId: const {'sp-alice': 'prism-alice'},
          systemSpId: 'sp-system',
        ),
      );
      final events = StreamIterator(session.events);
      addTearDown(() async => session.dispose());

      final ready = await _next<SpAvatarZipWorkerReady>(events);
      expect(ready.stats.entriesScanned, 4);
      expect(ready.stats.supportedImages, 3);
      expect(ready.stats.processableImages, 2);
      expect(ready.stats.unmatchedImages, 1);

      final chunk = await _next<SpAvatarZipWorkerChunk>(events);
      expect(chunk.sequence, 0);
      expect(chunk.descriptors, hasLength(2));
      expect(chunk.descriptors[0].targetKind, SpAvatarZipTargetKind.member);
      expect(chunk.descriptors[0].targetId, 'prism-alice');
      expect(chunk.bytesFor(chunk.descriptors[0]), alice);
      expect(chunk.descriptors[1].targetKind, SpAvatarZipTargetKind.system);
      expect(chunk.bytesFor(chunk.descriptors[1]), system);

      session.acknowledge(chunk.sequence);
      final complete = await _next<SpAvatarZipWorkerComplete>(events);
      expect(complete.stats.processableImages, 2);
      await session.done;
    },
  );

  test('matching acknowledgement releases the next chunk', () async {
    final zip = await _writeZip(tempDir, [
      ('one.jpg', _jpegBytes(1, 2, 3)),
      ('two.jpg', _jpegBytes(4, 5, 6)),
      ('three.jpg', _jpegBytes(7, 8, 9)),
    ]);
    final session = await const SpAvatarZipWorkerRunner().start(
      SpAvatarZipWorkerTask(
        filePath: zip.path,
        prismMemberIdBySpId: const {
          'one': 'member-one',
          'two': 'member-two',
          'three': 'member-three',
        },
        maxChunkImages: 2,
      ),
    );
    addTearDown(() async => session.dispose());
    final events = StreamIterator(session.events);

    await _next<SpAvatarZipWorkerReady>(events);
    final first = await _next<SpAvatarZipWorkerChunk>(events);
    expect(first.descriptors, hasLength(2));

    session.acknowledge(first.sequence);
    final second = await _next<SpAvatarZipWorkerChunk>(events);
    expect(second.sequence, 1);
    expect(second.descriptors, hasLength(1));
    session.acknowledge(second.sequence);
    await _next<SpAvatarZipWorkerComplete>(events);
  });

  test(
    'enforces byte limit and sends an oversized normalized image alone',
    () async {
      final one = _jpegBytes(11, 12, 13);
      final two = _jpegBytes(14, 15, 16);
      final zip = await _writeZip(tempDir, [
        ('one.jpg', one),
        ('two.jpg', two),
      ]);
      final session = await const SpAvatarZipWorkerRunner().start(
        SpAvatarZipWorkerTask(
          filePath: zip.path,
          prismMemberIdBySpId: const {'one': 'member-one', 'two': 'member-two'},
          maxChunkImages: 32,
          maxChunkBytes: 1,
        ),
      );
      addTearDown(() async => session.dispose());
      final events = StreamIterator(session.events);

      await _next<SpAvatarZipWorkerReady>(events);
      final first = await _next<SpAvatarZipWorkerChunk>(events);
      expect(first.descriptors, hasLength(1));
      expect(first.packedBytes.length, greaterThan(1));
      session.acknowledge(first.sequence);

      final second = await _next<SpAvatarZipWorkerChunk>(events);
      expect(second.descriptors, hasLength(1));
      expect(second.packedBytes.length, greaterThan(1));
      session.acknowledge(second.sequence);
      await _next<SpAvatarZipWorkerComplete>(events);
    },
  );

  test('uses the last supported entry for a duplicate SP id', () async {
    final first = _jpegBytes(220, 20, 20);
    final last = _jpegBytes(20, 20, 220);
    final zip = await _writeZip(tempDir, [
      ('sp-alice.jpg', first),
      ('nested/sp-alice.jpeg', last),
    ]);
    final session = await const SpAvatarZipWorkerRunner().start(
      SpAvatarZipWorkerTask(
        filePath: zip.path,
        prismMemberIdBySpId: const {'sp-alice': 'prism-alice'},
      ),
    );
    addTearDown(() async => session.dispose());
    final events = StreamIterator(session.events);

    final ready = await _next<SpAvatarZipWorkerReady>(events);
    expect(ready.stats.supportedImages, 2);
    expect(ready.stats.processableImages, 1);
    expect(ready.stats.duplicateImages, 1);
    final chunk = await _next<SpAvatarZipWorkerChunk>(events);
    expect(chunk.descriptors, hasLength(1));
    expect(chunk.bytesFor(chunk.descriptors.single), last);
    session.acknowledge(chunk.sequence);
    await _next<SpAvatarZipWorkerComplete>(events);
  });

  test(
    'filters unmatched and declared oversized entries before decode',
    () async {
      final zip = await _writeZip(tempDir, [
        ('unmatched.jpg', Uint8List.fromList([1, 2, 3, 4])),
        ('matched.jpg', Uint8List.fromList([5, 6, 7, 8])),
      ]);
      final session = await const SpAvatarZipWorkerRunner().start(
        SpAvatarZipWorkerTask(
          filePath: zip.path,
          prismMemberIdBySpId: const {'matched': 'prism-matched'},
          maxImageBytes: 3,
        ),
      );
      addTearDown(() async => session.dispose());
      final events = StreamIterator(session.events);

      final ready = await _next<SpAvatarZipWorkerReady>(events);
      expect(ready.stats.unmatchedImages, 1);
      expect(ready.stats.oversizedImages, 1);
      expect(ready.stats.processableImages, 0);
      final complete = await _next<SpAvatarZipWorkerComplete>(events);
      expect(complete.stats.invalidImages, 0);
    },
  );

  test(
    'a mismatched acknowledgement terminates with a sendable error',
    () async {
      final zip = await _writeZip(tempDir, [
        ('sp-alice.jpg', _jpegBytes(1, 2, 3)),
        ('sp-bob.jpg', _jpegBytes(4, 5, 6)),
      ]);
      final session = await const SpAvatarZipWorkerRunner().start(
        SpAvatarZipWorkerTask(
          filePath: zip.path,
          prismMemberIdBySpId: const {
            'sp-alice': 'prism-alice',
            'sp-bob': 'prism-bob',
          },
          maxChunkImages: 1,
        ),
      );
      addTearDown(() async => session.dispose());
      final events = StreamIterator(session.events);

      await _next<SpAvatarZipWorkerReady>(events);
      final chunk = await _next<SpAvatarZipWorkerChunk>(events);
      session.acknowledge(chunk.sequence + 1);
      // A second chunk would be ordered before this same-port failure.
      final failed = await _next<SpAvatarZipWorkerFailed>(events);
      expect(failed.code, 'protocol_error');
      expect(failed.safeMessage, isNot(contains(zip.path)));
      expect(failed.stack, isNotEmpty);
      await session.done;
    },
  );

  test('invalid ZIP failure is sanitized and closes the input file', () async {
    final zip = File('${tempDir.path}/invalid.zip');
    await zip.writeAsBytes([1, 2, 3, 4]);
    final session = await const SpAvatarZipWorkerRunner().start(
      SpAvatarZipWorkerTask(filePath: zip.path, prismMemberIdBySpId: const {}),
    );
    addTearDown(() async => session.dispose());
    final events = StreamIterator(session.events);

    final failed = await _next<SpAvatarZipWorkerFailed>(events);
    expect(failed.code, 'invalid_zip');
    expect(failed.safeMessage, 'Could not read avatar ZIP.');
    expect(failed.safeMessage, isNot(contains(zip.path)));
    await session.done;

    final renamed = File('${tempDir.path}/renamed.zip');
    await zip.rename(renamed.path);
    expect(await renamed.exists(), isTrue);
  });

  test('cancel stops a worker waiting for acknowledgement', () async {
    final zip = await _writeZip(tempDir, [
      ('sp-alice.jpg', _jpegBytes(1, 2, 3)),
      ('sp-bob.jpg', _jpegBytes(4, 5, 6)),
    ]);
    final session = await const SpAvatarZipWorkerRunner().start(
      SpAvatarZipWorkerTask(
        filePath: zip.path,
        prismMemberIdBySpId: const {
          'sp-alice': 'prism-alice',
          'sp-bob': 'prism-bob',
        },
        maxChunkImages: 1,
      ),
    );
    addTearDown(() async => session.dispose());
    final events = StreamIterator(session.events);

    await _next<SpAvatarZipWorkerReady>(events);
    await _next<SpAvatarZipWorkerChunk>(events);
    session.cancel('caller stopped');
    final failed = await _next<SpAvatarZipWorkerFailed>(events);
    expect(failed.code, 'cancelled');
    expect(failed.safeMessage, 'Avatar ZIP processing was cancelled.');
    await session.done;
  });
}

Future<T> _next<T extends SpAvatarZipWorkerEvent>(
  StreamIterator<SpAvatarZipWorkerEvent> iterator,
) async {
  expect(await iterator.moveNext(), isTrue);
  expect(iterator.current, isA<T>());
  return iterator.current as T;
}

Uint8List _jpegBytes(int r, int g, int b) {
  final image = img.Image(width: 2, height: 2);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image));
}

Future<File> _writeZip(Directory dir, List<(String, Uint8List)> entries) async {
  final archive = Archive();
  for (final (name, bytes) in entries) {
    archive.addFile(ArchiveFile.bytes(name, bytes));
  }
  final file = File('${dir.path}/avatars.zip');
  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file;
}
