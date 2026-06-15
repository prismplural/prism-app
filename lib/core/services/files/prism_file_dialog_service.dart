import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

enum SaveFileStatus {
  saved,
  cancelled,
  failed,
  unsupported,
  alreadyActive,
  sourceNotReady,
}

class SaveFileOutcome {
  const SaveFileOutcome({
    required this.status,
    this.pathOrUri,
    this.savedDisplayName,
    this.bytesCopied,
    this.error,
  });

  final SaveFileStatus status;
  final String? pathOrUri;
  final String? savedDisplayName;
  final int? bytesCopied;
  final Object? error;

  bool get didSave => status == SaveFileStatus.saved;
}

class ExistingFileSaveRequest {
  const ExistingFileSaveRequest({
    required this.sourceFile,
    required this.suggestedName,
    required this.allowedExtensions,
    this.sourceIsDurable = true,
    this.dialogTitle,
    this.mimeType,
  });

  final File sourceFile;
  final String suggestedName;
  final List<String> allowedExtensions;
  final bool sourceIsDurable;
  final String? dialogTitle;
  final String? mimeType;
}

class PickedFileHandle {
  const PickedFileHandle({
    required this.name,
    required this.readAsBytes,
    required this.openRead,
    this.path,
    this.size,
  });

  final String name;
  final String? path;
  final int? size;
  final Future<Uint8List> Function() readAsBytes;
  final Stream<List<int>> Function()? openRead;
}

abstract interface class PrismFileDialogService {
  Future<SaveFileOutcome> saveExistingFile(ExistingFileSaveRequest request);

  Future<SaveFileOutcome> saveBytes({
    required Uint8List bytes,
    required String suggestedName,
    required List<String> allowedExtensions,
    String? dialogTitle,
    String? mimeType,
  });

  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  });

  Future<PickedFileHandle?> pickImageFile({String? dialogTitle});
}

final prismFileDialogServiceProvider = Provider<PrismFileDialogService>(
  (ref) => PlatformPrismFileDialogService(),
);

class PlatformPrismFileDialogService implements PrismFileDialogService {
  PlatformPrismFileDialogService({
    MethodChannel channel = const MethodChannel(
      'com.prism.prism_plurality/file_handoffs',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;
  var _operationActive = false;

  @override
  Future<SaveFileOutcome> saveExistingFile(
    ExistingFileSaveRequest request,
  ) async {
    if (_operationActive) {
      return const SaveFileOutcome(status: SaveFileStatus.alreadyActive);
    }
    _operationActive = true;
    try {
      final sourceStat = await _readySourceStat(request.sourceFile);
      if (sourceStat == null) {
        return const SaveFileOutcome(status: SaveFileStatus.sourceNotReady);
      }
      final fileName = _safeSuggestedName(
        request.suggestedName,
        request.allowedExtensions,
      );
      if (Platform.isAndroid || Platform.isIOS) {
        return await _saveExistingFileNative(
          request,
          fileName: fileName,
          expectedLength: sourceStat.size,
        );
      }
      return await _saveExistingFileDesktop(
        request,
        fileName: fileName,
        expectedLength: sourceStat.size,
      );
    } finally {
      _operationActive = false;
    }
  }

  @override
  Future<SaveFileOutcome> saveBytes({
    required Uint8List bytes,
    required String suggestedName,
    required List<String> allowedExtensions,
    String? dialogTitle,
    String? mimeType,
  }) async {
    if (_operationActive) {
      return const SaveFileOutcome(status: SaveFileStatus.alreadyActive);
    }
    if (bytes.isEmpty) {
      return const SaveFileOutcome(status: SaveFileStatus.sourceNotReady);
    }
    _operationActive = true;
    try {
      final fileName = _safeSuggestedName(suggestedName, allowedExtensions);
      final destination = await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: _normalizedExtensions(allowedExtensions),
        bytes: bytes,
        lockParentWindow: Platform.isWindows,
      );
      if (destination == null) {
        return const SaveFileOutcome(status: SaveFileStatus.cancelled);
      }
      return SaveFileOutcome(
        status: SaveFileStatus.saved,
        pathOrUri: destination,
        savedDisplayName: _displayNameFromPathOrName(destination, fileName),
        bytesCopied: bytes.length,
      );
    } on MissingPluginException catch (e) {
      return SaveFileOutcome(status: SaveFileStatus.unsupported, error: e);
    } catch (e) {
      return SaveFileOutcome(status: SaveFileStatus.failed, error: e);
    } finally {
      _operationActive = false;
    }
  }

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    if (_operationActive) return null;
    _operationActive = true;
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: dialogTitle,
        type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: _normalizedExtensions(allowedExtensions),
        lockParentWindow: Platform.isWindows,
      );
      if (file == null) return null;
      return _handleForPlatformFile(file);
    } finally {
      _operationActive = false;
    }
  }

  @override
  Future<PickedFileHandle?> pickImageFile({String? dialogTitle}) {
    return pickFile(
      dialogTitle: dialogTitle,
      allowedExtensions: const [
        'avif',
        'gif',
        'heic',
        'heif',
        'jpeg',
        'jpg',
        'png',
        'webp',
      ],
    );
  }

  Future<SaveFileOutcome> _saveExistingFileNative(
    ExistingFileSaveRequest request, {
    required String fileName,
    required int expectedLength,
  }) async {
    try {
      final response = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('saveExistingFile', {
            'sourcePath': request.sourceFile.path,
            'suggestedName': fileName,
            'mimeType': request.mimeType ?? 'application/octet-stream',
            'expectedLength': expectedLength,
            'sourceIsDurable': request.sourceIsDurable,
          });
      return _outcomeFromNativeMap(response);
    } on MissingPluginException catch (e) {
      return SaveFileOutcome(status: SaveFileStatus.unsupported, error: e);
    } on PlatformException catch (e) {
      return SaveFileOutcome(status: SaveFileStatus.failed, error: e);
    } catch (e) {
      return SaveFileOutcome(status: SaveFileStatus.failed, error: e);
    }
  }

  Future<SaveFileOutcome> _saveExistingFileDesktop(
    ExistingFileSaveRequest request, {
    required String fileName,
    required int expectedLength,
  }) async {
    try {
      final bytes = await request.sourceFile.readAsBytes();
      if (bytes.length != expectedLength) {
        return SaveFileOutcome(
          status: SaveFileStatus.failed,
          bytesCopied: bytes.length,
          error: 'Read ${bytes.length} bytes, expected $expectedLength',
        );
      }
      final destination = await FilePicker.saveFile(
        dialogTitle: request.dialogTitle,
        fileName: fileName,
        type: request.allowedExtensions.isEmpty
            ? FileType.any
            : FileType.custom,
        allowedExtensions: _normalizedExtensions(request.allowedExtensions),
        bytes: bytes,
        lockParentWindow: Platform.isWindows,
      );
      if (destination == null) {
        return const SaveFileOutcome(status: SaveFileStatus.cancelled);
      }
      return SaveFileOutcome(
        status: SaveFileStatus.saved,
        pathOrUri: destination,
        savedDisplayName: p.basename(destination),
        bytesCopied: bytes.length,
      );
    } on MissingPluginException catch (e) {
      return SaveFileOutcome(status: SaveFileStatus.unsupported, error: e);
    } catch (e) {
      return SaveFileOutcome(status: SaveFileStatus.failed, error: e);
    }
  }

  SaveFileOutcome _outcomeFromNativeMap(Map<dynamic, dynamic>? response) {
    final statusName = response?['status'] as String?;
    final status = SaveFileStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => SaveFileStatus.failed,
    );
    final bytesCopied = response?['bytesCopied'];
    return SaveFileOutcome(
      status: status,
      pathOrUri: response?['pathOrUri'] as String?,
      savedDisplayName: response?['savedDisplayName'] as String?,
      bytesCopied: bytesCopied is num ? bytesCopied.toInt() : null,
      error: response?['error'],
    );
  }

  PickedFileHandle _handleForPlatformFile(PlatformFile file) {
    final path = file.path;
    return PickedFileHandle(
      name: file.name,
      path: path,
      size: file.size,
      readAsBytes: () async {
        if (!kIsWeb && path != null) return File(path).readAsBytes();
        return file.readAsBytes();
      },
      openRead: !kIsWeb && path != null
          ? () => File(path).openRead()
          : () => file.readAsByteStream(),
    );
  }

  Future<FileStat?> _readySourceStat(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        return null;
      }
      return stat;
    } on FileSystemException {
      return null;
    }
  }

  static String _safeSuggestedName(
    String suggestedName,
    List<String> allowedExtensions,
  ) {
    var name = suggestedName.trim();
    if (name.isEmpty) name = 'Prism Export';
    name = name.split(RegExp(r'[\\/]')).last;
    name = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty) name = 'Prism Export';
    return _ensureExtension(name, allowedExtensions);
  }

  static String _ensureExtension(
    String fileName,
    List<String> allowedExtensions,
  ) {
    final extensions = _normalizedExtensions(allowedExtensions);
    if (extensions.isEmpty) return fileName;
    final lowerName = fileName.toLowerCase();
    for (final extension in extensions) {
      if (lowerName.endsWith('.$extension')) return fileName;
    }
    return '$fileName.${extensions.first}';
  }

  static List<String> _normalizedExtensions(List<String> allowedExtensions) {
    return allowedExtensions
        .map((extension) => extension.trim().toLowerCase())
        .map(
          (extension) =>
              extension.startsWith('.') ? extension.substring(1) : extension,
        )
        .where((extension) => extension.isNotEmpty)
        .toList(growable: false);
  }

  static String _displayNameFromPathOrName(String pathOrUri, String fallback) {
    final parsed = Uri.tryParse(pathOrUri);
    if (parsed != null && parsed.hasScheme && parsed.pathSegments.isNotEmpty) {
      return parsed.pathSegments.last;
    }
    final basename = p.basename(pathOrUri);
    return basename.isEmpty ? fallback : basename;
  }
}
