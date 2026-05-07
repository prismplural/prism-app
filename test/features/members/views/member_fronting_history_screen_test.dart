import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/members/views/member_fronting_history_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _buildSubject({
  required double width,
  required String memberName,
  required ValueChanged<String> onTitle,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: Builder(
        builder: (context) {
          onTitle(
            memberFrontingHistoryTitleForWidth(
              context: context,
              memberName: memberName,
            ),
          );
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

void main() {
  testWidgets('member history title includes sessions suffix when it fits', (
    tester,
  ) async {
    String? title;

    await tester.pumpWidget(
      _buildSubject(
        width: 520,
        memberName: 'Alex',
        onTitle: (value) => title = value,
      ),
    );

    expect(title, "Alex's Sessions");
  });

  testWidgets('member history title falls back to name when suffix overflows', (
    tester,
  ) async {
    String? title;
    const longName = 'Alexandria Cassandra Meridian';

    await tester.pumpWidget(
      _buildSubject(
        width: 320,
        memberName: longName,
        onTitle: (value) => title = value,
      ),
    );

    expect(title, longName);
  });
}
