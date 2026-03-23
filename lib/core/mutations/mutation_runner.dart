import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';

typedef MutationAction<T> = Future<T> Function();
typedef MutationErrorMapper =
    AppFailure Function(Object error, StackTrace stackTrace);
typedef MutationSuccessHook = void Function();
typedef MutationErrorReporter =
    void Function(
      String message, {
      ErrorSeverity severity,
      StackTrace? stackTrace,
    });
typedef TransactionRunner = Future<T> Function<T>(MutationAction<T> action);

class MutationRunner {
  MutationRunner({required this.transactionRunner, this.reportError});

  factory MutationRunner.forDatabase(
    AppDatabase database, {
    ErrorReportingService? errorReportingService,
  }) {
    final reporter = errorReportingService ?? ErrorReportingService.instance;
    return MutationRunner(
      transactionRunner: database.transaction,
      reportError: reporter.report,
    );
  }

  final TransactionRunner transactionRunner;
  final MutationErrorReporter? reportError;

  Future<MutationResult<T>> run<T>({
    required MutationAction<T> action,
    String? actionLabel,
    bool transactional = true,
    MutationErrorMapper? mapError,
    List<MutationSuccessHook> onSuccess = const [],
  }) async {
    try {
      final result = await (transactional
          ? transactionRunner(action)
          : action());

      for (final callback in onSuccess) {
        try {
          callback();
        } catch (error, stackTrace) {
          reportError?.call(
            'Post-mutation hook failed: $error',
            severity: ErrorSeverity.warning,
            stackTrace: stackTrace,
          );
        }
      }

      return MutationResult.success(result);
    } catch (error, stackTrace) {
      final failure = _toFailure(error, stackTrace, mapError: mapError);

      reportError?.call(
        failure.formatForReport(actionLabel),
        severity: failure.severity,
        stackTrace: stackTrace,
      );

      return MutationResult.failure(failure);
    }
  }

  Future<MutationResult<void>> runVoid({
    required Future<void> Function() action,
    String? actionLabel,
    bool transactional = true,
    MutationErrorMapper? mapError,
    List<MutationSuccessHook> onSuccess = const [],
  }) async {
    return run<void>(
      action: () async {
        await action();
      },
      actionLabel: actionLabel,
      transactional: transactional,
      mapError: mapError,
      onSuccess: onSuccess,
    );
  }

  AppFailure _toFailure(
    Object error,
    StackTrace stackTrace, {
    MutationErrorMapper? mapError,
  }) {
    if (error is AppFailure) {
      return error;
    }

    if (mapError != null) {
      return mapError(error, stackTrace);
    }

    return AppFailure.unexpected(
      error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
