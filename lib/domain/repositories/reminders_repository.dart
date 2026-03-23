import 'package:prism_plurality/domain/models/reminder.dart';

abstract class RemindersRepository {
  Stream<List<Reminder>> watchAll();
  Stream<List<Reminder>> watchActive();
  Future<Reminder?> getById(String id);
  Future<void> create(Reminder reminder);
  Future<void> update(Reminder reminder);
  Future<void> delete(String id);
}
