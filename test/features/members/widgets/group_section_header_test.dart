import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/widgets/group_section_header.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

MemberGroup _group(String name, {String? emoji, String? colorHex}) =>
    MemberGroup(
      id: 'g',
      name: name,
      emoji: emoji,
      colorHex: colorHex,
      createdAt: DateTime(2024, 1, 1),
    );

MemberGroup _grp(String name) => MemberGroup(
  id: name,
  name: name,
  createdAt: DateTime(2024, 1, 1),
);

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  ),
);

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  ),
);

void main() {
  // Simply Plural lets users embed newlines in group names — some users have
  // up to three lines (primary label, separator, decorative line). Truncating
  // drops the trailing lines silently; the header must render all three.
  testWidgets('renders three-line group names without dropping lines', (
    tester,
  ) async {
    const threeLineName = 'Gender\n*.:: 🌙 ✦\nMan';

    await tester.pumpWidget(
      _host(
        GroupSectionHeader(
          group: _group(threeLineName, emoji: '🌙', colorHex: '#88CC88'),
          depth: 0,
          memberCount: 3,
          isCollapsed: false,
          canCollapse: true,
          onToggle: () {},
        ),
      ),
    );
    await tester.pump();

    final textFinder = find.text(threeLineName);
    expect(textFinder, findsOneWidget);

    final text = tester.widget<Text>(textFinder);
    expect(text.maxLines, greaterThanOrEqualTo(3));

    final renderText = tester.renderObject<RenderParagraph>(textFinder);
    final fontSize = renderText.text.style?.fontSize ?? 14.0;
    expect(
      renderText.size.height,
      greaterThan(fontSize * 2.4),
      reason: 'Expected the three-line name to wrap to ≥3 lines',
    );
  });

  testWidgets('renders a tinted-glass avatar in the leading slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GroupSectionHeader(
          group: _group('Gender', emoji: '⚧️', colorHex: '#88CC88'),
          depth: 0,
          memberCount: 1,
          isCollapsed: false,
          canCollapse: true,
          onToggle: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TintedGlassSurface), findsOneWidget);
    expect(find.text('⚧️'), findsOneWidget);
  });

  group('GroupSectionHeader detail-view affordance', () {
    testWidgets('absent at depth < cap even with deeper descendants', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(_wrap(GroupSectionHeader(
        group: _grp('alpha'),
        depth: 3,
        memberCount: 0,
        isCollapsed: false,
        canCollapse: true,
        onToggle: () {},
        hasDeeperDescendants: true,
        onOpenDetail: () => tapped = true,
      )));
      expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
      expect(tapped, isFalse);
    });

    testWidgets('present at cap when hasDeeperDescendants is true', (tester) async {
      await tester.pumpWidget(_wrap(GroupSectionHeader(
        group: _grp('alpha'),
        depth: kSectionsVisualDepthCap,
        memberCount: 0,
        isCollapsed: false,
        canCollapse: true,
        onToggle: () {},
        hasDeeperDescendants: true,
        onOpenDetail: () {},
      )));
      expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
    });

    testWidgets('absent at cap when hasDeeperDescendants is false', (tester) async {
      await tester.pumpWidget(_wrap(GroupSectionHeader(
        group: _grp('alpha'),
        depth: kSectionsVisualDepthCap,
        memberCount: 0,
        isCollapsed: false,
        canCollapse: true,
        onToggle: () {},
        hasDeeperDescendants: false,
        onOpenDetail: () {},
      )));
      expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
    });

    testWidgets('tap fires onOpenDetail', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(GroupSectionHeader(
        group: _grp('alpha'),
        depth: kSectionsVisualDepthCap,
        memberCount: 0,
        isCollapsed: false,
        canCollapse: true,
        onToggle: () {},
        hasDeeperDescendants: true,
        onOpenDetail: () => tapped++,
      )));
      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pump();
      expect(tapped, 1);
    });
  });
}
