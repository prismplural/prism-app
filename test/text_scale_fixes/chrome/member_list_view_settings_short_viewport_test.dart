// The member list "View Settings" sheet on a viewport shorter than its own header.
//
// The sheet's body decides between a column (bar + expanded list) and a scroll
// fallback by comparing the available height against the height the bar needs, and
// the bar grows with the ambient text scale. On a 320x100 viewport at composed
// 3.375x the body is shorter than the bar alone, so the sheet must still present its
// title, its close action and its settings - with the rest reachable through the
// scroll controller the sheet hands it - instead of collapsing to an empty box.
//
// The case is deliberately not vacuous: it captures the constraints the sheet body
// really receives and the bar height the shared contract reports, and asserts
// `bodyHeight < barHeight` *before* anything else. It also does not prescribe the
// implementation's scroll widget: the sheet may host a ListView or a
// CustomScrollView, so the checks go through the scroll controller the sheet
// provides and the rendered settings content.
//
// Hermetic: the sheet is opened through its real entry point (`PrismSheet.
// showFullScreen`, as `members_screen` does) with the providers this screen reads
// overridden to values; no database, no device, no timers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/member_list_view_settings_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

import '../../helpers/fronting_term_fixtures.dart';
import 'chrome_text_scale_harness.dart';

const _openSheetKey = Key('openViewSettingsSheet');

/// Values observed from the opened sheet.
class _SheetProbe {
  ScrollController? controller;
  double? bodyHeight;
  double? barHeight;
}

class _RecordingSettings extends SettingsNotifier {
  final pronouns = <bool>[];
  final frontButtons = <bool>[];

  @override
  Future<void> updateMembersShowPronouns(bool value) async {
    pronouns.add(value);
  }

  @override
  Future<void> updateMembersShowFrontButtons(bool value) async {
    frontButtons.add(value);
  }
}

Widget _host(_SheetProbe probe) {
  return Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          key: _openSheetKey,
          onPressed: () {
            PrismSheet.showFullScreen(
              context: context,
              builder: (context, scrollController) {
                probe.controller = scrollController;
                // Transparent pass-through: the sheet body's real constraints, and
                // the height the shared contract says its bar needs.
                return LayoutBuilder(
                  builder: (context, constraints) {
                    probe.bodyHeight = constraints.maxHeight;
                    probe.barHeight = prismScaledHeightOf(
                      context,
                      PrismSheetTopBar(
                        title: AppLocalizations.of(
                          context,
                        )!.memberListViewSettingsTitle,
                      ),
                      availableWidth: constraints.maxWidth,
                    );
                    return MemberListViewSettingsSheet(
                      scrollController: scrollController,
                    );
                  },
                );
              },
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

Widget _subject({
  required _SheetProbe probe,
  required double system,
  required double app,
  required String family,
  _RecordingSettings? settings,
}) {
  return ProviderScope(
    overrides: [
      if (settings != null)
        settingsNotifierProvider.overrideWith(() => settings),
      allGroupsProvider.overrideWithValue(const AsyncValue.data([])),
      membersShowGroupsProvider.overrideWithValue(false),
      membersListViewModeProvider.overrideWithValue(
        MembersListViewMode.groupedSections,
      ),
      membersGroupedDefaultStateProvider.overrideWithValue(
        MembersGroupedDefaultState.open,
      ),
      membersFolderMemberVisibilityProvider.overrideWithValue(
        MembersFolderMemberVisibility.allMembers,
      ),
      membersShowPronounsProvider.overrideWithValue(true),
      membersShowFrontButtonsProvider.overrideWithValue(true),
      membersFrontButtonBehaviorProvider.overrideWithValue(
        FrontStartBehavior.additive,
      ),
      frontingTermsSettingProvider.overrideWithValue(
        FrontingTerms.custom(testFrontingTermBundle),
      ),
    ],
    child: chromeApp(
      _host(probe),
      system: system,
      app: app,
      fontFamily: family,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadChromeFonts();
  });

  for (final family in chromeFontFamilies) {
    testWidgets('view settings on a 320x100 viewport keeps its title, close action and '
        'settings reachable ($family)', (tester) async {
      useWindow(tester, const Size(320, 100));
      final probe = _SheetProbe();
      await tester.pumpWidget(
        _subject(probe: probe, system: 2.25, app: 1.5, family: family),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_openSheetKey));
      await tester.pumpAndSettle();
      expectNoLayoutException(tester, 'view settings 320x100 (open)');

      // Precondition, asserted first so the case cannot pass vacuously: the sheet
      // body really is shorter than the bar it has to hold.
      expect(
        probe.bodyHeight,
        isNotNull,
        reason: 'the sheet body must have been laid out',
      );
      expect(
        probe.barHeight,
        isNotNull,
        reason: 'the bar height must have been resolvable for the same context',
      );
      expect(
        probe.bodyHeight,
        lessThan(probe.barHeight!),
        reason:
            'precondition: body ${probe.bodyHeight} must be shorter than the bar '
            '${probe.barHeight} for this case to mean anything',
      );

      // Not blank: the sheet still presents its header and its close action.
      expect(
        find.text('View Settings'),
        findsOneWidget,
        reason:
            'the sheet must not collapse to an empty box on a short viewport',
      );
      expect(
        find.byTooltip('Close'),
        findsWidgets,
        reason: 'the close action must stay reachable',
      );

      // The controller the sheet provided must be the one carrying the settings,
      // whatever scroll widget the fallback uses.
      final controller = probe.controller;
      expect(controller, isNotNull, reason: 'the sheet provides a controller');
      expect(
        controller!.hasClients,
        isTrue,
        reason:
            'the provided controller must be attached to the scrollable that '
            'hosts the settings; otherwise nothing below the bar is reachable',
      );
      expect(
        controller.position.maxScrollExtent,
        greaterThan(0),
        reason:
            'on a viewport shorter than the content the settings must scroll, so '
            'everything stays reachable',
      );

      // Settings content exists and is reachable through that controller.
      expect(
        find.text('Groups'),
        findsWidgets,
        reason: 'the first settings group is present',
      );
      final pixelsBefore = controller.position.pixels;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        controller.position.pixels,
        greaterThan(pixelsBefore),
        reason: 'the provided controller really scrolls the settings',
      );

      // Close still works from the short viewport.
      await tester.ensureVisible(find.byTooltip('Close').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close').first.hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Close').first);
      await tester.pumpAndSettle();
      expect(
        find.text('View Settings'),
        findsNothing,
        reason: 'the close action dismisses the sheet',
      );
      expectNoLayoutException(tester, 'view settings 320x100 (close)');
    });
  }

  for (final family in chromeFontFamilies) {
    for (final keyboard in [false, true]) {
      testWidgets('short landscape settings controls remain hittable '
          'with safe area and keyboard=$keyboard ($family)', (tester) async {
        useWindow(
          tester,
          const Size(568, 240),
          keyboardInset: keyboard ? 108 : 0,
        );
        tester.view.viewPadding = const FakeViewPadding(top: 12, bottom: 16);
        tester.view.padding = FakeViewPadding(
          top: 12,
          bottom: keyboard ? 0 : 16,
        );
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        final probe = _SheetProbe();
        final settings = _RecordingSettings();
        await tester.pumpWidget(
          _subject(
            probe: probe,
            system: 2.25,
            app: 1.5,
            family: family,
            settings: settings,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_openSheetKey));
        await tester.pumpAndSettle();
        final body = tester.getRect(find.byType(MemberListViewSettingsSheet));
        // The route consumes the top safe area and max(keyboard, bottom safe
        // area) exactly once, before the body makes its layout decision.
        expect(body.top, greaterThanOrEqualTo(12));
        expect(body.bottom, keyboard ? 132 : 224);
        expect(body.height, probe.bodyHeight);
        final controller = probe.controller!;
        expect(controller.hasClients, isTrue);
        expect(controller.position.maxScrollExtent, greaterThan(0));

        final switches = find.byType(PrismSwitchRow);
        expect(switches, findsNWidgets(3));
        // All controls are present, including the disabled no-groups switch.
        expect(tester.widget<PrismSwitchRow>(switches.at(0)).enabled, isFalse);
        for (final index in [1, 2]) {
          final row = switches.at(index);
          final target = find.descendant(
            of: row,
            matching: find.byType(Switch),
          );
          expect(target, findsOneWidget);
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(44));
          expect(rect.height, greaterThanOrEqualTo(44));
          expect(rect.top, greaterThanOrEqualTo(body.top));
          expect(rect.bottom, lessThanOrEqualTo(body.bottom));
          expect(target.hitTestable(), findsOneWidget);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }
        expect(settings.frontButtons, [false]);
        expect(settings.pronouns, [false]);
        expectNoLayoutException(tester, 'landscape settings callbacks');

        final close = find.byTooltip('Close').first;
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        expect(close.hitTestable(), findsOneWidget);
        final closeRect = tester.getRect(close);
        expect(closeRect.width, greaterThanOrEqualTo(44));
        expect(closeRect.height, greaterThanOrEqualTo(44));
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(MemberListViewSettingsSheet), findsNothing);
        expectNoLayoutException(tester, 'landscape settings close');
      });
    }
  }
}
