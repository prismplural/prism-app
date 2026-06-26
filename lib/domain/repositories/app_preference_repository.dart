import 'package:prism_plurality/domain/preferences/preference_definition.dart';

abstract interface class AppPreferenceRepository {
  Stream<T> watch<T>(PreferenceDefinition<T> definition);

  Stream<T?> watchStored<T>(PreferenceDefinition<T> definition);

  Future<T> get<T>(PreferenceDefinition<T> definition);

  Future<T?> getStored<T>(PreferenceDefinition<T> definition);

  Future<void> set<T>(PreferenceDefinition<T> definition, T value);

  Future<void> reset<T>(PreferenceDefinition<T> definition);
}
