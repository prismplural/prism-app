import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';

void main() {
  testWidgets(
    'modalBottomInsetOf uses navigation bar inset when keyboard is closed',
    (tester) async {
      late double inset;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 48)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                inset = modalBottomInsetOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(inset, 48);
    },
  );

  testWidgets('modalBottomInsetOf prefers keyboard when it is taller', (
    tester,
  ) async {
    late double inset;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: 320),
          viewPadding: EdgeInsets.only(bottom: 48),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              inset = modalBottomInsetOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(inset, 320);
  });
}
