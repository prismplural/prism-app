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
  // H1: per-field-gated PATCH payload (allowedFields)
  //
  // On the PATCH path the bidirectional service passes `allowedFields` — the
  // exact set of PK keys that may be written. Keys outside the set are omitted
  // (PK preserves), and gated fields never emit explicit `null`, so a single
  // triggering edit can never null-clear an unrelated PK-only field.
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
