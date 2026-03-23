import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/error_reporting_service.dart';

/// Provides the singleton [ErrorReportingService].
final errorReportingServiceProvider = Provider<ErrorReportingService>((ref) {
  return ErrorReportingService.instance;
});

/// Holds a reactive list of [AppError] entries, updated whenever the
/// [ErrorReportingService] reports a new error.
class ErrorHistoryNotifier extends Notifier<List<AppError>> {
  @override
  List<AppError> build() {
    final service = ref.read(errorReportingServiceProvider);

    // Seed with any errors already present.
    final initial = List<AppError>.from(service.recentErrors);

    // Listen for future errors and rebuild state.
    void onError(AppError error) {
      state = List<AppError>.from(service.recentErrors);
    }

    service.addListener(onError);

    // Clean up when the provider is disposed.
    ref.onDispose(() => service.removeListener(onError));

    return initial;
  }

  /// Convenience: report an error through the service and update state.
  void addError(
    String message, {
    ErrorSeverity severity = ErrorSeverity.error,
    StackTrace? stackTrace,
  }) {
    final service = ref.read(errorReportingServiceProvider);
    service.report(message, severity: severity, stackTrace: stackTrace);
    // State is updated via the listener registered in build().
  }

  /// Clear all recorded errors.
  void clear() {
    final service = ref.read(errorReportingServiceProvider);
    service.clear();
    state = [];
  }
}

final errorHistoryProvider =
    NotifierProvider<ErrorHistoryNotifier, List<AppError>>(
  ErrorHistoryNotifier.new,
);
