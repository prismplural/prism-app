import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_push_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

// ---------------------------------------------------------------------------
// Fake PluralKitClient that records calls
// ---------------------------------------------------------------------------

class Call {
  final String method;
  final List<dynamic> args;
  Call(this.method, this.args);
}

class FakePluralKitClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  final List<Call> calls = [];

  String nextMemberId = 'abcde';

  @override
  String get currentToken => 'fake-token';

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) async {
    calls.add(Call('createMember', [data]));
    return PKMember(
      id: nextMemberId,
      uuid: 'uuid-$nextMemberId',
      name: data['name'] as String? ?? '',
    );
  }

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) async {
    calls.add(Call('updateMember', [id, data]));
    return PKMember(
      id: id,
      uuid: 'uuid-$id',
      name: data['name'] as String? ?? '',
    );
  }

  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async {
    calls.add(Call('createSwitch', [memberIds, timestamp]));
    return PKSwitch(
      id: 'sw-001',
      timestamp: timestamp ?? DateTime.now(),
      members: memberIds,
    );
  }

  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) => throw UnimplementedError();

  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  // -- unused stubs ----------------------------------------------------------

  @override
  Future<PKSystem> getSystem() => throw UnimplementedError();
  @override
  Future<List<PKMember>> getMembers() => throw UnimplementedError();
  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();
  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) =>
      throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();
  @override
  Future<List<int>> downloadBytes(String url) => throw UnimplementedError();
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];
  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];
  @override
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();
  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();
  @override
  Future<PKSwitch?> getCurrentFronters() => throw UnimplementedError();
  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

domain.Member _member({
  String id = 'local-1',
  String name = 'Alice',
  String? pronouns,
  String? bio,
  String? pluralkitId,
  String? displayName,
  String? pluralkitDisplayName,
  String? customColorHex,
  bool customColorEnabled = false,
  String? proxyTagsJson,
  String? birthday,
}) {
  return domain.Member(
    id: id,
    name: name,
    pronouns: pronouns,
    bio: bio,
    pluralkitId: pluralkitId,
    displayName: displayName,
    pluralkitDisplayName: pluralkitDisplayName,
    customColorHex: customColorHex,
    customColorEnabled: customColorEnabled,
    proxyTagsJson: proxyTagsJson,
    birthday: birthday,
    createdAt: DateTime(2026, 1, 1),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakePluralKitClient fakeClient;
  late PkPushService pushService;

  setUp(() {
    fakeClient = FakePluralKitClient();
    pushService = const PkPushService();
  });

  group('pushMember', () {
    test('with existing pluralkitId calls updateMember', () async {
      final member = _member(pluralkitId: 'pk123', name: 'Bob');

      final resultId = await pushService.pushMember(member, fakeClient);

      expect(resultId, 'pk123');
      expect(fakeClient.calls.length, 1);
      expect(fakeClient.calls.first.method, 'updateMember');
      expect(fakeClient.calls.first.args[0], 'pk123');
    });

    test('without pluralkitId calls createMember', () async {
      fakeClient.nextMemberId = 'new01';
      final member = _member(name: 'Carol');

      final resultId = await pushService.pushMember(member, fakeClient);

      expect(resultId, 'new01');
      expect(fakeClient.calls.length, 1);
      expect(fakeClient.calls.first.method, 'createMember');
    });
  });

  group('_memberToPayload (tested via pushMember)', () {
    test('strips # from color', () async {
      final member = _member(
        customColorHex: '#7C3AED',
        customColorEnabled: true,
      );

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['color'], '7C3AED');
    });

    test('omits null pronouns', () async {
      final member = _member(pronouns: null);

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data.containsKey('pronouns'), isFalse);
    });

    test('omits null bio', () async {
      final member = _member(bio: null);

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data.containsKey('description'), isFalse);
    });

    test('includes pronouns when present', () async {
      final member = _member(pronouns: 'she/her');

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['pronouns'], 'she/her');
    });

    test('includes bio when present', () async {
      final member = _member(bio: 'Hello world');

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['description'], 'Hello world');
    });

    test('includes proxy tags when present', () async {
      final member = _member(proxyTagsJson: '[{"prefix":"A:","suffix":null}]');

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['proxy_tags'], [
        {'prefix': 'A:', 'suffix': null},
      ]);
    });

    test('create uses Prism Name for PK internal name', () async {
      final member = _member(name: 'Ada', displayName: 'Ada Lovelace');

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['name'], 'Ada');
    });

    test('create POST includes name + non-null fields, omits nulls', () async {
      // CREATE path must be unchanged by H1 gating: it ignores allowedFields,
      // requires `name`, includes local non-null fields, and omits nulls.
      final member = _member(
        name: 'Ada',
        pronouns: 'she/her',
        bio: null, // omitted
        // no pluralkitId → POST
      );

      await pushService.pushMember(
        member,
        fakeClient,
        allowedFields: {'description'}, // must be ignored on POST
      );

      expect(fakeClient.calls.first.method, 'createMember');
      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['name'], 'Ada');
      expect(data['pronouns'], 'she/her');
      expect(data.containsKey('description'), isFalse);
    });

    test(
      'patch omits PK internal name and sends PluralKit Display Name',
      () async {
        final member = _member(
          name: 'Prism Name',
          displayName: 'Local Full Name',
          pluralkitDisplayName: 'PK Display',
          pluralkitId: 'pk123',
        );

        await pushService.pushMember(member, fakeClient);

        final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
        expect(data.containsKey('name'), isFalse);
        expect(data['display_name'], 'PK Display');
      },
    );

    test('includes empty proxy tag list for explicit local clear', () async {
      final member = _member(proxyTagsJson: '[]');

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['proxy_tags'], isEmpty);
    });

    test('omits proxy tags when caller disables them', () async {
      final member = _member(proxyTagsJson: '[]');

      await pushService.pushMember(member, fakeClient, includeProxyTags: false);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data.containsKey('proxy_tags'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // H1: per-field-gated PATCH payload — keys outside `allowedFields` are
  // omitted (PK preserves) and gated fields never emit explicit `null`, so
  // one edit can't null-clear an unrelated PK-only field.
  // -------------------------------------------------------------------------

  group('_memberToPayload PATCH gating (H1)', () {
    PKMember pk({
      String? pronouns,
      String? description,
      String? color,
    }) => PKMember(
      id: 'pk123',
      uuid: 'uuid-pk123',
      name: 'Alice',
      pronouns: pronouns,
      description: description,
      color: color,
    );

    test('includes only the allowed field, omits all others', () async {
      final member = _member(
        pluralkitId: 'pk123',
        bio: 'new bio',
        pronouns: 'she/her',
      );

      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pk(pronouns: 'they/them', description: 'old bio'),
        allowedFields: {'description'},
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['description'], 'new bio');
      expect(data.containsKey('pronouns'), isFalse);
      expect(data.containsKey('name'), isFalse);
    });

    test(
      'local pronouns null + PK pronouns set: no pronouns key (H1 regression)',
      () async {
        final member = _member(
          pluralkitId: 'pk123',
          bio: 'new bio',
          pronouns: null,
        );

        await pushService.pushMember(
          member,
          fakeClient,
          pkMember: pk(pronouns: 'he/him', description: 'old bio'),
          allowedFields: {'description'},
        );

        final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
        expect(data['description'], 'new bio');
        expect(
          data.containsKey('pronouns'),
          isFalse,
          reason: 'a bio edit must not null-clear PK-only pronouns',
        );
      },
    );

    test(
      'gated allowed field that is null locally is omitted, never null',
      () async {
        // Defensive: even if 'pronouns' were (incorrectly) in the allowed set
        // while local is null, the gated path must omit rather than send null.
        final member = _member(
          pluralkitId: 'pk123',
          bio: 'new bio',
          pronouns: null,
        );

        await pushService.pushMember(
          member,
          fakeClient,
          pkMember: pk(pronouns: 'he/him', description: 'old bio'),
          allowedFields: {'description', 'pronouns'},
        );

        final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
        expect(data['description'], 'new bio');
        expect(data.containsKey('pronouns'), isFalse);
      },
    );

    test('pull-only field excluded from set never appears in payload', () async {
      // color differs but is not in allowedFields (pull-only at the call site).
      final member = _member(
        pluralkitId: 'pk123',
        bio: 'new bio',
        customColorHex: '#abcdef',
        customColorEnabled: true,
      );

      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pk(description: 'old bio', color: '123456'),
        allowedFields: {'description'},
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['description'], 'new bio');
      expect(data.containsKey('color'), isFalse);
    });

    test('proxy_tags gated by allowedFields membership', () async {
      final member = _member(
        pluralkitId: 'pk123',
        bio: 'new bio',
        proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
      );

      // proxy_tags NOT in the allowed set → omitted even though present.
      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pk(description: 'old bio'),
        allowedFields: {'description'},
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data.containsKey('proxy_tags'), isFalse);
    });

    test('legacy PATCH (no allowedFields) still sends local non-null fields', ()
        async {
      // No allowedFields and no pkMember: the sync-service auto-push shape.
      final member = _member(
        pluralkitId: 'pk123',
        bio: 'hi',
        pronouns: 'she/her',
      );

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['description'], 'hi');
      expect(data['pronouns'], 'she/her');
      // No remote snapshot → no explicit nulls to clear absent fields.
      expect(data.containsKey('birthday'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // M10b: client-side validation of PK caps — PATCH drops the offending
  // field (never silent truncation), POST truncates only the required
  // `name`, both surface via onFieldSkipped. Caps live-verified 2026-06-10.
  // -------------------------------------------------------------------------

  group('PkFieldLimits payload validation (M10b)', () {
    const pkSnapshot = PKMember(
      id: 'pk123',
      uuid: 'uuid-pk123',
      name: 'Alice',
      description: 'old bio',
      pronouns: 'they/them',
      displayName: 'Old Display',
    );

    test('over-cap description is dropped from PATCH and surfaced', () async {
      final skips = <(String, String)>[];
      final member = _member(
        pluralkitId: 'pk123',
        bio: 'x' * 1001,
        pronouns: 'she/her',
      );

      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pkSnapshot,
        allowedFields: {'description', 'pronouns'},
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      expect(fakeClient.calls, hasLength(1));
      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(
        data.containsKey('description'),
        isFalse,
        reason: 'over-cap field must be skipped, not truncated, on PATCH',
      );
      expect(data['pronouns'], 'she/her');
      expect(skips, hasLength(1));
      expect(skips.single.$1, 'description');
      expect(
        skips.single.$2,
        contains('is 1001 characters (PluralKit max 1000)'),
      );
    });

    test('over-cap display_name dropped; empty payload becomes a no-op', () async {
      final skips = <(String, String)>[];
      final member = _member(
        pluralkitId: 'pk123',
        pluralkitDisplayName: 'd' * 101,
      );

      final result = await pushService.pushMemberFull(
        member,
        fakeClient,
        pkMember: pkSnapshot,
        allowedFields: {'display_name'},
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      // The only allowed field was dropped → empty PATCH would 400, so the
      // existing empty-payload guard returns the snapshot without a call.
      expect(fakeClient.calls, isEmpty);
      expect(result.id, 'pk123');
      expect(skips.single.$1, 'display_name');
      expect(
        skips.single.$2,
        contains('is 101 characters (PluralKit max 100)'),
      );
    });

    test('over-cap pronouns dropped on PATCH', () async {
      final skips = <(String, String)>[];
      final member = _member(
        pluralkitId: 'pk123',
        pronouns: 'p' * 101,
        bio: 'fine',
      );

      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pkSnapshot,
        allowedFields: {'pronouns', 'description'},
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data.containsKey('pronouns'), isFalse);
      expect(data['description'], 'fine');
      expect(skips.single.$1, 'pronouns');
    });

    test('non-6-hex color remnant is skipped and surfaced', () async {
      final skips = <(String, String)>[];
      final member = _member(
        pluralkitId: 'pk123',
        bio: 'fine',
        customColorHex: '#12 34', // strips to '12 34' — not 6 hex digits
        customColorEnabled: true,
      );

      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pkSnapshot,
        allowedFields: {'color', 'description'},
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data.containsKey('color'), isFalse);
      expect(data['description'], 'fine');
      expect(skips.single.$1, 'color');
      expect(skips.single.$2, contains("isn't a 6-digit hex color"));
    });

    test('valid 6-hex color passes validation untouched', () async {
      final skips = <(String, String)>[];
      final member = _member(
        pluralkitId: 'pk123',
        customColorHex: '#7C3AED',
        customColorEnabled: true,
      );

      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pkSnapshot,
        allowedFields: {'color'},
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['color'], '7C3AED');
      expect(skips, isEmpty);
    });

    test('junk birthday strings are skipped (legacy import garbage)', () async {
      final skips = <(String, String)>[];
      // Legacy PATCH shape (no allowedFields / pkMember): every local
      // non-null field is included — including a raw-column birthday that
      // predates wire validation.
      final member = _member(
        pluralkitId: 'pk123',
        pronouns: 'she/her',
        birthday: 'July 15th, 1993',
      );

      await pushService.pushMember(
        member,
        fakeClient,
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data.containsKey('birthday'), isFalse);
      expect(data['pronouns'], 'she/her');
      expect(skips.single.$1, 'birthday');
      expect(skips.single.$2, contains("isn't a valid yyyy-MM-dd date"));
    });

    test('calendar-invalid birthday (02-30) is skipped', () async {
      final skips = <(String, String)>[];
      final member = _member(pluralkitId: 'pk123', birthday: '1990-02-30');

      final result = await pushService.pushMemberFull(
        member,
        fakeClient,
        pkMember: pkSnapshot,
        allowedFields: {'birthday'},
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      expect(fakeClient.calls, isEmpty);
      expect(result.id, 'pk123');
      expect(skips.single.$1, 'birthday');
    });

    test('sentinel birthday 0004-02-29 passes validation', () async {
      final skips = <(String, String)>[];
      final member = _member(pluralkitId: 'pk123', birthday: '0004-02-29');

      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pkSnapshot,
        allowedFields: {'birthday'},
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['birthday'], '0004-02-29');
      expect(skips, isEmpty);
    });

    test('create truncates the required name instead of failing', () async {
      final skips = <(String, String)>[];
      final member = _member(name: 'n' * 150); // no pluralkitId → POST

      await pushService.pushMember(
        member,
        fakeClient,
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      expect(fakeClient.calls.first.method, 'createMember');
      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect((data['name'] as String).length, 100);
      expect(data['name'], 'n' * 100);
      expect(skips.single.$1, 'name');
      expect(skips.single.$2, contains('truncated to 100 characters'));
    });

    test('create-name truncation never splits a surrogate pair', () async {
      final member = _member(name: '${'a' * 99}\u{1F600}'); // 99 + 2 units

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      // Cutting at 100 would leave a lone high surrogate — back off to 99.
      expect((data['name'] as String).length, 99);
      expect(data['name'], 'a' * 99);
    });

    test('create drops over-cap optional fields like PATCH does', () async {
      final skips = <(String, String)>[];
      final member = _member(name: 'Ada', bio: 'x' * 1001);

      await pushService.pushMember(
        member,
        fakeClient,
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      expect(fakeClient.calls.first.method, 'createMember');
      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['name'], 'Ada');
      expect(data.containsKey('description'), isFalse);
      expect(skips.single.$1, 'description');
    });

    test('explicit-null clears are exempt from validation', () async {
      // Legacy ungated PATCH with a remote snapshot: local null + remote set
      // emits an explicit null clear, which must pass through untouched.
      final skips = <(String, String)>[];
      final member = _member(pluralkitId: 'pk123', bio: null, pronouns: 'x/y');

      await pushService.pushMember(
        member,
        fakeClient,
        pkMember: pkSnapshot,
        onFieldSkipped: (field, reason) => skips.add((field, reason)),
      );

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data.containsKey('description'), isTrue);
      expect(data['description'], isNull);
      expect(skips, isEmpty);
    });
  });

  group('pushSwitch', () {
    test('calls createSwitch with correct IDs', () async {
      final ids = ['pk001', 'pk002'];

      final result = await pushService.pushSwitch(ids, fakeClient);

      expect(result.members, ids);
      expect(fakeClient.calls.length, 1);
      expect(fakeClient.calls.first.method, 'createSwitch');
      expect(fakeClient.calls.first.args[0], ids);
    });

    test('passes timestamp when provided', () async {
      final ts = DateTime(2026, 3, 15, 10, 30);

      await pushService.pushSwitch(['pk001'], fakeClient, timestamp: ts);

      expect(fakeClient.calls.first.args[1], ts);
    });

    test('wraps 404 as PkStaleLinkException with switchRecord kind', () async {
      final throwing = _Throw404OnCreateSwitchClient();
      expect(
        () => pushService.pushSwitch(['pk001'], throwing),
        throwsA(
          isA<PkStaleLinkException>().having(
            (e) => e.kind,
            'kind',
            PkStaleLinkKind.switchRecord,
          ),
        ),
      );
    });

    test('non-404 errors are not wrapped as stale-link', () async {
      final throwing = _Throw500OnCreateSwitchClient();
      expect(
        () => pushService.pushSwitch(['pk001'], throwing),
        throwsA(
          isA<PluralKitApiError>().having(
            (e) => e is PkStaleLinkException,
            'isStale',
            false,
          ),
        ),
      );
    });
  });

  _registerDeletionTests();
}

class _Throw404OnCreateSwitchClient extends FakePluralKitClient {
  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async => throw const PluralKitApiError(404, 'not found');
}

class _Throw500OnCreateSwitchClient extends FakePluralKitClient {
  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) async => throw const PluralKitApiError(500, 'boom');
}

// ---------------------------------------------------------------------------
// Plan 02 — deletion test fakes
// ---------------------------------------------------------------------------

/// Programmable fake: each call to deleteMember/deleteSwitch consumes the
/// next status code from the configured script. `null` = success (204).
/// `429` triggers a [PluralKitRateLimitError]; other ints throw
/// [PluralKitApiError] with that status. Lets us exercise the 429-retry
/// path deterministically.
class _ScriptedDeletionClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
  final List<int?> memberScript;
  final List<int?> switchScript;
  int memberCalls = 0;
  int switchCalls = 0;

  @override
  String get currentToken => 'fake-token';

  _ScriptedDeletionClient({
    this.memberScript = const [],
    this.switchScript = const [],
  });

  @override
  Future<void> deleteMember(String id) async {
    final status = memberScript[memberCalls++];
    if (status == null) return;
    if (status == 429) {
      throw const PluralKitRateLimitError('rate limited', Duration.zero);
    }
    throw PluralKitApiError(status, 'err');
  }

  @override
  Future<void> deleteSwitch(String switchId) async {
    final status = switchScript[switchCalls++];
    if (status == null) return;
    if (status == 429) {
      throw const PluralKitRateLimitError('rate limited', Duration.zero);
    }
    throw PluralKitApiError(status, 'err');
  }

  // -- unused stubs ----------------------------------------------------------
  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) => throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) => throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) => throw UnimplementedError();
  @override
  Future<PKSystem> getSystem() => throw UnimplementedError();
  @override
  Future<List<PKMember>> getMembers() => throw UnimplementedError();
  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();
  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) =>
      throw UnimplementedError();
  @override
  Future<List<int>> downloadBytes(String url) => throw UnimplementedError();
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];
  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];
  @override
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();
  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();
  @override
  Future<PKSwitch?> getCurrentFronters() => throw UnimplementedError();
  @override
  void dispose() {}
}

void _registerDeletionTests() {
  group('pushMemberDeletion', () {
    test('204 success completes normally', () async {
      final client = _ScriptedDeletionClient(memberScript: [null]);
      const svc = PkPushService();
      await svc.pushMemberDeletion('local-1', 'pk123', client);
      expect(client.memberCalls, 1);
    });

    test('404 swallowed as success (R4 gated by caller)', () async {
      final client = _ScriptedDeletionClient(memberScript: [404]);
      const svc = PkPushService();
      await svc.pushMemberDeletion('local-1', 'pk123', client);
      expect(client.memberCalls, 1);
    });

    test('403 throws PkDeletionForbiddenException', () async {
      final client = _ScriptedDeletionClient(memberScript: [403]);
      const svc = PkPushService();
      await expectLater(
        svc.pushMemberDeletion('local-1', 'pk123', client),
        throwsA(
          isA<PkDeletionForbiddenException>()
              .having((e) => e.kind, 'kind', PkStaleLinkKind.member)
              .having((e) => e.localId, 'localId', 'local-1')
              .having((e) => e.pkId, 'pkId', 'pk123'),
        ),
      );
    });

    test('429 propagates — retry is handled inside PluralKitClient', () async {
      final client = _ScriptedDeletionClient(memberScript: [429]);
      const svc = PkPushService();
      await expectLater(
        svc.pushMemberDeletion('local-1', 'pk123', client),
        throwsA(isA<PluralKitRateLimitError>()),
      );
    });
  });

  group('pushSwitchDeletion', () {
    test('204 success completes normally', () async {
      final client = _ScriptedDeletionClient(switchScript: [null]);
      const svc = PkPushService();
      await svc.pushSwitchDeletion('sess-1', 'uuid-1', client);
      expect(client.switchCalls, 1);
    });

    test('404 swallowed as success', () async {
      final client = _ScriptedDeletionClient(switchScript: [404]);
      const svc = PkPushService();
      await svc.pushSwitchDeletion('sess-1', 'uuid-1', client);
      expect(client.switchCalls, 1);
    });

    test(
      '403 throws PkDeletionForbiddenException with switchRecord kind',
      () async {
        final client = _ScriptedDeletionClient(switchScript: [403]);
        const svc = PkPushService();
        await expectLater(
          svc.pushSwitchDeletion('sess-1', 'uuid-1', client),
          throwsA(
            isA<PkDeletionForbiddenException>()
                .having((e) => e.kind, 'kind', PkStaleLinkKind.switchRecord)
                .having((e) => e.localId, 'localId', 'sess-1')
                .having((e) => e.pkId, 'pkId', 'uuid-1'),
          ),
        );
      },
    );

    test('429 propagates — retry is handled inside PluralKitClient', () async {
      final client = _ScriptedDeletionClient(switchScript: [429]);
      const svc = PkPushService();
      await expectLater(
        svc.pushSwitchDeletion('sess-1', 'uuid-1', client),
        throwsA(isA<PluralKitRateLimitError>()),
      );
    });
  });
}
