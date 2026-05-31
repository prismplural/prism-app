import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_mode_card.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FakeSleepNotifier extends SleepNotifier {
  final endedIds = <String>[];

  @override
  void build() {}

  @override
  Future<void> endSleep(String id) async => endedIds.add(id);
}

FrontingSession _activeSleep() => FrontingSession(
  id: 'sleep-active',
  startTime: DateTime.now().subtract(const Duration(hours: 8)),
  sessionType: SessionType.sleep,
);

Widget _buildSubject(_FakeSleepNotifier notifier) {
  return ProviderScope(
    overrides: [
      activeSleepSessionProvider.overrideWith(
        (ref) => Stream.value(_activeSleep()),
      ),
      sleepNotifierProvider.overrideWith(() => notifier),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: SleepModeCard()),
    ),
  );
}

void main() {
  testWidgets('active sleep card can end the open sleep session', (
    tester,
  ) async {
    final notifier = _FakeSleepNotifier();

    await tester.pumpWidget(_buildSubject(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();

    expect(notifier.endedIds, ['sleep-active']);
  });
}
