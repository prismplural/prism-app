import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/widgets/proxy_tags_section.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Member _member({String? pluralkitId, String? proxyTagsJson}) => Member(
  id: 'local-1',
  name: 'Alice',
  pluralkitId: pluralkitId,
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
  testWidgets('renders chips for parsed proxy tags', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ProxyTagsSection(
          member: _member(
            proxyTagsJson:
                '[{"prefix":"A:","suffix":null},'
                '{"prefix":null,"suffix":"-a"}]',
          ),
        ),
      ),
    );

    expect(find.text('Proxy Tags'), findsOneWidget);
    expect(find.text('A:text'), findsOneWidget);
    expect(find.text('text-a'), findsOneWidget);
  });

  testWidgets('renders nothing when no tags are set', (tester) async {
    await tester.pumpWidget(
      _wrap(ProxyTagsSection(member: _member(proxyTagsJson: null))),
    );

    expect(find.text('Proxy Tags'), findsNothing);
  });

  testWidgets('renders nothing for malformed JSON', (tester) async {
    await tester.pumpWidget(
      _wrap(ProxyTagsSection(member: _member(proxyTagsJson: 'not-json'))),
    );

    expect(find.text('Proxy Tags'), findsNothing);
  });

  testWidgets('renders nothing when tags array is empty', (tester) async {
    await tester.pumpWidget(
      _wrap(ProxyTagsSection(member: _member(proxyTagsJson: '[]'))),
    );

    expect(find.text('Proxy Tags'), findsNothing);
  });
}
