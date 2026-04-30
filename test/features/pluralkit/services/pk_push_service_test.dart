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
  final List<Call> calls = [];

  String nextMemberId = 'abcde';

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

    test('includes empty proxy tag list for explicit local clear', () async {
      final member = _member(proxyTagsJson: '[]');

      await pushService.pushMember(member, fakeClient);

      final data = fakeClient.calls.first.args.last as Map<String, dynamic>;
      expect(data['proxy_tags'], isEmpty);
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
  final List<int?> memberScript;
  final List<int?> switchScript;
  int memberCalls = 0;
  int switchCalls = 0;

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
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) =>
      throw UnimplementedError();
  @override
  Future<List<int>> downloadBytes(String url) => throw UnimplementedError();
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];
  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];
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
