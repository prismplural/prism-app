import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/widgets/group_section_header.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

MemberGroup _group(String name) => MemberGroup(
  id: 'g',
  name: name,
  createdAt: DateTime(2024, 1, 1),
);

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: const [Locale('en')],
  home: Scaffold(body: child),
);

void main() {
  // Simply Plural lets users embed newlines in group names (e.g. a primary
  // label on line 1 and an emoji/decoration line below). Truncating to a
  // single line drops the second line entirely; the header must render both.
  testWidgets('renders multi-line group names without dropping lines', (
    tester,
  ) async {
    const multiLineName = 'Gender\n*.:: Man';

    await tester.pumpWidget(
      _host(
        GroupSectionHeader(
          group: _group(multiLineName),
          depth: 0,
          memberCount: 3,
          isCollapsed: false,
          canCollapse: true,
          onToggle: () {},
        ),
      ),
    );

    final textFinder = find.text(multiLineName);
    expect(textFinder, findsOneWidget);

    final text = tester.widget<Text>(textFinder);
    expect(text.maxLines, greaterThanOrEqualTo(2));

    final renderText = tester.renderObject<RenderParagraph>(textFinder);
    final size = renderText.size;
    // A wrapped 2-line render is taller than a single line of the same style.
    final lineHeight =
        renderText.text.style?.fontSize == null
            ? 14.0
            : renderText.text.style!.fontSize!;
    expect(
      size.height,
      greaterThan(lineHeight * 1.4),
      reason: 'Expected the multi-line name to wrap to ≥2 lines',
    );
  });
}
