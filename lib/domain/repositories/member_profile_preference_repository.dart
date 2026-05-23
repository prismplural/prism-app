import 'package:prism_plurality/domain/preferences/preference_definition.dart';

abstract interface class MemberProfilePreferenceRepository {
  Stream<T> watch<T>(String memberId, PreferenceDefinition<T> definition);

  Future<T> get<T>(String memberId, PreferenceDefinition<T> definition);

  Future<void> set<T>(
    String memberId,
    PreferenceDefinition<T> definition,
    T value,
  );

  Future<void> reset<T>(String memberId, PreferenceDefinition<T> definition);

  Future<void> resetAllForMember(String memberId);
}
