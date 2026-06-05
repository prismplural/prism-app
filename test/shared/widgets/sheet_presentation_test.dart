import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/shared/providers/accessibility_preferences_provider.dart';
import 'package:prism_plurality/shared/widgets/sheet_presentation.dart';

import '../../helpers/fake_repositories.dart';

void main() {
  testWidgets('wide layouts use side sheets by default', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = FakeAppPreferenceRepository();
    addTearDown(prefs.close);

    final context = await _pumpResolverHost(tester, prefs);

    expect(
      resolveAdaptiveSheetLayout(
        context,
        role: AdaptiveSheetRole.transientSheet,
      ),
      AdaptiveSheetLayout.sideSheet,
    );
    expect(
      resolveAdaptiveSheetLayout(context, role: AdaptiveSheetRole.modalDetail),
      AdaptiveSheetLayout.sideSheet,
    );
    expect(
      resolveAdaptiveSheetLayout(
        context,
        role: AdaptiveSheetRole.embeddedDetail,
      ),
      AdaptiveSheetLayout.embeddedPane,
    );
  });

  testWidgets(
    'force centered sheets affects modal surfaces but not embedded panes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 700);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final prefs = FakeAppPreferenceRepository()
        ..seed(forceCenteredSheetsPreference, true);
      addTearDown(prefs.close);

      final context = await _pumpResolverHost(tester, prefs);

      expect(
        resolveAdaptiveSheetLayout(
          context,
          role: AdaptiveSheetRole.transientSheet,
        ),
        AdaptiveSheetLayout.centeredSheet,
      );
      expect(
        resolveAdaptiveSheetLayout(
          context,
          role: AdaptiveSheetRole.modalDetail,
        ),
        AdaptiveSheetLayout.centeredSheet,
      );
      expect(
        resolveAdaptiveSheetLayout(
          context,
          role: AdaptiveSheetRole.embeddedDetail,
        ),
        AdaptiveSheetLayout.embeddedPane,
      );
    },
  );

  testWidgets('narrow layouts keep mobile behavior', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = FakeAppPreferenceRepository()
      ..seed(forceCenteredSheetsPreference, true);
    addTearDown(prefs.close);

    final context = await _pumpResolverHost(tester, prefs);

    expect(
      resolveAdaptiveSheetLayout(
        context,
        role: AdaptiveSheetRole.transientSheet,
      ),
      AdaptiveSheetLayout.centeredSheet,
    );
    expect(
      resolveAdaptiveSheetLayout(context, role: AdaptiveSheetRole.modalDetail),
      AdaptiveSheetLayout.route,
    );
    expect(
      resolveAdaptiveSheetLayout(
        context,
        role: AdaptiveSheetRole.embeddedDetail,
      ),
      AdaptiveSheetLayout.route,
    );
  });
}

Future<BuildContext> _pumpResolverHost(
  WidgetTester tester,
  FakeAppPreferenceRepository prefs,
) async {
  late BuildContext capturedContext;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appPreferenceRepositoryProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(dimBackgroundBehindSheetsProvider);
            ref.watch(forceCenteredSheetsProvider);
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();

  return capturedContext;
}
