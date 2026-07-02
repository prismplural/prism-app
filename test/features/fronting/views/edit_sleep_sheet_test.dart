import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_plurality/features/fronting/views/edit_sleep_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';

import '../../../helpers/fake_repositories.dart';

FrontingSession _sleepSession() => FrontingSession(
  id: 'sleep-1',
  startTime: DateTime(2026, 7, 1, 22),
  endTime: DateTime(2026, 7, 2, 7),
  notes: 'old notes',
  sessionType: SessionType.sleep,
);

class _FakeFrontingMutationService extends FrontingMutationService {
  _FakeFrontingMutationService()
    : super(
        repository: FakeFrontingSessionRepository(),
        mutationRunner: MutationRunner(
          transactionRunner: <T>(action) => action(),
        ),
      );

  int updateSessionCalls = 0;
  Completer<void>? updateSessionCompleter;

  @override
  Future<MutationResult<FrontingSession>> updateSession(
    String sessionId,
    UpdateFrontingSessionPatch patch,
  ) async {
    updateSessionCalls += 1;
    final completer = updateSessionCompleter;
    if (completer != null) {
      await completer.future;
    }
    return MutationResult.success(_sleepSession());
  }
}

Widget _buildSubject(_FakeFrontingMutationService service) {
  return ProviderScope(
    overrides: [frontingMutationServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: EditSleepSheet(
          session: _sleepSession(),
          scrollController: ScrollController(),
        ),
      ),
    ),
  );
}

Finder _saveButton() => find.byWidgetPredicate(
  (widget) => widget is PrismGlassIconButton && widget.icon == AppIcons.check,
);

void main() {
  testWidgets('save ignores repeated taps while update is pending', (
    tester,
  ) async {
    final service = _FakeFrontingMutationService()
      ..updateSessionCompleter = Completer<void>();

    await tester.pumpWidget(_buildSubject(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'new notes');
    await tester.pump();

    await tester.tap(_saveButton());
    await tester.tap(_saveButton());

    expect(service.updateSessionCalls, 1);

    service.updateSessionCompleter!.complete();
    await tester.pumpAndSettle();
  });
}
