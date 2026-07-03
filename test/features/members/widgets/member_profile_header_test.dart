import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/members/widgets/member_profile_header.dart';
import 'package:prism_plurality/features/members/widgets/member_profile_header_editor.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lB0Q9wAAAABJRU5ErkJggg==',
);

Member _member({
  String id = 'member-1',
  String name = 'Alice',
  MemberProfileHeaderSource profileHeaderSource =
      MemberProfileHeaderSource.prism,
  MemberProfileHeaderLayout profileHeaderLayout =
      MemberProfileHeaderLayout.compactBackground,
  bool profileHeaderVisible = true,
  Uint8List? profileHeaderImageData,
  Uint8List? pkBannerImageData,
  String? pkBannerUrl,
  String? pkBannerCachedUrl,
  String? pronouns,
}) => Member(
  id: id,
  name: name,
  emoji: '*',
  pronouns: pronouns,
  createdAt: DateTime(2026, 4, 1),
  profileHeaderSource: profileHeaderSource,
  profileHeaderLayout: profileHeaderLayout,
  profileHeaderVisible: profileHeaderVisible,
  profileHeaderImageData: profileHeaderImageData,
  pkBannerImageData: pkBannerImageData,
  pkBannerUrl: pkBannerUrl,
  pkBannerCachedUrl: pkBannerCachedUrl,
);

Widget _wrap(Widget child, {FrontingTerms? frontingTerms}) {
  return ProviderScope(
    overrides: [
      if (frontingTerms != null)
        frontingTermsSettingProvider.overrideWithValue(frontingTerms),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Finder get _headerImages => find.byWidgetPredicate(
  (widget) => widget is Image && widget.semanticLabel == 'Alice profile header',
);

void main() {
  testWidgets('compact header renders metadata over background image', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Padding(
          padding: const EdgeInsets.all(16),
          child: MemberProfileHeader(
            member: _member(profileHeaderImageData: _pngBytes),
          ),
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(_headerImages, findsOneWidget);
    expect(find.byType(AspectRatio), findsNothing);
  });

  testWidgets('hidden header preserves metadata but does not render image', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Padding(
          padding: const EdgeInsets.all(16),
          child: MemberProfileHeader(
            member: _member(
              profileHeaderVisible: false,
              profileHeaderImageData: _pngBytes,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(_headerImages, findsNothing);
  });

  testWidgets('classic header renders banner aspect ratio above metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Padding(
          padding: const EdgeInsets.all(16),
          child: MemberProfileHeader(
            member: _member(
              profileHeaderLayout: MemberProfileHeaderLayout.classicOverlap,
              profileHeaderImageData: _pngBytes,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(_headerImages, findsOneWidget);
    final aspectRatio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(aspectRatio.aspectRatio, 3);
  });

  testWidgets('long pronoun chip wraps in the profile header', (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;

    const pronouns =
        'She/Her, Sae/Saers, Lace/Laces, Bliss/Blissful, Pure/Pures';

    await tester.pumpWidget(
      _wrap(
        Padding(
          padding: const EdgeInsets.all(16),
          child: MemberProfileHeader(
            member: _member(
              pronouns: pronouns,
              profileHeaderLayout: MemberProfileHeaderLayout.classicOverlap,
              profileHeaderImageData: _pngBytes,
            ),
            isFronting: true,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final pronounText = tester.widget<Text>(find.text(pronouns));
    expect(pronounText.maxLines, 2);
    expect(pronounText.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.text(pronouns)).height, greaterThan(16));
  });

  testWidgets('fronting chip follows fronting terminology preset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Padding(
          padding: const EdgeInsets.all(16),
          child: MemberProfileHeader(member: _member(), isFronting: true),
        ),
        frontingTerms: const FrontingTerms.preset(FrontingTermPreset.online),
      ),
    );

    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Fronting'), findsNothing);
  });

  testWidgets(
    'editor source, layout, change, and remove controls update state',
    (tester) async {
      var source = MemberProfileHeaderSource.prism;
      var layout = MemberProfileHeaderLayout.compactBackground;
      var visible = true;
      Uint8List? prismHeaderImageData = _pngBytes;
      var removed = false;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) => MemberProfileHeaderEditor(
              member: _member(
                profileHeaderImageData: prismHeaderImageData,
                pkBannerImageData: _pngBytes,
                pkBannerUrl: 'https://cdn.example.com/banner.png',
              ),
              source: source,
              layout: layout,
              visible: visible,
              prismHeaderImageData: prismHeaderImageData,
              pluralKitHeaderImageData: _pngBytes,
              pluralKitEligible: true,
              onSourceChanged: (value) => setState(() => source = value),
              onLayoutChanged: (value) => setState(() => layout = value),
              onVisibleChanged: (value) => setState(() => visible = value),
              onPrismHeaderImageChanged: (value) =>
                  setState(() => prismHeaderImageData = value),
              onPrismHeaderImageRemoved: () => removed = true,
              pickCroppedHeaderBytes: (_) async =>
                  Uint8List.fromList([9, 8, 7]),
            ),
          ),
        ),
      );

      await tester.tap(find.text('PluralKit').first);
      await tester.pumpAndSettle();
      expect(source, MemberProfileHeaderSource.pluralKit);

      await tester.tap(find.text('Hide profile banner'));
      await tester.pumpAndSettle();
      expect(visible, isFalse);

      await tester.ensureVisible(find.text('Classic').first);
      await tester.tap(find.text('Classic').first);
      await tester.pumpAndSettle();
      expect(layout, MemberProfileHeaderLayout.classicOverlap);

      await tester.ensureVisible(find.text('Change banner'));
      await tester.tap(find.text('Change banner'));
      await tester.pumpAndSettle();
      expect(source, MemberProfileHeaderSource.prism);
      expect(prismHeaderImageData, Uint8List.fromList([9, 8, 7]));

      await tester.ensureVisible(find.text('Remove banner'));
      await tester.tap(find.text('Remove banner'));
      await tester.pumpAndSettle();
      expect(prismHeaderImageData, isNull);
      expect(removed, isTrue);
    },
  );
}
