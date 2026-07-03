import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/reminders/providers/reminders_providers.dart';
import 'package:prism_plurality/features/reminders/views/reminders_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

import '../../../helpers/fake_repositories.dart';

class _FakeRemindersNotifier extends RemindersNotifier {
  final toggled = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> toggleActive(Reminder reminder) async {
    toggled.add(reminder.id);
  }
}

Reminder _reminder({
  String id = 'reminder-1',
  String name = 'Feed Panda',
  String message = 'Give Panda breakfast before the morning standup.',
  bool isActive = true,
}) {
  final timestamp = DateTime(2026, 6, 2, 9, 30);
  return Reminder(
    id: id,
    name: name,
    message: message,
    isActive: isActive,
    timeOfDay: '09:30',
    createdAt: timestamp,
    modifiedAt: timestamp,
  );
}

Widget _buildSubject(
  List<Reminder> reminders, {
  _FakeRemindersNotifier? notifier,
  bool alwaysUse24HourFormat = false,
}) {
  final appPrefs = FakeAppPreferenceRepository();
  addTearDown(appPrefs.close);
  return ProviderScope(
    overrides: [
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      remindersProvider.overrideWith((ref) => Stream.value(reminders)),
      if (notifier != null)
        remindersNotifierProvider.overrideWith(() => notifier),
      allMembersProvider.overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            alwaysUse24HourFormat: alwaysUse24HourFormat,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const RemindersScreen(showBackButton: false),
    ),
  );
}

void main() {
  testWidgets('reminder cards stay clamped on wide desktop layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_buildSubject([_reminder()]));
    await tester.pumpAndSettle();

    final cardRect = tester.getRect(
      find.byKey(const Key('reminderCard-reminder-1')),
    );

    expect(cardRect.width, lessThanOrEqualTo(PrismTokens.contentMaxWidth));
    expect(cardRect.left, greaterThan(0));
  });

  testWidgets('reminder cards show the reminder message', (tester) async {
    await tester.pumpWidget(_buildSubject([_reminder()]));
    await tester.pumpAndSettle();

    expect(find.text('Feed Panda'), findsOneWidget);
    expect(
      find.text('Give Panda breakfast before the morning standup.'),
      findsOneWidget,
    );
  });

  testWidgets('reminder cards honor 12-hour time preference', (tester) async {
    await tester.pumpWidget(
      _buildSubject([_reminder()], alwaysUse24HourFormat: false),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('9:30 AM'), findsOneWidget);
    expect(find.textContaining('09:30 · Daily'), findsNothing);
  });

  testWidgets('reminder cards honor 24-hour time preference', (tester) async {
    await tester.pumpWidget(
      _buildSubject([_reminder()], alwaysUse24HourFormat: true),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('09:30 · Daily'), findsOneWidget);
    expect(find.textContaining('AM'), findsNothing);
  });

  testWidgets('disabling a reminder asks for confirmation', (tester) async {
    final notifier = _FakeRemindersNotifier();

    await tester.pumpWidget(_buildSubject([_reminder()], notifier: notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Disable reminder?'), findsOneWidget);
    expect(notifier.toggled, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(notifier.toggled, isEmpty);
  });

  testWidgets('confirming disable toggles the reminder off', (tester) async {
    final notifier = _FakeRemindersNotifier();

    await tester.pumpWidget(_buildSubject([_reminder()], notifier: notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disable'));
    await tester.pumpAndSettle();

    expect(notifier.toggled, ['reminder-1']);
  });

  testWidgets('enabling a disabled reminder does not ask for confirmation', (
    tester,
  ) async {
    final notifier = _FakeRemindersNotifier();

    await tester.pumpWidget(
      _buildSubject([_reminder(isActive: false)], notifier: notifier),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Disable reminder?'), findsNothing);
    expect(notifier.toggled, ['reminder-1']);
  });
}
