import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/views/start_sleep_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

class _FakeSleepNotifier extends SleepNotifier {
  int startSleepCalls = 0;
  Completer<void>? startSleepCompleter;

  @override
  void build() {}

  @override
  Future<void> startSleep({
    String? notes,
    DateTime? startTime,
    SleepQuality? quality,
  }) async {
    startSleepCalls += 1;
    final completer = startSleepCompleter;
    if (completer != null) {
      await completer.future;
    }
  }
}

Widget _buildSubject(_FakeSleepNotifier notifier) {
  return ProviderScope(
    overrides: [
      sleepNotifierProvider.overrideWith(() => notifier),
      recentSleepSessionsPaginatedProvider.overrideWith(
        (ref, limit) => Stream.value(const <FrontingSession>[]),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: StartSleepSheet()),
    ),
  );
}

Finder _startButton() => find.byWidgetPredicate(
  (widget) => widget is PrismButton && widget.label == 'Start',
);

void main() {
  testWidgets('start ignores repeated taps while start is pending', (
    tester,
  ) async {
    final notifier = _FakeSleepNotifier()
      ..startSleepCompleter = Completer<void>();

    await tester.pumpWidget(_buildSubject(notifier));
    await tester.pumpAndSettle();

    await tester.tap(_startButton());
    await tester.tap(_startButton());

    expect(notifier.startSleepCalls, 1);

    notifier.startSleepCompleter!.complete();
    await tester.pumpAndSettle();
  });
}
