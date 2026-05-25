/// Thrown when a field's parentFieldId would violate the depth-1 cap.
class DepthLimitExceededException implements Exception {
  const DepthLimitExceededException(this.fieldId, this.parentFieldId);
  final String fieldId;
  final String parentFieldId;
  @override
  String toString() =>
      'DepthLimitExceededException: field $fieldId cannot nest under $parentFieldId — depth-1 cap';
}

/// Thrown when a per-member value is written for a group-typed field.
class InvalidFieldTypeException implements Exception {
  const InvalidFieldTypeException(this.fieldId, this.reason);
  final String fieldId;
  final String reason;
  @override
  String toString() => 'InvalidFieldTypeException: $fieldId — $reason';
}
