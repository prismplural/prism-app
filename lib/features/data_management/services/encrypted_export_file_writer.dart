import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import 'package:prism_plurality/features/data_management/models/export_models.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

/// Sendable snapshot of one cached encrypted media blob.
///
/// Only scalars and a path string cross the isolate boundary. The worker
/// rebuilds the `File` handle itself, so no `File`, `IOSink`, database
/// handle, repository, or FFI object is ever sent.
///
/// [lengthBytes] and [modifiedMillisecondsSinceEpoch] are the stat snapshot
/// captured on the caller isolate. They are intentionally *not* re-read on
/// arrival: `ExportCrypto._statMatchesDescriptor` compares against this
/// snapshot, which is what detects a media file that changed between
/// descriptor capture and the actual read.
@immutable
final class ExportMediaBlobTask {
  const ExportMediaBlobTask({
    required this.mediaId,
    required this.path,
    required this.lengthBytes,
    required this.modifiedMillisecondsSinceEpoch,
  });

  final String mediaId;
  final String path;
  final int lengthBytes;
  final int modifiedMillisecondsSinceEpoch;
}

/// Test-only rendezvous that proves the write happened on a distinct isolate
/// and that the main isolate's event loop stayed live while the worker was
/// paused. Null in production.
///
/// Carries only a `SendPort`, which is sendable across isolates.
@visibleForTesting
final class ExportWorkerProbe {
  const ExportWorkerProbe(this.eventPort);

  final SendPort eventPort;
}

/// Event emitted by the worker when [ExportWorkerProbe] is active.
///
/// [isolateControlPort] is `Isolate.current.controlPort` *inside the worker*,
/// so a test can assert it differs from the main isolate's control port.
/// [resumePort] is the worker's own `ReceivePort.sendPort`; the worker blocks
/// until the test sends it a message.
@visibleForTesting
final class ExportWorkerStartedEvent {
  const ExportWorkerStartedEvent({
    required this.isolateControlPort,
    required this.resumePort,
  });

  final SendPort isolateControlPort;
  final SendPort resumePort;
}

/// Everything the encrypted export worker needs, and nothing more.
///
/// Deliberately has no `toString` override: the task holds the user's export
/// password in plaintext, so it must never be interpolated into a log,
/// diagnostic, or error message. Do not add one, and do not log the task.
@immutable
final class EncryptedExportWriteTask {
  EncryptedExportWriteTask({
    required this.export,
    required List<ExportMediaBlobTask> mediaBlobs,
    required this.password,
    required this.outputPath,
    this.jsonPlaintextSoftLimitBytes =
        ExportCrypto.defaultJsonPlaintextSoftLimitBytes,
    this.mediaChunkSize = ExportCrypto.defaultStreamChunkSize,
    @visibleForTesting Uint8List? saltForTesting,
    @visibleForTesting Uint8List? nonceForTesting,
    @visibleForTesting this.probe,
  }) : mediaBlobs = List<ExportMediaBlobTask>.unmodifiable(mediaBlobs),
       saltForTesting = saltForTesting == null
           ? null
           : Uint8List.fromList(saltForTesting),
       nonceForTesting = nonceForTesting == null
           ? null
           : Uint8List.fromList(nonceForTesting);

  /// The export envelope itself — not a prebuilt JSON map.
  ///
  /// [V1Export.toJson] runs *inside* the worker immediately before the
  /// streaming writer. Passing a prebuilt map would leave the eager map
  /// construction (the sampled ANR stack) on the main isolate.
  final V1Export export;

  /// Immutable copy; caller mutation cannot change an in-flight task.
  final List<ExportMediaBlobTask> mediaBlobs;

  final String password;
  final String outputPath;
  final int jsonPlaintextSoftLimitBytes;
  final int mediaChunkSize;

  @visibleForTesting
  final Uint8List? saltForTesting;

  @visibleForTesting
  final Uint8List? nonceForTesting;

  @visibleForTesting
  final ExportWorkerProbe? probe;
}

/// Runs [writeEncryptedExportFileTask] on a worker isolate.
///
/// The `Isolate.run` closure captures only `task`. It is deliberately a
/// top-level function: defining it inside `DataExportService` would let it
/// over-capture repositories, database state, or an open sink.
Future<int> writeEncryptedExportFileOffMain(EncryptedExportWriteTask task) =>
    Isolate.run(() => writeEncryptedExportFileTask(task));

/// Builds and writes the PRISM1 file. Runs on the worker isolate in
/// production; tests may call it directly.
///
/// The worker owns the destination [IOSink]: it opens the file, calls
/// [V1Export.toJson] locally, and delegates the format itself to the
/// unchanged [ExportCrypto.writeEncryptedFile] primitive.
Future<int> writeEncryptedExportFileTask(EncryptedExportWriteTask task) async {
  final probe = task.probe;
  if (probe != null) {
    final resumePort = ReceivePort();
    probe.eventPort.send(
      ExportWorkerStartedEvent(
        isolateControlPort: Isolate.current.controlPort,
        resumePort: resumePort.sendPort,
      ),
    );
    // Hold before opening the sink so a paused worker leaves no partial file.
    await resumePort.first;
    resumePort.close();
  }

  final descriptors = <ExportMediaBlobDescriptor>[
    for (final blob in task.mediaBlobs)
      ExportMediaBlobDescriptor(
        mediaId: blob.mediaId,
        file: File(blob.path),
        lengthBytes: blob.lengthBytes,
        // Milliseconds, matching `ExportCrypto._statMatchesDescriptor`.
        modified: DateTime.fromMillisecondsSinceEpoch(
          blob.modifiedMillisecondsSinceEpoch,
        ),
      ),
  ];

  final sink = File(task.outputPath).openWrite();
  try {
    final sizeBytes = await ExportCrypto.writeEncryptedFile(
      jsonValue: task.export.toJson(),
      mediaBlobs: descriptors,
      password: task.password,
      sink: sink,
      jsonPlaintextSoftLimitBytes: task.jsonPlaintextSoftLimitBytes,
      mediaChunkSize: task.mediaChunkSize,
      saltForTesting: task.saltForTesting,
      nonceForTesting: task.nonceForTesting,
    );
    await sink.close();
    return sizeBytes;
  } catch (error, stack) {
    // Suppress only the close failure; the original error and worker stack
    // are what the service-level cleanup and the user-visible path need.
    try {
      await sink.close();
    } catch (_) {}
    Error.throwWithStackTrace(error, stack);
  }
}
