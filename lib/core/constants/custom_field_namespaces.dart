import 'dart:convert';

import 'package:uuid/uuid.dart';

/// Namespace for custom-field value row ids.
///
/// Key format: JSON array `[customFieldId, memberId]`.
/// Custom-field values are logically unique per field/member pair. Deriving
/// new row ids from that pair keeps paired devices from independently
/// creating different rows that collide on the active `(field, member)` index.
const String customFieldValueNamespace = '120aebca-b7b8-4266-bd30-033477d7faea';

String deriveCustomFieldValueId({
  required String customFieldId,
  required String memberId,
}) {
  return const Uuid().v5(
    customFieldValueNamespace,
    jsonEncode([customFieldId, memberId]),
  );
}
