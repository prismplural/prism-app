import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_codec.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';

enum CustomFieldGroupProfileDisplayMode {
  inline('inline'),
  collapsible('collapsible'),
  page('page');

  const CustomFieldGroupProfileDisplayMode(this.storageValue);

  final String storageValue;

  static CustomFieldGroupProfileDisplayMode fromStorage(String value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return inline;
  }
}

typedef CustomFieldGroupCollapsedKey = ({String memberId, String groupId});

const _groupDisplayModeValues = {'inline', 'collapsible', 'page'};

PreferenceDefinition<String> customFieldGroupProfileDisplayModePreference(
  String groupId,
) {
  return PreferenceDefinition<String>(
    key: 'custom_fields.group_profile_display.${_encodedGroupSegment(groupId)}',
    scope: PreferenceScope.appSynced,
    defaultValue: CustomFieldGroupProfileDisplayMode.inline.storageValue,
    codec: const StringPreferenceCodec(allowedValues: _groupDisplayModeValues),
    introducedInAppVersion: '0.13.1',
    introducedInSchemaVersion: 38,
  );
}

PreferenceDefinition<bool> customFieldGroupCollapsedPreference(String groupId) {
  return PreferenceDefinition<bool>(
    key: 'custom_fields.group_collapsed.${_encodedGroupSegment(groupId)}',
    scope: PreferenceScope.memberProfileSynced,
    defaultValue: false,
    codec: const BoolPreferenceCodec(),
    introducedInAppVersion: '0.13.1',
    introducedInSchemaVersion: 38,
  );
}

String _encodedGroupSegment(String groupId) {
  final bytes = utf8.encode(groupId);
  final buffer = StringBuffer('g');
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

class CustomFieldGroupProfileDisplayModeNotifier
    extends AsyncNotifier<CustomFieldGroupProfileDisplayMode> {
  CustomFieldGroupProfileDisplayModeNotifier(this.groupId);

  final String groupId;

  @override
  Future<CustomFieldGroupProfileDisplayMode> build() async {
    final repo = ref.watch(appPreferenceRepositoryProvider);
    final definition = customFieldGroupProfileDisplayModePreference(groupId);
    final initial = CustomFieldGroupProfileDisplayMode.fromStorage(
      await repo.get(definition),
    );
    final subscription = repo
        .watch(definition)
        .listen(
          (value) => state = AsyncValue.data(
            CustomFieldGroupProfileDisplayMode.fromStorage(value),
          ),
          onError: (Object error, StackTrace stackTrace) =>
              state = AsyncValue.error(error, stackTrace),
        );
    ref.onDispose(subscription.cancel);
    return initial;
  }

  Future<void> set(CustomFieldGroupProfileDisplayMode mode) async {
    await ref
        .read(appPreferenceRepositoryProvider)
        .set(
          customFieldGroupProfileDisplayModePreference(groupId),
          mode.storageValue,
        );
    state = AsyncValue.data(mode);
  }
}

final customFieldGroupProfileDisplayModeProvider =
    AsyncNotifierProvider.family<
      CustomFieldGroupProfileDisplayModeNotifier,
      CustomFieldGroupProfileDisplayMode,
      String
    >(CustomFieldGroupProfileDisplayModeNotifier.new);

class CustomFieldGroupCollapsedNotifier extends AsyncNotifier<bool> {
  CustomFieldGroupCollapsedNotifier(this.key);

  final CustomFieldGroupCollapsedKey key;

  @override
  Future<bool> build() async {
    final repo = ref.watch(memberProfilePreferenceRepositoryProvider);
    final definition = customFieldGroupCollapsedPreference(key.groupId);
    final initial = await repo.get(key.memberId, definition);
    final subscription = repo
        .watch(key.memberId, definition)
        .listen(
          (value) => state = AsyncValue.data(value),
          onError: (Object error, StackTrace stackTrace) =>
              state = AsyncValue.error(error, stackTrace),
        );
    ref.onDispose(subscription.cancel);
    return initial;
  }

  Future<void> setCollapsed(bool value) async {
    await ref
        .read(memberProfilePreferenceRepositoryProvider)
        .set(
          key.memberId,
          customFieldGroupCollapsedPreference(key.groupId),
          value,
        );
    state = AsyncValue.data(value);
  }
}

final customFieldGroupCollapsedProvider =
    AsyncNotifierProvider.family<
      CustomFieldGroupCollapsedNotifier,
      bool,
      CustomFieldGroupCollapsedKey
    >(CustomFieldGroupCollapsedNotifier.new);
