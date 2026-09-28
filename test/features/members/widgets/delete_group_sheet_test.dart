import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/delete_group_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class _GatedGroupNotifier extends GroupNotifier {
  final gate = Completer<void>();
  int promoteCalls = 0;
  int deleteAllCalls = 0;

  @override
  Future<void> build() async {}

  @override
  Future<void> promoteChildrenToRoot(String groupId) async {
    promoteCalls++;
    await gate.future;
  }

  @override
  Future<void> deleteGroupWithDescendants(String groupId) async {
    deleteAllCalls++;
    await gate.future;
  }
}

class _PopCounter extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

final _l10n = lookupAppLocalizations(const Locale('en'));

SemanticsFinder _tapTarget(String label) => find.semantics.byPredicate(
  (node) =>
      node.getSemanticsData().hasAction(SemanticsAction.tap) &&
      node.label.contains(label),
);

final _group = MemberGroup(id: 'crew', name: 'Crew', createdAt: DateTime(2024));

/// Opens the sheet over a pushed "Group detail" route so a stray second pop
/// is observable as that route disappearing.
Future<void> _openSheet(
  WidgetTester tester, {
  required _GatedGroupNotifier notifier,
  required _PopCounter popCounter,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupNotifierProvider.overrideWith(() => notifier),
        terminologySettingProvider.overrideWithValue((
          term: SystemTerminology.members,
          customSingular: null,
          customPlural: null,
          useEnglish: false,
        )),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [popCounter],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: const Scaffold(body: Text('Groups')),
      ),
    ),
  );
  unawaited(
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Group detail')),
      ),
    ),
  );
  await tester.pumpAndSettle();

  unawaited(
    PrismSheet.show<void>(
      context: tester.element(find.text('Group detail')),
      builder: (_) => DeleteGroupSheet(group: _group),
    ),
  );
  await tester.pumpAndSettle();
  popCounter.pops = 0;
}

void main() {
  setUp(PrismToast.resetForTest);

  testWidgets('a same-frame double tap on promote runs once and pops once', (
    tester,
  ) async {
    final notifier = _GatedGroupNotifier();
    final popCounter = _PopCounter();
    await _openSheet(tester, notifier: notifier, popCounter: popCounter);

    // No pump between taps: both land before the disabling rebuild.
    final promote = find.text(_l10n.memberGroupDeletePromote);
    await tester.tap(promote);
    await tester.tap(promote);

    expect(notifier.promoteCalls, 1);

    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(popCounter.pops, 1);
    expect(find.byType(DeleteGroupSheet), findsNothing);
    expect(find.text('Group detail'), findsOneWidget);

    PrismToast.resetForTest();
    await tester.pump();
  });

  testWidgets('a same-frame double activation of delete all opens one dialog', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final notifier = _GatedGroupNotifier();
    final popCounter = _PopCounter();
    await _openSheet(tester, notifier: notifier, popCounter: popCounter);

    // The dialog push makes the navigator absorb further pointers until the
    // next frame, but not semantics actions, so repeat through those.
    final deleteAll = _tapTarget(_l10n.memberGroupDeleteAll);
    tester.semantics.tap(deleteAll);
    tester.semantics.tap(deleteAll);
    await tester.pumpAndSettle();

    expect(find.text(_l10n.memberGroupDeleteAllConfirmTitle), findsOneWidget);

    await tester.tap(find.text(_l10n.memberGroupDeleteAll).last);
    await tester.pump();

    expect(notifier.deleteAllCalls, 1);

    notifier.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(DeleteGroupSheet), findsNothing);
    expect(find.text('Group detail'), findsOneWidget);

    PrismToast.resetForTest();
    await tester.pump();
    semantics.dispose();
  });

  testWidgets('cancelling delete all leaves the options usable', (
    tester,
  ) async {
    final notifier = _GatedGroupNotifier();
    final popCounter = _PopCounter();
    await _openSheet(tester, notifier: notifier, popCounter: popCounter);

    await tester.tap(find.text(_l10n.memberGroupDeleteAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(find.text(_l10n.memberGroupDeleteAllConfirmTitle), findsNothing);
    expect(notifier.deleteAllCalls, 0);

    await tester.tap(find.text(_l10n.memberGroupDeletePromote));
    await tester.pump();

    expect(notifier.promoteCalls, 1);

    notifier.gate.complete();
    await tester.pumpAndSettle();
    PrismToast.resetForTest();
    await tester.pump();
  });
}
