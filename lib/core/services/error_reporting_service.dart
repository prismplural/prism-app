/// Severity levels for reported errors.
enum ErrorSeverity {
  info,
  warning,
  error,
  fatal,
}

/// Represents a single error entry in the in-memory log.
class AppError {
  const AppError({
    required this.message,
    required this.severity,
    required this.timestamp,
    this.stackTrace,
  });

  final String message;
  final ErrorSeverity severity;
  final DateTime timestamp;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      '[${severity.name.toUpperCase()}] $timestamp: $message';
}

/// Callback type for error listeners.
typedef ErrorListener = void Function(AppError error);

/// Pure Dart service that maintains an in-memory log of application errors.
///
/// Keeps at most [_maxErrors] entries, automatically discarding the oldest
/// when the limit is exceeded.
class ErrorReportingService {
  ErrorReportingService._();

  static final ErrorReportingService instance = ErrorReportingService._();

  static const _maxErrors = 100;

  final List<AppError> _errors = [];
  final List<ErrorListener> _listeners = [];

  /// All stored errors (newest last).
  List<AppError> get errors => List.unmodifiable(_errors);

  /// The 50 most recent errors (newest last).
  List<AppError> get recentErrors {
    final start = _errors.length > 50 ? _errors.length - 50 : 0;
    return List.unmodifiable(_errors.sublist(start));
  }

  /// Register a listener that is called whenever a new error is reported.
  void addListener(ErrorListener listener) {
    _listeners.add(listener);
  }

  /// Remove a previously registered listener.
  void removeListener(ErrorListener listener) {
    _listeners.remove(listener);
  }

  /// Report an error and notify listeners.
  void report(
    String message, {
    ErrorSeverity severity = ErrorSeverity.error,
    StackTrace? stackTrace,
  }) {
    final error = AppError(
      message: message,
      severity: severity,
      timestamp: DateTime.now(),
      stackTrace: stackTrace,
    );

    _errors.add(error);

    // Trim to max size.
    while (_errors.length > _maxErrors) {
      _errors.removeAt(0);
    }

    for (final listener in _listeners) {
      listener(error);
    }
  }

  /// Clear all stored errors and notify listeners with a synthetic info entry.
  void clear() {
    _errors.clear();
  }
}
