import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prism_plurality/features/chat/services/voice/voice_models.dart';

enum VoiceRecorderBackendStatus {
  idle,
  recording,
  preparing,
  readyToSend,
  error,
  unsupported,
}

enum VoiceRecorderPermissionStatus { unknown, granted, denied, blocked }

enum VoiceRecorderErrorCode {
  permissionDenied,
  permissionBlocked,
  unsupported,
  tooShort,
  budgetExceeded,
  remuxFailed,
  invalidFormat,
  emptyRecording,
  notRecording,
  alreadyRecording,
  recorderFailure,
}

class VoiceRecorderBackendException implements Exception {
  const VoiceRecorderBackendException({
    required this.errorCode,
    required this.message,
    this.cause,
  });

  final VoiceRecorderErrorCode errorCode;
  final String message;
  final Object? cause;

  @override
  String toString() => 'VoiceRecorderBackendException($errorCode, $message)';
}

class VoiceRecorderBackendState {
  const VoiceRecorderBackendState({
    this.status = VoiceRecorderBackendStatus.idle,
    this.permissionStatus = VoiceRecorderPermissionStatus.unknown,
    this.capabilities,
    this.elapsed = Duration.zero,
    this.artifact,
    this.errorCode,
    this.errorMessage,
  });

  final VoiceRecorderBackendStatus status;
  final VoiceRecorderPermissionStatus permissionStatus;
  final VoiceRecorderCapabilities? capabilities;
  final Duration elapsed;
  final VoiceCaptureArtifact? artifact;
  final VoiceRecorderErrorCode? errorCode;
  final String? errorMessage;

  VoiceRecorderBackendState copyWith({
    VoiceRecorderBackendStatus? status,
    VoiceRecorderPermissionStatus? permissionStatus,
    VoiceRecorderCapabilities? capabilities,
    bool clearCapabilities = false,
    Duration? elapsed,
    VoiceCaptureArtifact? artifact,
    bool clearArtifact = false,
    VoiceRecorderErrorCode? errorCode,
    bool clearErrorCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return VoiceRecorderBackendState(
      status: status ?? this.status,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      capabilities: clearCapabilities
          ? null
          : (capabilities ?? this.capabilities),
      elapsed: elapsed ?? this.elapsed,
      artifact: clearArtifact ? null : (artifact ?? this.artifact),
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

abstract interface class VoiceRecorderBackend {
  ValueListenable<VoiceRecorderBackendState> get state;
  Stream<double> get meterStream;

  Future<VoiceRecorderCapabilities> getCapabilities();
  Future<void> start();
  Future<VoiceCaptureArtifact> stop();
  Future<void> cancel();
  Future<void> dispose();
}
