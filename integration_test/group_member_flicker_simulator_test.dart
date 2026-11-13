// Synthetic, local-only iOS simulator check. Never imports user data or sync credentials.
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class _OfflineSync extends PrismSyncHandleNotifier {
  @override
  Future<ffi.PrismSyncHandle?> build() async => null;
}

const _groupId = 'qa-large-target';
String _memberId(int i) => 'qa-member-${i.toString().padLeft(4, '0')}';
String _memberName(int i) => i == 0
    ? 'Existing anchor'
    : i >= 20 && i < 104
    ? 'Bulk add ${i.toString().padLeft(4, '0')}'
    : 'Background member ${i.toString().padLeft(4, '0')}';

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.utc(2024);
  await db.batch((b) {
    b.insertAll(db.members, [
      for (var i = 0; i < 1000; i++)
        MembersCompanion.insert(
          id: _memberId(i),
          name: _memberName(i),
          createdAt: now,
        ),
    ]);
    b.insertAll(db.memberGroups, [
      for (var i = 0; i < 300; i++)
        MemberGroupsCompanion.insert(
          id: 'qa-group-$i',
          name: 'Background group $i',
          createdAt: now,
        ),
      MemberGroupsCompanion.insert(
        id: _groupId,
        name: 'Large-system flicker verification',
        createdAt: now,
        sortState: drift.Value(
          jsonEncode({
            'mode': 0,
            'order': [for (var i = 0; i < 20; i++) 'qa-initial-$i'],
          }),
        ),
      ),
    ]);
    b.insertAll(db.memberGroupEntries, [
      for (var i = 0; i < 1000; i++)
        for (var j = 0; j < 12; j++)
          MemberGroupEntriesCompanion.insert(
            id: 'qa-link-$i-$j',
            groupId: 'qa-group-${(i + j * 17) % 300}',
            memberId: _memberId(i),
          ),
      for (var i = 0; i < 20; i++)
        MemberGroupEntriesCompanion.insert(
          id: 'qa-initial-$i',
          groupId: _groupId,
          memberId: _memberId(i),
        ),
    ]);
  });
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'large system bulk-add preserves rendered group rows on iOS',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          prismSyncHandleProvider.overrideWith(_OfflineSync.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            builder: (context, child) =>
                PrismToastHost(child: child ?? const SizedBox.shrink()),
            home: const GroupDetailScreen(groupId: _groupId),
          ),
        ),
      );
      final anchor = find.byKey(
        const ValueKey('member_qa-initial-0'),
        skipOffstage: false,
      );
      for (var frame = 0; frame < 300 && anchor.evaluate().isEmpty; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(anchor, findsOneWidget);
      expect(
        container.read(groupEntriesProvider(_groupId)).requireValue.length,
        20,
      );
      // Host can begin a recording after this marker; no original flashing video is replayed.
      // ignore: avoid_print
      print(
        'QA_LARGE_READY members=1000 groups=301 background_links=12000 initial_group=20',
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      await tester.tap(
        find.widgetWithIcon(PrismInlineIconButton, AppIcons.personAddOutlined),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MemberSearchSheet), findsOneWidget);
      final field = find.descendant(
        of: find.byType(MemberSearchSheet),
        matching: find.byType(PrismTextField),
      );
      await tester.enterText(field, 'Bulk add');
      await tester.pumpAndSettle();
      final scroller = find
          .descendant(
            of: find.byType(MemberSearchSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 20; i < 104; i++) {
        final row = find.byKey(ValueKey(_memberId(i)));
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: scroller,
          maxScrolls: 100,
        );
        await tester.tap(row);
        await tester.pump();
      }
      final sheet = tester.widget<MemberSearchSheet>(
        find.byType(MemberSearchSheet),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MemberSearchSheet)),
      );
      final confirm = find.byTooltip(
        l10n.memberSearchConfirmSelectionTooltip(
          sheet.termPlural.toLowerCase(),
        ),
      );
      expect(confirm, findsOneWidget);
      var monitoring = true,
          renderedFrames = 0,
          missingFrames = 0,
          hydratingFrames = 0,
          positionChanges = 0;
      final originalPosition = tester.getTopLeft(anchor);
      addTearDown(() {
        monitoring = false;
      });
      final started = Stopwatch()..start();
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        if (!monitoring) return;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!monitoring) return;
          renderedFrames++;
          if (container
              .read(sortedGroupMembersAsyncProvider(_groupId))
              .isLoading) {
            hydratingFrames++;
          }
          if (anchor.evaluate().length != 1) {
            missingFrames++;
            return;
          }
          final renderBox =
              anchor.evaluate().single.findRenderObject()! as RenderBox;
          if ((renderBox.localToGlobal(Offset.zero) - originalPosition)
                  .distance >
              0.5) {
            positionChanges++;
          }
        });
      });
      // Actual picker confirmation -> production _addMember loop -> real Drift repos and query streams.
      await tester.tap(confirm);
      var complete = false;
      for (var frame = 0; frame < 6000; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final entries = container.read(groupEntriesProvider(_groupId)).value;
        final pairs = container.read(sortedGroupMembersAsyncProvider(_groupId));
        if (entries?.length == 104 &&
            pairs.hasValue &&
            pairs.requireValue.length == 104) {
          complete = true;
          break;
        }
      }
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      monitoring = false;
      started.stop();
      final report = {
        'members': 1000,
        'groups': 301,
        'background_links': 12000,
        'initial_group': 20,
        'selected_in_real_picker': 84,
        'final_group': container
            .read(groupEntriesProvider(_groupId))
            .value
            ?.length,
        'final_resolved_rows': container
            .read(sortedGroupMembersAsyncProvider(_groupId))
            .value
            ?.length,
        'rendered_frames_observed': renderedFrames,
        'hydrating_frames_observed': hydratingFrames,
        'missing_anchor_frames': missingFrames,
        'anchor_position_change_frames': positionChanges,
        'elapsed_ms': started.elapsedMilliseconds,
        'complete': complete,
        'simulator': true,
        'real_drift_repositories': true,
        'sync_disabled': true,
      };
      // ignore: avoid_print
      print('QA_LARGE_RESULT ${jsonEncode(report)}');
      binding.reportData = report;
      final output = File(
        '${Directory.systemTemp.path}/prism-group-flicker-large-result.json',
      );
      await output.writeAsString(jsonEncode(report));
      expect(complete, isTrue);
      expect(renderedFrames, greaterThan(0));
      expect(missingFrames, 0);
      expect(positionChanges, 0);
      expect(tester.takeException(), isNull);
      // Keep the final stable result visible briefly for a host screenshot.
      await Future<void>.delayed(const Duration(seconds: 5));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
