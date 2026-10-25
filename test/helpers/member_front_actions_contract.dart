import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/member_front_actions_menu.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';

class _RecordingFrontingNotifier extends FrontingNotifier {
  final calls = <String>[];
  final release = Completer<void>();

  @override
  Future<void> build() async {}

  @override
  Future<void> startFronting(
    List<String> ids, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    calls.add('add:${ids.join(',')}');
    await release.future;
  }

  @override
  Future<void> replaceFronting(
    List<String> ids, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    calls.add('replace:${ids.join(',')}');
    await release.future;
  }

  @override
  Future<void> endFronting(List<String> ids) async {
    calls.add('end:${ids.join(',')}');
    await release.future;
  }
}

/// Runs against each real screen's existing provider fixture, not a new UI mock.
/// Windows-configured widget coverage is not an actual Windows device smoke.
void memberFrontActionsContract({
  required String surface,
  required Widget Function(
    Member member,
    List<FrontingSession> sessions,
    FrontingNotifier notifier,
  )
  build,
}) {
  for (final input in ['touch', 'mouse', 'keyboard']) {
    for (final state in ['inactive', 'active', 'protected']) {
      testWidgets('$surface $input $state individual front actions', (
        tester,
      ) async {
        final member = Member(
          id: 'contract-member',
          name: 'Synthetic member',
          createdAt: DateTime(2024),
          isAlwaysFronting: state == 'protected',
        );
        final sessions = <FrontingSession>[
          if (state != 'inactive')
            FrontingSession(
              id: 'contract-session',
              memberId: member.id,
              startTime: DateTime(2024),
            ),
        ];
        final notifier = _RecordingFrontingNotifier();
        final previousPlatform = debugDefaultTargetPlatformOverride;
        try {
          debugDefaultTargetPlatformOverride = input == 'touch'
              ? TargetPlatform.android
              : TargetPlatform.windows;
          await tester.pumpWidget(build(member, sessions, notifier));
          await tester.pumpAndSettle();
          final row = find.byWidgetPredicate(
            (widget) => widget is MemberCard && widget.member.id == member.id,
          );
          expect(row, findsOneWidget);
          // The production menu must have subscribed before any input. Reading
          // here is assertion-only: a lazy first subscription would be Loading.
          final container = ProviderScope.containerOf(tester.element(row));
          final roster = container.read(allMemberListProvider);
          expect(roster.isLoading, isFalse);
          expect(roster.hasError, isFalse);
          expect(roster.hasValue, isTrue);
          final l10n = AppLocalizations.of(tester.element(row));
          final terms = frontingTermBundleForPreset(
            l10n,
            FrontingTermPreset.fronting,
          );

          switch (input) {
            case 'touch':
              await tester.longPress(find.text(member.name));
            case 'mouse':
              await tester.tap(
                find.text(member.name),
                kind: PointerDeviceKind.mouse,
                buttons: kSecondaryMouseButton,
              );
            case 'keyboard':
              // Tab to the real card's focusable descendant, then invoke the
              // standard Windows context-menu shortcut without pointer input.
              var rowHasFocus = false;
              for (var i = 0; i < 30; i++) {
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pump();
                final focused = FocusManager.instance.primaryFocus?.context;
                rowHasFocus =
                    focused != null &&
                    find
                        .descendant(
                          of: row,
                          matching: find.byElementPredicate(
                            (element) => element == focused,
                          ),
                        )
                        .evaluate()
                        .isNotEmpty;
                if (rowHasFocus) break;
              }
              expect(
                rowHasFocus,
                isTrue,
                reason: 'member row must be keyboard reachable',
              );
              await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.f10);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.pumpAndSettle();

          if (state == 'inactive') {
            expect(find.text(terms.addAction), findsOneWidget);
            expect(find.text(terms.replaceCurrentAction), findsOneWidget);
            expect(find.text(terms.endCurrentAction), findsNothing);
          } else if (state == 'active') {
            expect(find.text(terms.endCurrentAction), findsOneWidget);
            expect(find.text(terms.addAction), findsNothing);
            expect(find.text(terms.replaceCurrentAction), findsNothing);
          } else {
            // Protected policy must be visible rather than offering an end that
            // the domain policy immediately reverses. No policy mutation here.
            expect(find.text(terms.alwaysActiveLabel), findsOneWidget);
            expect(find.text(terms.endCurrentAction), findsNothing);
            expect(find.text(terms.addAction), findsNothing);
            expect(find.text(terms.replaceCurrentAction), findsNothing);
          }
          expect(tester.takeException(), isNull);
          if (state != 'protected') {
            final verb = state == 'active'
                ? 'end'
                : input == 'touch'
                ? 'add'
                : 'replace';
            final label = state == 'active'
                ? terms.endCurrentAction
                : input == 'touch'
                ? terms.addAction
                : terms.replaceCurrentAction;
            final action = find.text(label);
            if (input == 'keyboard') {
              Focus.of(tester.element(action)).requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              await tester.tap(
                action,
                kind: input == 'mouse'
                    ? PointerDeviceKind.mouse
                    : PointerDeviceKind.touch,
              );
              await tester.tap(
                action,
                kind: input == 'mouse'
                    ? PointerDeviceKind.mouse
                    : PointerDeviceKind.touch,
                warnIfMissed: false,
              );
            }
            expect(
              container.read(memberFrontActionBusyProvider),
              isTrue,
              reason: 'same-frame double dispatch holds the shared latch',
            );
            await tester.pump();
            expect(
              notifier.calls,
              ['$verb:${member.id}'],
              reason: 'rapid repeat dispatches only one individual mutation',
            );
            notifier.release.complete();
            await tester.pumpAndSettle();
            expect(notifier.calls, ['$verb:${member.id}']);
          } else {
            expect(notifier.calls, isEmpty);
          }
        } finally {
          try {
            if (!notifier.release.isCompleted) notifier.release.complete();
            // Dispose screen/provider subscriptions before the harness closes
            // its owned preference streams in asynchronous addTearDown.
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          } finally {
            debugDefaultTargetPlatformOverride = previousPlatform;
          }
        }
      });
    }
  }
}
