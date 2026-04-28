// Shared fixture helpers for the member_groups / member_group_entries /
// members test rows that PK-related tests need. These were originally
// copy-pasted across ~7 test files — centralizing them cuts maintenance
// cost and makes new tests consistent by default.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';

MemberGroupsCompanion pkFixtureGroup({
  required String id,
  String? name,
  DateTime? createdAt,
  int displayOrder = 0,
  String? parentGroupId,
  String? pluralkitUuid,
  DateTime? lastSeenFromPkAt,
  bool syncSuppressed = false,
  String? suspectedPkGroupUuid,
  bool isDeleted = false,
}) => MemberGroupsCompanion.insert(
  id: id,
  name: name ?? id,
  createdAt: createdAt ?? DateTime(2024, 1, 1),
  displayOrder: Value(displayOrder),
  parentGroupId: Value(parentGroupId),
  pluralkitUuid: Value(pluralkitUuid),
  lastSeenFromPkAt: Value(lastSeenFromPkAt),
  syncSuppressed: Value(syncSuppressed),
  suspectedPkGroupUuid: Value(suspectedPkGroupUuid),
  isDeleted: Value(isDeleted),
);

MembersCompanion pkFixtureMember({
  required String id,
  required String name,
  DateTime? createdAt,
  String? pluralkitUuid,
}) => MembersCompanion.insert(
  id: id,
  name: name,
  createdAt: createdAt ?? DateTime(2024, 1, 1),
  pluralkitUuid: Value(pluralkitUuid),
);

MemberGroupEntriesCompanion pkFixtureEntry({
  required String id,
  required String groupId,
  required String memberId,
  String? pkGroupUuid,
  String? pkMemberUuid,
  bool isDeleted = false,
}) => MemberGroupEntriesCompanion.insert(
  id: id,
  groupId: groupId,
  memberId: memberId,
  pkGroupUuid: Value(pkGroupUuid),
  pkMemberUuid: Value(pkMemberUuid),
  isDeleted: Value(isDeleted),
);

/// `sha256(pkGroupUuid || 0x00 || pkMemberUuid)[:16]`: the canonical entry id
/// used by the CRDT layer for PK-backed memberships.
String pkFixtureCanonicalEntryId(String pkGroupUuid, String pkMemberUuid) {
  final joined = '$pkGroupUuid\x00$pkMemberUuid';
  final digest = sha256.convert(utf8.encode(joined));
  return digest.toString().substring(0, 16);
}
