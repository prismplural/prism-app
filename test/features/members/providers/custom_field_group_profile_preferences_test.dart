import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_entity_id.dart';
import 'package:prism_plurality/domain/repositories/member_profile_preference_repository.dart';
import 'package:prism_plurality/features/members/providers/custom_field_group_profile_preferences.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  test('dynamic group preference keys are valid for arbitrary ids', () {
    final display = customFieldGroupProfileDisplayModePreference(
      'Group:One/With Spaces',
    );
    final collapsed = customFieldGroupCollapsedPreference(
      'Group:One/With Spaces',
    );

    expect(isValidPreferenceKey(display.key), isTrue);
    expect(isValidPreferenceKey(collapsed.key), isTrue);
    expect(display.key, startsWith('custom_fields.group_profile_display.g'));
    expect(collapsed.key, startsWith('custom_fields.group_collapsed.g'));
  });

  test(
    'display mode provider defaults inline and persists page mode',
    () async {
      final prefs = FakeAppPreferenceRepository();
      addTearDown(prefs.close);
      final container = ProviderContainer(
        overrides: [appPreferenceRepositoryProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final provider = customFieldGroupProfileDisplayModeProvider('group-1');

      expect(
        await container.read(provider.future),
        CustomFieldGroupProfileDisplayMode.inline,
      );

      await container
          .read(provider.notifier)
          .set(CustomFieldGroupProfileDisplayMode.page);

      expect(
        await prefs.get(
          customFieldGroupProfileDisplayModePreference('group-1'),
        ),
        CustomFieldGroupProfileDisplayMode.page.storageValue,
      );
      expect(
        container.read(provider).value,
        CustomFieldGroupProfileDisplayMode.page,
      );
    },
  );

  test('collapsed state is member-profile scoped and defaults open', () async {
    final prefs = _FakeMemberProfilePreferenceRepository();
    addTearDown(prefs.close);
    final container = ProviderContainer(
      overrides: [
        memberProfilePreferenceRepositoryProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final aliceGroup = customFieldGroupCollapsedProvider((
      memberId: 'alice',
      groupId: 'group-1',
    ));
    final bobGroup = customFieldGroupCollapsedProvider((
      memberId: 'bob',
      groupId: 'group-1',
    ));

    expect(await container.read(aliceGroup.future), isFalse);
    expect(await container.read(bobGroup.future), isFalse);

    await container.read(aliceGroup.notifier).setCollapsed(true);

    expect(container.read(aliceGroup).value, isTrue);
    expect(await container.read(bobGroup.future), isFalse);
  });
}

class _FakeMemberProfilePreferenceRepository
    implements MemberProfilePreferenceRepository {
  final Map<String, Object?> _values = {};
  final Map<String, StreamController<Object?>> _controllers = {};

  @override
  Future<T> get<T>(String memberId, PreferenceDefinition<T> definition) async {
    final value = _values[_id(memberId, definition)];
    if (value is T) return value;
    return definition.defaultValue;
  }

  @override
  Stream<T> watch<T>(
    String memberId,
    PreferenceDefinition<T> definition,
  ) async* {
    yield await get(memberId, definition);
    yield* _controllerFor(_id(memberId, definition)).stream.map((value) {
      if (value is T) return value;
      return definition.defaultValue;
    });
  }

  @override
  Future<void> set<T>(
    String memberId,
    PreferenceDefinition<T> definition,
    T value,
  ) async {
    definition.validate(value);
    final id = _id(memberId, definition);
    _values[id] = value;
    _controllerFor(id).add(value);
  }

  @override
  Future<void> reset<T>(
    String memberId,
    PreferenceDefinition<T> definition,
  ) async {
    final id = _id(memberId, definition);
    _values.remove(id);
    _controllerFor(id).add(definition.defaultValue);
  }

  @override
  Future<void> resetAllForMember(String memberId) async {
    final prefix = '$memberId:';
    for (final key in _values.keys.where((key) => key.startsWith(prefix))) {
      _values.remove(key);
      _controllerFor(key).add(null);
    }
  }

  String _id(String memberId, PreferenceDefinition<dynamic> definition) =>
      '$memberId:${definition.key}';

  StreamController<Object?> _controllerFor(String key) {
    return _controllers.putIfAbsent(key, StreamController<Object?>.broadcast);
  }

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
