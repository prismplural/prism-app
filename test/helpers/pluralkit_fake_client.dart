import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

class FakePluralKitClient implements PluralKitClient {
  FakePluralKitClient({
    this.system = const PKSystem(id: 'pk-system', name: 'Test PK System'),
    this.members = const <PKMember>[],
    this.groups = const <PKGroup>[],
    List<PKSwitch> switchesNewestFirst = const <PKSwitch>[],
    List<List<PKSwitch>>? switchPages,
  }) : _switchesNewestFirst = List<PKSwitch>.of(switchesNewestFirst),
       _switchPages = switchPages?.map(List<PKSwitch>.of).toList();

  PKSystem system;
  List<PKMember> members;
  List<PKGroup> groups;

  final List<PKSwitch> _switchesNewestFirst;
  final List<List<PKSwitch>>? _switchPages;

  int getSystemCallCount = 0;
  int getMembersCallCount = 0;
  int getGroupsCallCount = 0;
  int getSwitchesCallCount = 0;
  int disposeCallCount = 0;

  @override
  Future<PKSystem> getSystem() async {
    getSystemCallCount++;
    return system;
  }

  @override
  Future<List<PKMember>> getMembers() async {
    getMembersCallCount++;
    return members;
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async {
    getGroupsCallCount++;
    return groups;
  }

  @override
  Future<List<PKSwitch>> getSwitches({
    DateTime? before,
    int limit = 100,
  }) async {
    getSwitchesCallCount++;
    final pages = _switchPages;
    if (pages != null) {
      if (pages.isEmpty) return const <PKSwitch>[];
      return pages.removeAt(0);
    }
    if (before == null) return List<PKSwitch>.of(_switchesNewestFirst);
    return const <PKSwitch>[];
  }

  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];

  @override
  Future<List<int>> downloadBytes(String url) async => const [];

  @override
  Future<PKSwitch?> getCurrentFronters() async => null;

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();

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
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();

  @override
  void dispose() {
    disposeCallCount++;
  }
}
