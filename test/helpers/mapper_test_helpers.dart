import 'dart:typed_data';

import 'package:prism_plurality/core/database/app_database.dart' as db;

// =============================================================================
// Shared factory functions for mapper tests.
//
// Each factory builds a DB row type with sensible defaults so that tests only
// need to override the fields they care about.
// =============================================================================

// -- Member -------------------------------------------------------------------

db.Member makeDbMember({
  String id = 'member-1',
  String name = 'Alice',
  String? pronouns = 'she/her',
  String emoji = '\u{1F338}',
  int? age = 25,
  String? bio = 'Hello world',
  Uint8List? avatarImageData,
  bool isActive = true,
  DateTime? createdAt,
  int displayOrder = 0,
  bool isAdmin = false,
  bool customColorEnabled = false,
  String? customColorHex,
  String? parentSystemId,
  String? pluralkitUuid,
  String? pluralkitId,
  bool markdownEnabled = false,
  int profileHeaderSource = 1,
  int profileHeaderLayout = 0,
  Uint8List? profileHeaderImageData,
  Uint8List? pkBannerImageData,
  String? pkBannerCachedUrl,
}) {
  return db.Member(
    id: id,
    name: name,
    pronouns: pronouns,
    emoji: emoji,
    age: age,
    bio: bio,
    avatarImageData: avatarImageData,
    isActive: isActive,
    createdAt: createdAt ?? DateTime(2025, 3, 1, 12, 0),
    displayOrder: displayOrder,
    isAdmin: isAdmin,
    customColorEnabled: customColorEnabled,
    customColorHex: customColorHex,
    parentSystemId: parentSystemId,
    pluralkitUuid: pluralkitUuid,
    pluralkitId: pluralkitId,
    markdownEnabled: markdownEnabled,
    profileHeaderSource: profileHeaderSource,
    profileHeaderLayout: profileHeaderLayout,
    profileHeaderImageData: profileHeaderImageData,
    pkBannerImageData: pkBannerImageData,
    pkBannerCachedUrl: pkBannerCachedUrl,
    pluralkitSyncIgnored: false,
    isDeleted: false,
    isAlwaysFronting: false,
  );
}

// -- FrontingSession ----------------------------------------------------------

db.FrontingSession makeDbFrontingSession({
  String id = 'session-1',
  int sessionType = 0,
  DateTime? startTime,
  DateTime? endTime,
  String? memberId = 'member-1',
  String? notes,
  int? confidence,
  int? quality,
  bool isHealthKitImport = false,
  String? pluralkitUuid,
  String? pkImportSource,
  String? pkFileSwitchId,
}) {
  // The `coFronterIds` and `pkMemberIdsJson` columns survive on the Drift table
  // for now (the mapper no longer reads or writes them after the per-member-
  // sessions refactor). Pass empty defaults so the row constructor is satisfied.
  return db.FrontingSession(
    id: id,
    sessionType: sessionType,
    startTime: startTime ?? DateTime(2025, 3, 1, 10, 0),
    endTime: endTime,
    memberId: memberId,
    coFronterIds: '[]',
    notes: notes,
    confidence: confidence,
    quality: quality,
    isHealthKitImport: isHealthKitImport,
    pluralkitUuid: pluralkitUuid,
    pkImportSource: pkImportSource,
    pkFileSwitchId: pkFileSwitchId,
    isDeleted: false,
  );
}

// -- Poll ---------------------------------------------------------------------

db.Poll makeDbPoll({
  String id = 'poll-1',
  String question = 'Favorite color?',
  bool isAnonymous = false,
  bool allowsMultipleVotes = false,
  bool isClosed = false,
  DateTime? expiresAt,
  DateTime? createdAt,
}) {
  return db.Poll(
    id: id,
    question: question,
    isAnonymous: isAnonymous,
    allowsMultipleVotes: allowsMultipleVotes,
    isClosed: isClosed,
    expiresAt: expiresAt,
    createdAt: createdAt ?? DateTime(2025, 3, 1, 12, 0),
    isDeleted: false,
  );
}

// -- CustomFieldRow -----------------------------------------------------------

db.CustomFieldRow makeDbCustomField({
  String id = 'field-1',
  String name = 'Role',
  int fieldType = 0,
  int? datePrecision,
  int displayOrder = 0,
  DateTime? createdAt,
}) {
  return db.CustomFieldRow(
    id: id,
    name: name,
    fieldType: fieldType,
    datePrecision: datePrecision,
    displayOrder: displayOrder,
    createdAt: createdAt ?? DateTime(2026, 3, 20, 12, 0),
    isDeleted: false,
  );
}

// -- MemberGroupRow -----------------------------------------------------------

db.MemberGroupRow makeDbMemberGroup({
  String id = 'group-1',
  String name = 'Subsystem A',
  String? description = 'A group',
  String? colorHex = '#FF5733',
  String? emoji = '\u{1F31F}',
  int displayOrder = 0,
  String? parentGroupId,
  int groupType = 0,
  String? filterRules,
  String? pluralkitId,
  String? pluralkitUuid,
  DateTime? lastSeenFromPkAt,
  bool syncSuppressed = false,
  String? suspectedPkGroupUuid,
  DateTime? createdAt,
}) {
  return db.MemberGroupRow(
    id: id,
    name: name,
    description: description,
    colorHex: colorHex,
    emoji: emoji,
    displayOrder: displayOrder,
    parentGroupId: parentGroupId,
    groupType: groupType,
    filterRules: filterRules,
    createdAt: createdAt ?? DateTime(2026, 3, 20, 12, 0),
    isDeleted: false,
    pluralkitId: pluralkitId,
    pluralkitUuid: pluralkitUuid,
    lastSeenFromPkAt: lastSeenFromPkAt,
    syncSuppressed: syncSuppressed,
    suspectedPkGroupUuid: suspectedPkGroupUuid,
  );
}

// -- NoteRow ------------------------------------------------------------------

db.NoteRow makeDbNote({
  String id = 'note-1',
  String title = 'Test Note',
  String body = 'Some content',
  String? colorHex,
  String? memberId,
  DateTime? date,
  DateTime? createdAt,
  DateTime? modifiedAt,
}) {
  return db.NoteRow(
    id: id,
    title: title,
    body: body,
    colorHex: colorHex,
    memberId: memberId,
    date: date ?? DateTime(2026, 3, 19),
    createdAt: createdAt ?? DateTime(2026, 3, 20, 12, 0),
    modifiedAt: modifiedAt ?? DateTime(2026, 3, 20, 14, 30),
    isDeleted: false,
  );
}

// -- FrontSessionCommentRow ---------------------------------------------------

db.FrontSessionCommentRow makeDbFrontSessionComment({
  String id = 'comment-1',
  String sessionId = 'session-1',
  String body = 'A comment',
  DateTime? timestamp,
  DateTime? createdAt,
}) {
  return db.FrontSessionCommentRow(
    id: id,
    sessionId: sessionId,
    body: body,
    timestamp: timestamp ?? DateTime(2026, 3, 20, 10, 45),
    createdAt: createdAt ?? DateTime(2026, 3, 20, 12, 0),
    isDeleted: false,
    targetTime: null,
    authorMemberId: null,
  );
}
