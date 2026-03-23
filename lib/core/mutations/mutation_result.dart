import 'package:prism_plurality/core/mutations/app_failure.dart';

sealed class MutationResult<T> {
  const MutationResult();

  const factory MutationResult.success(T data) = MutationSuccess<T>;
  const factory MutationResult.failure(AppFailure failure) = MutationFailure<T>;

  bool get isSuccess => this is MutationSuccess<T>;

  bool get isFailure => this is MutationFailure<T>;

  T? get dataOrNull {
    return switch (this) {
      MutationSuccess<T>(:final data) => data,
      MutationFailure<T>() => null,
    };
  }

  AppFailure? get failureOrNull {
    return switch (this) {
      MutationSuccess<T>() => null,
      MutationFailure<T>(:final failure) => failure,
    };
  }

  R when<R>({
    required R Function(T data) success,
    required R Function(AppFailure error) failure,
  }) {
    return switch (this) {
      MutationSuccess<T>(:final data) => success(data),
      MutationFailure<T>(failure: final appFailure) => failure(appFailure),
    };
  }
}

final class MutationSuccess<T> extends MutationResult<T> {
  const MutationSuccess(this.data);

  final T data;
}

final class MutationFailure<T> extends MutationResult<T> {
  const MutationFailure(this.failure);

  final AppFailure failure;
}
