import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prism_plurality/core/services/auth_policy_service.dart';

void main() {
  late AuthPolicyService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = AuthPolicyService();
  });

  // ── isPinVerificationDue ──────────────────────────────────────────────────

  group('isPinVerificationDue', () {
    test('returns true when no record exists', () async {
      expect(await service.isPinVerificationDue(), isTrue);
    });

    test('returns false when verified less than 30 days ago', () async {
      final prefs = await SharedPreferences.getInstance();
      final recent = DateTime.now().subtract(const Duration(days: 15));
      await prefs.setInt(
        'prism.last_pin_verified',
        recent.millisecondsSinceEpoch,
      );

      expect(await service.isPinVerificationDue(), isFalse);
    });

    test('returns true when verified exactly 30 days ago', () async {
      final prefs = await SharedPreferences.getInstance();
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      await prefs.setInt(
        'prism.last_pin_verified',
        thirtyDaysAgo.millisecondsSinceEpoch,
      );

      expect(await service.isPinVerificationDue(), isTrue);
    });

    test('returns true when verified more than 30 days ago', () async {
      final prefs = await SharedPreferences.getInstance();
      final old = DateTime.now().subtract(const Duration(days: 45));
      await prefs.setInt(
        'prism.last_pin_verified',
        old.millisecondsSinceEpoch,
      );

      expect(await service.isPinVerificationDue(), isTrue);
    });

    test('returns true when stored timestamp is in the future (clock rollback)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final future = DateTime.now().add(const Duration(days: 1));
      await prefs.setInt(
        'prism.last_pin_verified',
        future.millisecondsSinceEpoch,
      );

      // Future timestamps are treated as missing — require re-verification.
      expect(await service.isPinVerificationDue(), isTrue);
    });
  });

  // ── recordPinVerified ─────────────────────────────────────────────────────

  group('recordPinVerified', () {
    test('sets a timestamp so isPinVerificationDue returns false', () async {
      await service.recordPinVerified();

      expect(await service.isPinVerificationDue(), isFalse);
    });

    test('persists a non-null timestamp in SharedPreferences', () async {
      await service.recordPinVerified();

      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('prism.last_pin_verified');
      expect(ts, isNotNull);
      expect(ts!, greaterThan(0));
    });
  });

  // ── isBackupReminderDue ───────────────────────────────────────────────────

  group('isBackupReminderDue', () {
    test('returns true when no record exists', () async {
      expect(await service.isBackupReminderDue(), isTrue);
    });

    test('returns false when dismissed less than 30 days ago', () async {
      final prefs = await SharedPreferences.getInstance();
      final recent = DateTime.now().subtract(const Duration(days: 10));
      await prefs.setInt(
        'prism.last_recovery_reminder',
        recent.millisecondsSinceEpoch,
      );

      expect(await service.isBackupReminderDue(), isFalse);
    });

    test('returns true when dismissed exactly 30 days ago', () async {
      final prefs = await SharedPreferences.getInstance();
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      await prefs.setInt(
        'prism.last_recovery_reminder',
        thirtyDaysAgo.millisecondsSinceEpoch,
      );

      expect(await service.isBackupReminderDue(), isTrue);
    });

    test('returns true when dismissed more than 30 days ago', () async {
      final prefs = await SharedPreferences.getInstance();
      final old = DateTime.now().subtract(const Duration(days: 60));
      await prefs.setInt(
        'prism.last_recovery_reminder',
        old.millisecondsSinceEpoch,
      );

      expect(await service.isBackupReminderDue(), isTrue);
    });

    test('returns true when stored timestamp is in the future (clock rollback)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final future = DateTime.now().add(const Duration(days: 1));
      await prefs.setInt(
        'prism.last_recovery_reminder',
        future.millisecondsSinceEpoch,
      );

      // Future timestamps are treated as missing — require re-verification.
      expect(await service.isBackupReminderDue(), isTrue);
    });
  });

  // ── recordReminderDismissed ───────────────────────────────────────────────

  group('recordReminderDismissed', () {
    test('sets a timestamp so isBackupReminderDue returns false', () async {
      await service.recordReminderDismissed();

      expect(await service.isBackupReminderDue(), isFalse);
    });

    test('persists a non-null timestamp in SharedPreferences', () async {
      await service.recordReminderDismissed();

      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('prism.last_recovery_reminder');
      expect(ts, isNotNull);
      expect(ts!, greaterThan(0));
    });
  });
}
