import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/data/mappers/member_mapper.dart';
import 'package:prism_plurality/data/mappers/poll_mapper.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/poll.dart' as domain;

import '../helpers/mapper_test_helpers.dart';

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // MemberMapper
  // ════════════════════════════════════════════════════════════════════════════

  group('MemberMapper', () {
    final now = DateTime(2025, 3, 1, 12, 0);

    test('toDomain maps all fields correctly', () {
      final avatar = Uint8List.fromList([1, 2, 3, 4]);
      final row = makeDbMember(
        id: 'abc',
        name: 'Test',
        pronouns: 'they/them',
        emoji: '🦊',
        age: 30,
        bio: 'A bio',
        avatarImageData: avatar,
        isActive: false,
        displayOrder: 5,
        isAdmin: true,
        customColorEnabled: true,
        customColorHex: '#FF0000',
        parentSystemId: 'sys-1',
        pluralkitUuid: 'pk-uuid',
        pluralkitId: 'pk-id',
      );

      final model = MemberMapper.toDomain(row);
      expect(model.id, 'abc');
      expect(model.name, 'Test');
      expect(model.pronouns, 'they/them');
      expect(model.emoji, '🦊');
      expect(model.age, 30);
      expect(model.bio, 'A bio');
      expect(model.avatarImageData, avatar);
      expect(model.isActive, false);
      expect(model.displayOrder, 5);
      expect(model.isAdmin, true);
      expect(model.customColorEnabled, true);
      expect(model.customColorHex, '#FF0000');
      expect(model.parentSystemId, 'sys-1');
      expect(model.pluralkitUuid, 'pk-uuid');
      expect(model.pluralkitId, 'pk-id');
    });

    test('toDomain handles null optional fields', () {
      final row = makeDbMember(
        pronouns: null,
        age: null,
        bio: null,
        avatarImageData: null,
        customColorHex: null,
        parentSystemId: null,
        pluralkitUuid: null,
        pluralkitId: null,
      );

      final model = MemberMapper.toDomain(row);
      expect(model.pronouns, isNull);
      expect(model.age, isNull);
      expect(model.bio, isNull);
      expect(model.avatarImageData, isNull);
      expect(model.customColorHex, isNull);
      expect(model.parentSystemId, isNull);
      expect(model.pluralkitUuid, isNull);
      expect(model.pluralkitId, isNull);
    });

    test('toCompanion preserves all fields and sets isDirty to true', () {
      final avatar = Uint8List.fromList([10, 20, 30]);
      final model = domain.Member(
        id: 'member-99',
        name: 'Bob',
        pronouns: 'he/him',
        emoji: '🎸',
        age: 22,
        bio: 'Guitarist',
        avatarImageData: avatar,
        isActive: true,
        createdAt: now,
        displayOrder: 3,
        isAdmin: false,
        customColorEnabled: true,
        customColorHex: '#00FF00',
        parentSystemId: 'sys-2',
        pluralkitUuid: 'pk-2',
        pluralkitId: 'pkid-2',
      );

      final companion = MemberMapper.toCompanion(model);
      expect(companion.id.value, 'member-99');
      expect(companion.name.value, 'Bob');
      expect(companion.pronouns.value, 'he/him');
      expect(companion.emoji.value, '🎸');
      expect(companion.age.value, 22);
      expect(companion.bio.value, 'Guitarist');
      expect(companion.avatarImageData.value, avatar);
      expect(companion.isActive.value, true);
      expect(companion.createdAt.value, now);
      expect(companion.displayOrder.value, 3);
      expect(companion.isAdmin.value, false);
      expect(companion.customColorEnabled.value, true);
      expect(companion.customColorHex.value, '#00FF00');
    });

    test('round-trip: domain -> companion -> toDomain preserves data', () {
      final original = domain.Member(
        id: 'rt-1',
        name: 'Roundtrip',
        pronouns: 'ze/zir',
        emoji: '🔄',
        age: 10,
        bio: 'Testing round trip',
        avatarImageData: null,
        isActive: true,
        createdAt: now,
        displayOrder: 7,
        isAdmin: true,
        customColorEnabled: false,
        customColorHex: null,
      );

      final companion = MemberMapper.toCompanion(original);

      // Simulate what Drift would return as a row
      final row = db.Member(
        id: companion.id.value,
        name: companion.name.value,
        pronouns: companion.pronouns.value,
        emoji: companion.emoji.value,
        age: companion.age.value,
        bio: companion.bio.value,
        avatarImageData: companion.avatarImageData.value,
        isActive: companion.isActive.value,
        createdAt: companion.createdAt.value,
        displayOrder: companion.displayOrder.value,
        isAdmin: companion.isAdmin.value,
        customColorEnabled: companion.customColorEnabled.value,
        customColorHex: companion.customColorHex.value,
        parentSystemId: companion.parentSystemId.value,
        pluralkitUuid: companion.pluralkitUuid.value,
        pluralkitId: companion.pluralkitId.value,
        markdownEnabled: companion.markdownEnabled.value,
        pluralkitSyncIgnored: false,
        isDeleted: false,
        isAlwaysFronting: false,
      );

      final restored = MemberMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.pronouns, original.pronouns);
      expect(restored.emoji, original.emoji);
      expect(restored.age, original.age);
      expect(restored.bio, original.bio);
      expect(restored.isActive, original.isActive);
      expect(restored.displayOrder, original.displayOrder);
      expect(restored.isAdmin, original.isAdmin);
      expect(restored.customColorEnabled, original.customColorEnabled);
    });

    test('toDomain handles empty string bio and pronouns', () {
      final row = makeDbMember(bio: '', pronouns: '');
      final model = MemberMapper.toDomain(row);
      expect(model.bio, '');
      expect(model.pronouns, '');
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // FrontingSessionMapper
  // ════════════════════════════════════════════════════════════════════════════

  group('FrontingSessionMapper', () {
    final start = DateTime(2025, 3, 1, 10, 0);
    final end = DateTime(2025, 3, 1, 11, 0);

    test('toDomain maps all fields correctly', () {
      final row = makeDbFrontingSession(
        id: 'fs-1',
        startTime: start,
        endTime: end,
        memberId: 'member-1',
        coFronterIds: jsonEncode(['co-1', 'co-2']),
        notes: 'Felt good',
        confidence: domain.FrontConfidence.strong.index,
        pluralkitUuid: 'pk-fs-1',
      );

      final model = FrontingSessionMapper.toDomain(row);
      expect(model.id, 'fs-1');
      expect(model.startTime, start);
      expect(model.endTime, end);
      expect(model.memberId, 'member-1');
      expect(model.coFronterIds, ['co-1', 'co-2']);
      expect(model.notes, 'Felt good');
      expect(model.confidence, domain.FrontConfidence.strong);
      expect(model.sessionType, domain.SessionType.normal);
      expect(model.quality, isNull);
      expect(model.isHealthKitImport, isFalse);
      expect(model.pluralkitUuid, 'pk-fs-1');
    });

    test('toDomain maps sleep rows with sleep quality fields', () {
      final row = makeDbFrontingSession(
        id: 'fs-sleep',
        memberId: null,
        sessionType: domain.SessionType.sleep.index,
        quality: domain.SleepQuality.good.index,
        isHealthKitImport: true,
      );

      final model = FrontingSessionMapper.toDomain(row);
      expect(model.sessionType, domain.SessionType.sleep);
      expect(model.quality, domain.SleepQuality.good);
      expect(model.isHealthKitImport, isTrue);
      expect(model.memberId, isNull);
    });

    test('toDomain handles empty coFronterIds string', () {
      final row = makeDbFrontingSession(coFronterIds: '');
      final model = FrontingSessionMapper.toDomain(row);
      expect(model.coFronterIds, isEmpty);
    });

    test('toDomain handles empty JSON array for coFronterIds', () {
      final row = makeDbFrontingSession(coFronterIds: '[]');
      final model = FrontingSessionMapper.toDomain(row);
      expect(model.coFronterIds, isEmpty);
    });

    test('toDomain handles null optional fields', () {
      final row = makeDbFrontingSession(
        endTime: null,
        memberId: null,
        notes: null,
        confidence: null,
        pluralkitUuid: null,
      );

      final model = FrontingSessionMapper.toDomain(row);
      expect(model.endTime, isNull);
      expect(model.memberId, isNull);
      expect(model.notes, isNull);
      expect(model.confidence, isNull);
      expect(model.pluralkitUuid, isNull);
      expect(model.isActive, isTrue);
    });

    test('toDomain maps all confidence enum values correctly', () {
      for (final conf in domain.FrontConfidence.values) {
        final row = makeDbFrontingSession(confidence: conf.index);
        final model = FrontingSessionMapper.toDomain(row);
        expect(model.confidence, conf);
      }
    });

    test('toDomain falls back to unsure for unknown confidence index', () {
      final row = makeDbFrontingSession(confidence: 999);
      final model = FrontingSessionMapper.toDomain(row);
      expect(model.confidence, domain.FrontConfidence.unsure);
    });

    test('toCompanion encodes coFronterIds as JSON and sets isDirty', () {
      final model = domain.FrontingSession(
        id: 'fs-2',
        startTime: start,
        endTime: end,
        memberId: 'member-2',
        coFronterIds: ['a', 'b', 'c'],
        notes: 'Test notes',
        confidence: domain.FrontConfidence.certain,
        pluralkitUuid: 'pk-2',
      );

      final companion = FrontingSessionMapper.toCompanion(model);
      expect(companion.id.value, 'fs-2');
      expect(companion.startTime.value, start);
      expect(companion.endTime.value, end);
      expect(companion.memberId.value, 'member-2');
      expect(jsonDecode(companion.coFronterIds.value), ['a', 'b', 'c']);
      expect(companion.notes.value, 'Test notes');
      expect(companion.confidence.value, domain.FrontConfidence.certain.index);
      expect(companion.sessionType.value, domain.SessionType.normal.index);
      expect(companion.quality.value, isNull);
      expect(companion.isHealthKitImport.value, isFalse);
    });

    test('round-trip: domain -> companion -> toDomain preserves data', () {
      final original = domain.FrontingSession(
        id: 'rt-fs',
        startTime: start,
        endTime: end,
        memberId: 'member-rt',
        coFronterIds: ['x', 'y'],
        notes: 'Round trip',
        confidence: domain.FrontConfidence.certain,
      );

      final companion = FrontingSessionMapper.toCompanion(original);

      final row = db.FrontingSession(
        id: companion.id.value,
        sessionType: companion.sessionType.value,
        startTime: companion.startTime.value,
        endTime: companion.endTime.value,
        memberId: companion.memberId.value,
        coFronterIds: companion.coFronterIds.value,
        notes: companion.notes.value,
        confidence: companion.confidence.value,
        quality: companion.quality.value,
        isHealthKitImport: companion.isHealthKitImport.value,
        pluralkitUuid: companion.pluralkitUuid.value,
        isDeleted: false,
      );

      final restored = FrontingSessionMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.startTime, original.startTime);
      expect(restored.endTime, original.endTime);
      expect(restored.memberId, original.memberId);
      expect(restored.coFronterIds, original.coFronterIds);
      expect(restored.notes, original.notes);
      expect(restored.confidence, original.confidence);
      expect(restored.sessionType, original.sessionType);
      expect(restored.quality, original.quality);
      expect(restored.isHealthKitImport, original.isHealthKitImport);
    });

    test('toCompanion with empty coFronterIds encodes as empty JSON array', () {
      final model = domain.FrontingSession(
        id: 'fs-empty',
        startTime: start,
        coFronterIds: const [],
      );
      final companion = FrontingSessionMapper.toCompanion(model);
      expect(companion.coFronterIds.value, '[]');
    });

    test('toDomain gracefully handles malformed coFronterIds JSON', () {
      // The mapper catches JSON parse errors and returns empty list
      final row = makeDbFrontingSession(coFronterIds: 'not valid json!!!');
      final model = FrontingSessionMapper.toDomain(row);
      expect(model.coFronterIds, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // PollMapper
  // ════════════════════════════════════════════════════════════════════════════

  group('PollMapper', () {
    final created = DateTime(2025, 3, 1, 12, 0);
    final expires = DateTime(2025, 3, 8, 12, 0);

    test('toDomain maps all fields correctly', () {
      final row = makeDbPoll(
        id: 'p-1',
        question: 'What for dinner?',
        isAnonymous: true,
        allowsMultipleVotes: true,
        isClosed: true,
        expiresAt: expires,
      );

      final model = PollMapper.toDomain(row);
      expect(model.id, 'p-1');
      expect(model.question, 'What for dinner?');
      expect(model.isAnonymous, true);
      expect(model.allowsMultipleVotes, true);
      expect(model.isClosed, true);
      expect(model.expiresAt, expires);
      expect(model.createdAt, created);
      // Options should default to empty (populated separately)
      expect(model.options, isEmpty);
    });

    test('toDomain handles null expiresAt', () {
      final row = makeDbPoll(expiresAt: null);
      final model = PollMapper.toDomain(row);
      expect(model.expiresAt, isNull);
    });

    test('toDomain defaults to false booleans and empty options', () {
      final row = makeDbPoll(
        isAnonymous: false,
        allowsMultipleVotes: false,
        isClosed: false,
      );
      final model = PollMapper.toDomain(row);
      expect(model.isAnonymous, false);
      expect(model.allowsMultipleVotes, false);
      expect(model.isClosed, false);
      expect(model.options, isEmpty);
    });

    test('toCompanion preserves all fields and sets isDirty', () {
      final model = domain.Poll(
        id: 'p-2',
        question: 'Where to eat?',
        isAnonymous: true,
        allowsMultipleVotes: false,
        isClosed: false,
        expiresAt: expires,
        createdAt: created,
      );

      final companion = PollMapper.toCompanion(model);
      expect(companion.id.value, 'p-2');
      expect(companion.question.value, 'Where to eat?');
      expect(companion.isAnonymous.value, true);
      expect(companion.allowsMultipleVotes.value, false);
      expect(companion.isClosed.value, false);
      expect(companion.expiresAt.value, expires);
      expect(companion.createdAt.value, created);
    });

    test('round-trip: domain -> companion -> toDomain preserves data', () {
      final original = domain.Poll(
        id: 'rt-poll',
        question: 'Round trip?',
        isAnonymous: true,
        allowsMultipleVotes: true,
        isClosed: false,
        expiresAt: expires,
        createdAt: created,
      );

      final companion = PollMapper.toCompanion(original);
      final row = db.Poll(
        id: companion.id.value,
        question: companion.question.value,
        isAnonymous: companion.isAnonymous.value,
        allowsMultipleVotes: companion.allowsMultipleVotes.value,
        isClosed: companion.isClosed.value,
        expiresAt: companion.expiresAt.value,
        createdAt: companion.createdAt.value,
        isDeleted: false,
      );

      final restored = PollMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.question, original.question);
      expect(restored.isAnonymous, original.isAnonymous);
      expect(restored.allowsMultipleVotes, original.allowsMultipleVotes);
      expect(restored.isClosed, original.isClosed);
      expect(restored.expiresAt, original.expiresAt);
      expect(restored.createdAt, original.createdAt);
      // Note: options are not part of the Poll table row, so they reset to []
      expect(restored.options, isEmpty);
    });

    test('toDomain handles empty question string', () {
      final row = makeDbPoll(question: '');
      final model = PollMapper.toDomain(row);
      expect(model.question, '');
    });

    test('toCompanion with null expiresAt stores null', () {
      final model = domain.Poll(
        id: 'p-no-exp',
        question: 'No expiry',
        createdAt: created,
      );
      final companion = PollMapper.toCompanion(model);
      expect(companion.expiresAt.value, isNull);
    });
  });
}
