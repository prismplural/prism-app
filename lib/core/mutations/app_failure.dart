import 'package:prism_plurality/core/services/error_reporting_service.dart';

enum AppFailureType {
  validation,
  notFound,
  conflict,
  unauthorized,
  network,
  storage,
  cancelled,
  unexpected,
}

class AppFailure implements Exception {
  const AppFailure({
    required this.type,
    required this.message,
    required this.severity,
    this.cause,
    this.stackTrace,
  });

  factory AppFailure.validation(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppFailure(
      type: AppFailureType.validation,
      message: message,
      severity: ErrorSeverity.warning,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory AppFailure.notFound(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppFailure(
      type: AppFailureType.notFound,
      message: message,
      severity: ErrorSeverity.warning,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory AppFailure.conflict(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppFailure(
      type: AppFailureType.conflict,
      message: message,
      severity: ErrorSeverity.warning,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory AppFailure.unauthorized(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppFailure(
      type: AppFailureType.unauthorized,
      message: message,
      severity: ErrorSeverity.error,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory AppFailure.network(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppFailure(
      type: AppFailureType.network,
      message: message,
      severity: ErrorSeverity.error,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory AppFailure.storage(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppFailure(
      type: AppFailureType.storage,
      message: message,
      severity: ErrorSeverity.error,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory AppFailure.cancelled(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppFailure(
      type: AppFailureType.cancelled,
      message: message,
      severity: ErrorSeverity.info,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory AppFailure.unexpected(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppFailure(
      type: AppFailureType.unexpected,
      message: message,
      severity: ErrorSeverity.error,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  final AppFailureType type;
  final String message;
  final ErrorSeverity severity;
  final Object? cause;
  final StackTrace? stackTrace;

  String formatForReport([String? actionLabel]) {
    if (actionLabel == null || actionLabel.isEmpty) {
      return message;
    }
    return '$actionLabel failed: $message';
  }

  @override
  String toString() => message;
}
