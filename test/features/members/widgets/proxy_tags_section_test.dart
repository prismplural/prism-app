import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/widgets/proxy_tags_section.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

Member _member({
  String? pluralkitId,
  String? pluralkitUuid,
  String? proxyTagsJson,
}) =>
    Member(
      id: 'local-1',
      name: 'Alice',
      pluralkitId: pluralkitId,
      pluralkitUuid: pluralkitUuid,
      proxyTagsJson: proxyTagsJson,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('linked member with tags shows chips + deeplink button',
      (tester) async {
    final uris = <Uri>[];
    await tester.pumpWidget(_wrap(ProxyTagsSection(
      member: _member(
        pluralkitId: 'abcde',
        proxyTagsJson: '[{"prefix":"A:","suffix":null},'
            '{"prefix":null,"suffix":"-a"}]',
      ),
      launcher: (u) async {
        uris.add(u);
        return true;
      },
    )));

    expect(find.text('Proxy Tags'), findsOneWidget);
    expect(find.text('A:text'), findsOneWidget);
    expect(find.text('text-a'), findsOneWidget);
    expect(find.text('Proxy tags are managed on PluralKit.'), findsOneWidget);

    final button = find.widgetWithText(PrismButton, 'Edit on PluralKit');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();

    expect(uris, hasLength(1));
    expect(uris.first.toString(), 'https://dash.pluralkit.me/profile/m/abcde');
  });

  testWidgets('linked member with no tags shows empty copy', (tester) async {
    await tester.pumpWidget(_wrap(ProxyTagsSection(
      member: _member(pluralkitId: 'abcde', proxyTagsJson: null),
      launcher: (_) async => true,
    )));

    expect(find.text('No proxy tags set.'), findsOneWidget);
    expect(find.widgetWithText(PrismButton, 'Edit on PluralKit'),
        findsOneWidget);
  });

  testWidgets('unlinked member collapses the whole section', (tester) async {
    await tester.pumpWidget(_wrap(ProxyTagsSection(
      member: _member(proxyTagsJson: '[{"prefix":"A:","suffix":null}]'),
      launcher: (_) async => true,
    )));

    expect(find.text('Proxy Tags'), findsNothing);
    expect(find.widgetWithText(PrismButton, 'Edit on PluralKit'), findsNothing);
  });

  testWidgets('malformed JSON falls back to empty state', (tester) async {
    await tester.pumpWidget(_wrap(ProxyTagsSection(
      member: _member(pluralkitId: 'abcde', proxyTagsJson: 'not-json'),
      launcher: (_) async => true,
    )));

    expect(find.text('No proxy tags set.'), findsOneWidget);
  });
}
