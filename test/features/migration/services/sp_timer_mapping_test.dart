import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/reminder.dart' as domain;
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/services/sp_mapper.dart';

/// Helper to create minimal SpExportData with sensible defaults.
SpExportData _makeExportData({
  List<SpMember> members = const [],
  List<SpCustomFront> customFronts = const [],
  List<SpFrontHistory> frontHistory = const [],
  List<SpGroup> groups = const [],
  List<SpChannel> channels = const [],
  List<SpMessage> messages = const [],
  List<SpPoll> polls = const [],
  List<SpNote> notes = const [],
  List<SpComment> comments = const [],
  List<SpCustomFieldDef> customFields = const [],
  List<SpBoardMessage> boardMessages = const [],
  List<SpAutomatedTimer> automatedTimers = const [],
  List<SpRepeatedTimer> repeatedTimers = const [],
}) {
  return SpExportData(
    members: members,
    customFronts: customFronts,
    frontHistory: frontHistory,
    groups: groups,
    channels: channels,
    messages: messages,
    polls: polls,
    notes: notes,
    comments: comments,
    customFields: customFields,
    boardMessages: boardMessages,
    automatedTimers: automatedTimers,
    repeatedTimers: repeatedTimers,
  );
}

void main() {
  // ── SpAutomatedTimer.fromJson ─────────────────────────────────

  group('SpAutomatedTimer.fromJson', () {
    test('parses int delayInHours', () {
      final timer = SpAutomatedTimer.fromJson({
        '_id': 'at1',
        'name': 'Check In',
        'message': 'Time to check in',
        'delayInHours': 4,
        'enabled': true,
      });

      expect(timer.id, 'at1');
      expect(timer.name, 'Check In');
      expect(timer.message, 'Time to check in');
      expect(timer.delayHours, 4);
      expect(timer.enabled, isTrue);
    });

    test('parses string delayInHours', () {
      final timer = SpAutomatedTimer.fromJson({
        '_id': 'at2',
        'name': 'Reminder',
        'delayInHours': '6',
      });

      expect(timer.delayHours, 6);
    });

    test('unparseable string delayInHours becomes null', () {
      final timer = SpAutomatedTimer.fromJson({
        '_id': 'at3',
        'name': 'Bad',
        'delayInHours': 'not-a-number',
      });

      expect(timer.delayHours, isNull);
    });

    test('missing fields use defaults', () {
      final timer = SpAutomatedTimer.fromJson({});

      expect(timer.id, '');
      expect(timer.name, 'Timer');
      expect(timer.message, isNull);
      expect(timer.delayHours, isNull);
      expect(timer.enabled, isTrue);
    });

    test('enabled: false is respected', () {
      final timer = SpAutomatedTimer.fromJson({
        '_id': 'at4',
        'name': 'Disabled',
        'enabled': false,
      });

      expect(timer.enabled, isFalse);
    });

    test('falls back to id key when _id is missing', () {
      final timer = SpAutomatedTimer.fromJson({
        'id': 'fallback-id',
        'name': 'Test',
      });

      expect(timer.id, 'fallback-id');
    });
  });

  // ── SpRepeatedTimer.fromJson ──────────────────────────────────

  group('SpRepeatedTimer.fromJson', () {
    test('parses intervalInDays as int', () {
      final timer = SpRepeatedTimer.fromJson({
        '_id': 'rt1',
        'name': 'Daily Check',
        'intervalInDays': 7,
      });

      expect(timer.intervalDays, 7);
    });

    test('parses intervalInDays as string', () {
      final timer = SpRepeatedTimer.fromJson({
        '_id': 'rt2',
        'name': 'Test',
        'intervalInDays': '3',
      });

      expect(timer.intervalDays, 3);
    });

    test('falls back to interval key when intervalInDays is missing', () {
      final timer = SpRepeatedTimer.fromJson({
        '_id': 'rt3',
        'name': 'Fallback',
        'interval': 14,
      });

      expect(timer.intervalDays, 14);
    });

    test('prefers intervalInDays over interval', () {
      final timer = SpRepeatedTimer.fromJson({
        '_id': 'rt4',
        'name': 'Priority',
        'intervalInDays': 2,
        'interval': 30,
      });

      expect(timer.intervalDays, 2);
    });

    test('parses time key for timeOfDay', () {
      final timer = SpRepeatedTimer.fromJson({
        '_id': 'rt5',
        'name': 'Morning',
        'time': '08:00',
      });

      expect(timer.timeOfDay, '08:00');
    });

    test('falls back to timeOfDay key when time is missing', () {
      final timer = SpRepeatedTimer.fromJson({
        '_id': 'rt6',
        'name': 'Evening',
        'timeOfDay': '20:00',
      });

      expect(timer.timeOfDay, '20:00');
    });

    test('prefers time over timeOfDay', () {
      final timer = SpRepeatedTimer.fromJson({
        '_id': 'rt7',
        'name': 'Priority',
        'time': '09:00',
        'timeOfDay': '21:00',
      });

      expect(timer.timeOfDay, '09:00');
    });

    test('missing fields use defaults', () {
      final timer = SpRepeatedTimer.fromJson({});

      expect(timer.id, '');
      expect(timer.name, 'Timer');
      expect(timer.message, isNull);
      expect(timer.intervalDays, isNull);
      expect(timer.timeOfDay, isNull);
      expect(timer.enabled, isTrue);
    });

    test('enabled: false is respected', () {
      final timer = SpRepeatedTimer.fromJson({
        '_id': 'rt8',
        'name': 'Disabled',
        'enabled': false,
      });

      expect(timer.enabled, isFalse);
    });
  });

  // ── _mapTimers via SpMapper.mapAll ────────────────────────────

  group('Timer mapping to Reminder domain models', () {
    test('automated timer maps to onFrontChange trigger', () {
      final data = _makeExportData(
        automatedTimers: [
          const SpAutomatedTimer(
            id: 'at1',
            name: 'Front Alert',
            message: 'You switched!',
            delayHours: 2,
            enabled: true,
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.reminders, hasLength(1));
      final reminder = result.reminders.first;
      expect(reminder.trigger, domain.ReminderTrigger.onFrontChange);
      expect(reminder.name, 'Front Alert');
      expect(reminder.message, 'You switched!');
      expect(reminder.delayHours, 2);
      expect(reminder.isActive, isTrue);
    });

    test('repeated timer maps to scheduled trigger with intervalDays and timeOfDay', () {
      final data = _makeExportData(
        repeatedTimers: [
          const SpRepeatedTimer(
            id: 'rt1',
            name: 'Daily Log',
            message: 'Write your log',
            intervalDays: 1,
            timeOfDay: '09:00',
            enabled: true,
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.reminders, hasLength(1));
      final reminder = result.reminders.first;
      expect(reminder.trigger, domain.ReminderTrigger.scheduled);
      expect(reminder.name, 'Daily Log');
      expect(reminder.message, 'Write your log');
      expect(reminder.intervalDays, 1);
      expect(reminder.timeOfDay, '09:00');
      expect(reminder.isActive, isTrue);
    });

    test('empty name defaults to Imported Timer', () {
      final data = _makeExportData(
        automatedTimers: [
          const SpAutomatedTimer(id: 'at1', name: ''),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.reminders, hasLength(1));
      expect(result.reminders.first.name, 'Imported Timer');
    });

    test('null message falls back to name', () {
      final data = _makeExportData(
        automatedTimers: [
          const SpAutomatedTimer(
            id: 'at1',
            name: 'My Timer',
            message: null,
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.reminders.first.message, 'My Timer');
    });

    test('disabled automated timer maps to inactive reminder', () {
      final data = _makeExportData(
        automatedTimers: [
          const SpAutomatedTimer(
            id: 'at1',
            name: 'Off',
            enabled: false,
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.reminders.first.isActive, isFalse);
    });

    test('disabled repeated timer maps to inactive reminder', () {
      final data = _makeExportData(
        repeatedTimers: [
          const SpRepeatedTimer(
            id: 'rt1',
            name: 'Off',
            enabled: false,
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.reminders.first.isActive, isFalse);
    });

    test('mixed automated and repeated timers all mapped', () {
      final data = _makeExportData(
        automatedTimers: [
          const SpAutomatedTimer(id: 'at1', name: 'Auto 1'),
          const SpAutomatedTimer(id: 'at2', name: 'Auto 2'),
        ],
        repeatedTimers: [
          const SpRepeatedTimer(id: 'rt1', name: 'Rep 1'),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.reminders, hasLength(3));
      final triggers = result.reminders.map((r) => r.trigger).toList();
      expect(
        triggers.where((t) => t == domain.ReminderTrigger.onFrontChange).length,
        2,
      );
      expect(
        triggers.where((t) => t == domain.ReminderTrigger.scheduled).length,
        1,
      );
    });

    test('each mapped reminder gets a unique ID', () {
      final data = _makeExportData(
        automatedTimers: [
          const SpAutomatedTimer(id: 'at1', name: 'A'),
          const SpAutomatedTimer(id: 'at2', name: 'B'),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      final ids = result.reminders.map((r) => r.id).toSet();
      expect(ids.length, result.reminders.length);
    });
  });
}
