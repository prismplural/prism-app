import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/klipy_providers.dart';
import 'package:prism_plurality/features/chat/services/klipy_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/chat_feature_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class _NullSpeakingAsNotifier extends SpeakingAsNotifier {
  @override
  String? build() => null;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(PrismToast.resetForTest);

  Widget buildSubject({
    bool chatEnabled = true,
    bool syncEnabled = false,
    GifServiceConfig gifConfig = const GifServiceConfig.disabled(),
  }) {
    return ProviderScope(
      overrides: [
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(SystemSettings(chatEnabled: chatEnabled)),
        ),
        gifServiceConfigProvider.overrideWith((ref) async => gifConfig),
        syncEnabledProvider.overrideWithValue(syncEnabled),
        speakingAsProvider.overrideWith(_NullSpeakingAsNotifier.new),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: ChatFeatureSettingsScreen(),
      ),
    );
  }

  group('ChatFeatureSettingsScreen proxy-tag toggle', () {
    testWidgets('row is visible when chat is enabled', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Use proxy tags to author messages'), findsOneWidget);
    });

    testWidgets('row is hidden when chat is disabled', (tester) async {
      await tester.pumpWidget(buildSubject(chatEnabled: false));
      await tester.pumpAndSettle();

      expect(find.text('Use proxy tags to author messages'), findsNothing);
    });

    testWidgets('toggling persists to SharedPreferences', (tester) async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.use_proxy_tags_for_authoring': false,
      });

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use proxy tags to author messages'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.use_proxy_tags_for_authoring'), true);
    });
  });

  group('ChatFeatureSettingsScreen GIF gating', () {
    testWidgets(
      'does not route enabled sync users to sync setup when GIF config is unavailable',
      (tester) async {
        await tester.pumpWidget(buildSubject(syncEnabled: true));
        await tester.pumpAndSettle();

        await tester.tap(find.text('GIF Search'));
        await tester.pumpAndSettle();
        PrismToast.resetForTest();

        expect(find.text('Sync required for GIFs'), findsNothing);
        expect(find.text('Set up sync'), findsNothing);
      },
    );
  });
}
