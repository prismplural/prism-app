import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';

const _defaultMaxImageBytes = 20 * 1024 * 1024;
const _defaultMaxChunkImages = 32;
const _defaultMaxChunkBytes = 8 * 1024 * 1024;

const _supportedImageExtensions = {'.gif', '.jpeg', '.jpg', '.png', '.webp'};

/// File-backed work passed to the avatar ZIP isolate.
class SpAvatarZipWorkerTask {
  final String filePath;
  final Map<String, String> prismMemberIdBySpId;
  final String? systemSpId;
  final int maxImageBytes;
  final int maxChunkImages;
  final int maxChunkBytes;

  const SpAvatarZipWorkerTask({
    required this.filePath,
    required this.prismMemberIdBySpId,
    this.systemSpId,
    this.maxImageBytes = _defaultMaxImageBytes,
    this.maxChunkImages = _defaultMaxChunkImages,
    this.maxChunkBytes = _defaultMaxChunkBytes,
  });
}

enum SpAvatarZipTargetKind { member, system }

class SpAvatarZipChunkDescriptor {
  final SpAvatarZipTargetKind targetKind;
  final String targetId;
  final String sourceSpId;
  final int byteOffset;
  final int byteLength;

  const SpAvatarZipChunkDescriptor({
    required this.targetKind,
    required this.targetId,
    required this.sourceSpId,
    required this.byteOffset,
    required this.byteLength,
  });
}

class SpAvatarZipScanStats {
  final int entriesScanned;
  final int supportedImages;
  final int processableImages;
  final int unmatchedImages;
  final int duplicateImages;
  final int oversizedImages;
  final int emptyImages;
  final int invalidImages;

  const SpAvatarZipScanStats({
    this.entriesScanned = 0,
    this.supportedImages = 0,
    this.processableImages = 0,
    this.unmatchedImages = 0,
    this.duplicateImages = 0,
    this.oversizedImages = 0,
    this.emptyImages = 0,
    this.invalidImages = 0,
  });

  factory SpAvatarZipScanStats._fromMessage(Map<Object?, Object?> message) {
    return SpAvatarZipScanStats(
      entriesScanned: message['entriesScanned']! as int,
      supportedImages: message['supportedImages']! as int,
      processableImages: message['processableImages']! as int,
      unmatchedImages: message['unmatchedImages']! as int,
      duplicateImages: message['duplicateImages']! as int,
      oversizedImages: message['oversizedImages']! as int,
      emptyImages: message['emptyImages']! as int,
      invalidImages: message['invalidImages']! as int,
    );
  }
}

sealed class SpAvatarZipWorkerEvent {
  const SpAvatarZipWorkerEvent();
}

class SpAvatarZipWorkerReady extends SpAvatarZipWorkerEvent {
  final SpAvatarZipScanStats stats;

  const SpAvatarZipWorkerReady(this.stats);
}

class SpAvatarZipWorkerChunk extends SpAvatarZipWorkerEvent {
  final int sequence;
  final List<SpAvatarZipChunkDescriptor> descriptors;
  final Uint8List packedBytes;
  final SpAvatarZipScanStats stats;

  const SpAvatarZipWorkerChunk({
    required this.sequence,
    required this.descriptors,
    required this.packedBytes,
    required this.stats,
  });

  Uint8List bytesFor(SpAvatarZipChunkDescriptor descriptor) {
    final end = descriptor.byteOffset + descriptor.byteLength;
    if (descriptor.byteOffset < 0 || end > packedBytes.length) {
      throw RangeError.range(end, 0, packedBytes.length, 'descriptor');
    }
    return Uint8List.sublistView(packedBytes, descriptor.byteOffset, end);
  }
}

class SpAvatarZipWorkerComplete extends SpAvatarZipWorkerEvent {
  final SpAvatarZipScanStats stats;

  const SpAvatarZipWorkerComplete(this.stats);
}

class SpAvatarZipWorkerFailed extends SpAvatarZipWorkerEvent {
  final String code;
  final String safeMessage;
  final String stack;
  final SpAvatarZipScanStats stats;

  const SpAvatarZipWorkerFailed({
    required this.code,
    required this.safeMessage,
    required this.stack,
    required this.stats,
  });
}

/// Starts one isolate per ZIP and exposes its explicit ack/cancel protocol.
class SpAvatarZipWorkerRunner {
  const SpAvatarZipWorkerRunner();

  Future<SpAvatarZipWorkerSession> start(SpAvatarZipWorkerTask task) async {
    _validateTask(task);

    final eventPort = ReceivePort();
    final errorPort = ReceivePort();
    final session = SpAvatarZipWorkerSession._(
      eventPort: eventPort,
      errorPort: errorPort,
    );

    session._listen();
    try {
      final isolate = await Isolate.spawn<Map<Object?, Object?>>(
        _spAvatarZipWorkerMain,
        {'replyPort': eventPort.sendPort, 'task': _taskToMessage(task)},
        errorsAreFatal: true,
        onError: errorPort.sendPort,
        // Preserve terminal-message and exit ordering.
        onExit: eventPort.sendPort,
        debugName: 'sp-avatar-zip-worker',
      );
      session._attach(isolate);
      return session;
    } catch (_) {
      await session._closePorts();
      rethrow;
    }
  }
}

class SpAvatarZipWorkerSession {
  final ReceivePort _eventPort;
  final ReceivePort _errorPort;
  final StreamController<SpAvatarZipWorkerEvent> _events =
      StreamController<SpAvatarZipWorkerEvent>();
  final Completer<void> _done = Completer<void>();

  StreamSubscription<Object?>? _eventSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  Isolate? _isolate;
  SendPort? _commandPort;
  bool _terminal = false;
  bool _portsClosed = false;

  SpAvatarZipWorkerSession._({
    required ReceivePort eventPort,
    required ReceivePort errorPort,
  }) : _eventPort = eventPort,
       _errorPort = errorPort;

  Stream<SpAvatarZipWorkerEvent> get events => _events.stream;

  Future<void> get done => _done.future;

  void _listen() {
    _eventSubscription = _eventPort.listen(_handleWorkerMessage);
    _errorSubscription = _errorPort.listen(_handleIsolateError);
  }

  void _attach(Isolate isolate) {
    _isolate = isolate;
  }

  void acknowledge(int sequence) {
    if (_terminal) {
      throw StateError('Avatar ZIP worker has already completed.');
    }
    final port = _commandPort;
    if (port == null) {
      throw StateError('Avatar ZIP worker is not ready.');
    }
    port.send({'type': 'ack', 'sequence': sequence});
  }

  void cancel([String reason = 'cancelled']) {
    if (_terminal) return;
    final port = _commandPort;
    if (port != null) {
      port.send({'type': 'cancel', 'reason': reason});
      return;
    }
    _isolate?.kill(priority: Isolate.immediate);
    _finish(
      const SpAvatarZipWorkerFailed(
        code: 'cancelled',
        safeMessage: 'Avatar ZIP processing was cancelled.',
        stack: 'Cancelled before the worker became ready.',
        stats: SpAvatarZipScanStats(),
      ),
    );
  }

  Future<void> dispose() async {
    if (!_terminal) cancel('session disposed');
    await done;
    await _closePorts();
  }

  void _handleWorkerMessage(Object? rawMessage) {
    if (_terminal) return;
    if (rawMessage == null) {
      _finish(
        const SpAvatarZipWorkerFailed(
          code: 'unexpected_exit',
          safeMessage: 'Avatar ZIP processing stopped unexpectedly.',
          stack: 'Worker isolate exited without a terminal message.',
          stats: SpAvatarZipScanStats(),
        ),
      );
      return;
    }
    if (rawMessage is! Map<Object?, Object?>) {
      _finishMainProtocolFailure(
        const SpAvatarZipWorkerFailed(
          code: 'protocol_error',
          safeMessage: 'Avatar ZIP worker sent an invalid message.',
          stack: 'Worker message was not a map.',
          stats: SpAvatarZipScanStats(),
        ),
      );
      return;
    }
    try {
      final type = rawMessage['type'];
      switch (type) {
        case 'ready':
          _commandPort = rawMessage['commandPort']! as SendPort;
          _events.add(
            SpAvatarZipWorkerReady(
              SpAvatarZipScanStats._fromMessage(
                rawMessage['stats']! as Map<Object?, Object?>,
              ),
            ),
          );
        case 'chunk':
          final transfer = rawMessage['bytes']! as TransferableTypedData;
          final packedBytes = transfer.materialize().asUint8List();
          final rawDescriptors = rawMessage['descriptors']! as List<Object?>;
          final descriptors = [
            for (final raw in rawDescriptors)
              _descriptorFromMessage(raw! as Map<Object?, Object?>),
          ];
          _events.add(
            SpAvatarZipWorkerChunk(
              sequence: rawMessage['sequence']! as int,
              descriptors: List.unmodifiable(descriptors),
              packedBytes: packedBytes,
              stats: SpAvatarZipScanStats._fromMessage(
                rawMessage['stats']! as Map<Object?, Object?>,
              ),
            ),
          );
        case 'complete':
          _finish(
            SpAvatarZipWorkerComplete(
              SpAvatarZipScanStats._fromMessage(
                rawMessage['stats']! as Map<Object?, Object?>,
              ),
            ),
          );
        case 'failed':
          _finish(
            SpAvatarZipWorkerFailed(
              code: rawMessage['code']! as String,
              safeMessage: rawMessage['safeMessage']! as String,
              stack: rawMessage['stack']! as String,
              stats: SpAvatarZipScanStats._fromMessage(
                rawMessage['stats']! as Map<Object?, Object?>,
              ),
            ),
          );
        default:
          _finishMainProtocolFailure(
            const SpAvatarZipWorkerFailed(
              code: 'protocol_error',
              safeMessage: 'Avatar ZIP worker sent an invalid message.',
              stack: 'Unknown worker message type.',
              stats: SpAvatarZipScanStats(),
            ),
          );
      }
    } catch (error, stack) {
      _finishMainProtocolFailure(
        SpAvatarZipWorkerFailed(
          code: 'protocol_error',
          safeMessage: 'Avatar ZIP worker sent an invalid message.',
          stack: '$error\n$stack',
          stats: const SpAvatarZipScanStats(),
        ),
      );
    }
  }

  void _finishMainProtocolFailure(SpAvatarZipWorkerFailed failure) {
    // Cancel cooperatively when a malformed chunk cannot be acknowledged.
    final port = _commandPort;
    if (port != null) {
      port.send({'type': 'cancel', 'reason': 'main protocol failure'});
    } else {
      // A pre-handshake failure cannot be cancelled cooperatively.
      _isolate?.kill(priority: Isolate.immediate);
    }
    _finish(failure);
  }

  void _handleIsolateError(Object? rawError) {
    if (_terminal) return;
    final parts = rawError is List<Object?> ? rawError : const <Object?>[];
    final stack = parts.length > 1 ? '${parts[1]}' : '$rawError';
    _finish(
      SpAvatarZipWorkerFailed(
        code: 'worker_error',
        safeMessage: 'Avatar ZIP processing failed.',
        stack: stack,
        stats: const SpAvatarZipScanStats(),
      ),
    );
  }

  void _finish(SpAvatarZipWorkerEvent event) {
    if (_terminal) return;
    _terminal = true;
    _events.add(event);
    if (!_done.isCompleted) _done.complete();
    unawaited(_closePorts());
  }

  Future<void> _closePorts() async {
    if (_portsClosed) return;
    _portsClosed = true;
    await _eventSubscription?.cancel();
    await _errorSubscription?.cancel();
    _eventPort.close();
    _errorPort.close();
    await _events.close();
  }
}

class _MutableStats {
  int entriesScanned = 0;
  int supportedImages = 0;
  int processableImages = 0;
  int unmatchedImages = 0;
  int duplicateImages = 0;
  int oversizedImages = 0;
  int emptyImages = 0;
  int invalidImages = 0;

  Map<String, int> toMessage() => {
    'entriesScanned': entriesScanned,
    'supportedImages': supportedImages,
    'processableImages': processableImages,
    'unmatchedImages': unmatchedImages,
    'duplicateImages': duplicateImages,
    'oversizedImages': oversizedImages,
    'emptyImages': emptyImages,
    'invalidImages': invalidImages,
  };
}

class _SelectedEntry {
  final ArchiveFile entry;
  final String sourceSpId;
  final String targetId;
  final SpAvatarZipTargetKind targetKind;

  const _SelectedEntry({
    required this.entry,
    required this.sourceSpId,
    required this.targetId,
    required this.targetKind,
  });
}

class _PendingDescriptor {
  final String sourceSpId;
  final String targetId;
  final SpAvatarZipTargetKind targetKind;
  final int byteOffset;
  final int byteLength;

  const _PendingDescriptor({
    required this.sourceSpId,
    required this.targetId,
    required this.targetKind,
    required this.byteOffset,
    required this.byteLength,
  });

  Map<String, Object> toMessage() => {
    'sourceSpId': sourceSpId,
    'targetId': targetId,
    'targetKind': targetKind.name,
    'byteOffset': byteOffset,
    'byteLength': byteLength,
  };
}

class _WorkerFailure implements Exception {
  final String code;
  final String safeMessage;
  final String detail;

  const _WorkerFailure(this.code, this.safeMessage, this.detail);
}

void _spAvatarZipWorkerMain(Map<Object?, Object?> spawnMessage) async {
  final replyPort = spawnMessage['replyPort']! as SendPort;
  final task = spawnMessage['task']! as Map<Object?, Object?>;
  final commands = ReceivePort();
  final commandIterator = StreamIterator<Object?>(commands);
  final stats = _MutableStats();
  InputFileStream? input;
  Archive? archive;
  Map<String, Object?>? terminalMessage;

  try {
    input = InputFileStream(task['filePath']! as String);
    if (input.length < 4 || !_hasZipSignature(input)) {
      throw const FormatException('Invalid ZIP signature');
    }
    archive = ZipDecoder().decodeStream(input);

    final memberIds = (task['memberIds']! as Map<Object?, Object?>)
        .cast<String, String>();
    final systemSpId = task['systemSpId'] as String?;
    final maxImageBytes = task['maxImageBytes']! as int;
    final maxChunkImages = task['maxChunkImages']! as int;
    final maxChunkBytes = task['maxChunkBytes']! as int;
    final selectedBySpId = <String, _SelectedEntry>{};

    for (final entry in archive.files) {
      stats.entriesScanned++;
      if (!entry.isFile) continue;

      final fileName = p.posix.basename(entry.name.replaceAll('\\', '/'));
      final extension = p.posix.extension(fileName).toLowerCase();
      if (!_supportedImageExtensions.contains(extension)) continue;
      stats.supportedImages++;

      final spId = p.posix.basenameWithoutExtension(fileName).trim();
      if (spId.isEmpty) {
        stats.unmatchedImages++;
        continue;
      }

      final isSystem = systemSpId != null && spId == systemSpId;
      final memberId = memberIds[spId];
      if (!isSystem && memberId == null) {
        stats.unmatchedImages++;
        continue;
      }

      if (selectedBySpId.containsKey(spId)) stats.duplicateImages++;
      selectedBySpId[spId] = _SelectedEntry(
        entry: entry,
        sourceSpId: spId,
        targetId: isSystem ? spId : memberId!,
        targetKind: isSystem
            ? SpAvatarZipTargetKind.system
            : SpAvatarZipTargetKind.member,
      );
    }

    final selected = <_SelectedEntry>[];
    for (final candidate in selectedBySpId.values) {
      if (candidate.entry.size <= 0) {
        stats.emptyImages++;
      } else if (candidate.entry.size > maxImageBytes) {
        stats.oversizedImages++;
      } else {
        selected.add(candidate);
      }
    }
    stats.processableImages = selected.length;

    replyPort.send({
      'type': 'ready',
      'commandPort': commands.sendPort,
      'stats': stats.toMessage(),
    });

    var sequence = 0;
    var pendingBytes = BytesBuilder(copy: false);
    var pendingDescriptors = <_PendingDescriptor>[];

    Future<void> flush() async {
      if (pendingDescriptors.isEmpty) return;
      final packed = pendingBytes.takeBytes();
      final descriptors = pendingDescriptors;
      pendingBytes = BytesBuilder(copy: false);
      pendingDescriptors = <_PendingDescriptor>[];
      final currentSequence = sequence++;
      replyPort.send({
        'type': 'chunk',
        'sequence': currentSequence,
        'descriptors': [
          for (final descriptor in descriptors) descriptor.toMessage(),
        ],
        'bytes': TransferableTypedData.fromList([packed]),
        'stats': stats.toMessage(),
      });
      await _waitForAcknowledgement(commandIterator, currentSequence);
    }

    for (final candidate in selected) {
      Uint8List? normalized;
      try {
        final raw = candidate.entry.readBytes();
        if (raw == null || raw.isEmpty) {
          stats.emptyImages++;
          continue;
        }
        if (raw.length > maxImageBytes) {
          stats.oversizedImages++;
          continue;
        }
        normalized = AvatarNormalizer.normalize(raw);
        if (normalized == null || normalized.isEmpty) {
          stats.invalidImages++;
          continue;
        }
      } catch (_) {
        stats.invalidImages++;
        continue;
      } finally {
        candidate.entry.closeSync();
      }

      final crossesCount = pendingDescriptors.length >= maxChunkImages;
      final crossesBytes =
          pendingBytes.length > 0 &&
          pendingBytes.length + normalized.length > maxChunkBytes;
      if (crossesCount || crossesBytes) await flush();

      final offset = pendingBytes.length;
      pendingBytes.add(normalized);
      pendingDescriptors.add(
        _PendingDescriptor(
          sourceSpId: candidate.sourceSpId,
          targetId: candidate.targetId,
          targetKind: candidate.targetKind,
          byteOffset: offset,
          byteLength: normalized.length,
        ),
      );

      if (pendingDescriptors.length >= maxChunkImages ||
          pendingBytes.length >= maxChunkBytes) {
        await flush();
      }
    }

    await flush();
    terminalMessage = {'type': 'complete', 'stats': stats.toMessage()};
  } on _WorkerFailure catch (error, stack) {
    terminalMessage = {
      'type': 'failed',
      'code': error.code,
      'safeMessage': error.safeMessage,
      'stack': '${error.detail}\n$stack',
      'stats': stats.toMessage(),
    };
  } on ArchiveException catch (error, stack) {
    terminalMessage = {
      'type': 'failed',
      'code': 'invalid_zip',
      'safeMessage': 'Could not read avatar ZIP.',
      'stack': '${error.runtimeType}\n$stack',
      'stats': stats.toMessage(),
    };
  } on FormatException catch (error, stack) {
    terminalMessage = {
      'type': 'failed',
      'code': 'invalid_zip',
      'safeMessage': 'Could not read avatar ZIP.',
      'stack': '${error.runtimeType}\n$stack',
      'stats': stats.toMessage(),
    };
  } catch (error, stack) {
    terminalMessage = {
      'type': 'failed',
      'code': 'worker_error',
      'safeMessage': 'Avatar ZIP processing failed.',
      'stack': '${error.runtimeType}\n$stack',
      'stats': stats.toMessage(),
    };
  } finally {
    try {
      await commandIterator.cancel();
    } catch (_) {}
    commands.close();
    try {
      archive?.clearSync();
    } catch (_) {}
    try {
      input?.closeSync();
    } catch (_) {}
  }

  replyPort.send(terminalMessage);
}

bool _hasZipSignature(InputFileStream input) {
  final signature = input.readUint32();
  input.reset();
  return signature == 0x04034b50 ||
      signature == 0x06054b50 ||
      signature == 0x08074b50;
}

Future<void> _waitForAcknowledgement(
  StreamIterator<Object?> commands,
  int expectedSequence,
) async {
  if (!await commands.moveNext()) {
    throw const _WorkerFailure(
      'cancelled',
      'Avatar ZIP processing was cancelled.',
      'Command port closed.',
    );
  }
  final command = commands.current;
  if (command is! Map<Object?, Object?>) {
    throw const _WorkerFailure(
      'protocol_error',
      'Avatar ZIP acknowledgement was invalid.',
      'Command was not a map.',
    );
  }
  if (command['type'] == 'cancel') {
    throw const _WorkerFailure(
      'cancelled',
      'Avatar ZIP processing was cancelled.',
      'Caller cancelled processing.',
    );
  }
  if (command['type'] != 'ack' || command['sequence'] != expectedSequence) {
    throw _WorkerFailure(
      'protocol_error',
      'Avatar ZIP acknowledgement was invalid.',
      'Expected acknowledgement $expectedSequence.',
    );
  }
}

Map<String, Object?> _taskToMessage(SpAvatarZipWorkerTask task) => {
  'filePath': task.filePath,
  'memberIds': Map<String, String>.from(task.prismMemberIdBySpId),
  'systemSpId': task.systemSpId?.trim().isEmpty ?? true
      ? null
      : task.systemSpId!.trim(),
  'maxImageBytes': task.maxImageBytes,
  'maxChunkImages': task.maxChunkImages,
  'maxChunkBytes': task.maxChunkBytes,
};

SpAvatarZipChunkDescriptor _descriptorFromMessage(
  Map<Object?, Object?> message,
) => SpAvatarZipChunkDescriptor(
  targetKind: SpAvatarZipTargetKind.values.byName(
    message['targetKind']! as String,
  ),
  targetId: message['targetId']! as String,
  sourceSpId: message['sourceSpId']! as String,
  byteOffset: message['byteOffset']! as int,
  byteLength: message['byteLength']! as int,
);

void _validateTask(SpAvatarZipWorkerTask task) {
  if (task.filePath.trim().isEmpty) {
    throw ArgumentError.value(task.filePath, 'filePath', 'must not be empty');
  }
  if (task.maxImageBytes <= 0) {
    throw ArgumentError.value(
      task.maxImageBytes,
      'maxImageBytes',
      'must be positive',
    );
  }
  if (task.maxChunkImages <= 0) {
    throw ArgumentError.value(
      task.maxChunkImages,
      'maxChunkImages',
      'must be positive',
    );
  }
  if (task.maxChunkBytes <= 0) {
    throw ArgumentError.value(
      task.maxChunkBytes,
      'maxChunkBytes',
      'must be positive',
    );
  }
}
