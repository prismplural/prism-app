import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_system_profile_disclosure.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Finder _row(PkProfileField field) =>
    find.byKey(ValueKey('pk_profile_field_${field.name}'));

void main() {
  testWidgets('hides rows whose PK value is null/empty; pre-checks blank-Prism rows',
      (tester) async {
    await tester.pumpWidget(_wrap(PkSystemProfileDisclosureSheet(
      pkSystem: const PKSystem(id: 'sys', name: 'Nova', tag: '| Nova'),
      currentPrismSettings: const SystemSettings(),
      onConfirm: (_) {},
      onSkip: () {},
    )));

    expect(_row(PkProfileField.name), findsOneWidget);
    expect(_row(PkProfileField.tag), findsOneWidget);
    expect(_row(PkProfileField.description), findsNothing);
    expect(_row(PkProfileField.avatar), findsNothing);

    final nameTile = tester.widget<CheckboxListTile>(_row(PkProfileField.name));
    final tagTile = tester.widget<CheckboxListTile>(_row(PkProfileField.tag));
    expect(nameTile.value, isTrue);
    expect(tagTile.value, isTrue);
  });

  testWidgets('row is unchecked with overwrite hint when Prism field has a value',
      (tester) async {
    await tester.pumpWidget(_wrap(PkSystemProfileDisclosureSheet(
      pkSystem: const PKSystem(
        id: 'sys',
        name: 'Nova',
        description: 'desc',
        tag: '| Nova',
        avatarUrl: 'https://example.com/a.png',
      ),
      currentPrismSettings: const SystemSettings(systemName: 'Existing'),
      onConfirm: (_) {},
      onSkip: () {},
    )));

    final nameTile = tester.widget<CheckboxListTile>(_row(PkProfileField.name));
    expect(nameTile.value, isFalse);
    expect(
      find.descendant(
        of: _row(PkProfileField.name),
        matching: find.text('Prism already has a value — tick to overwrite.'),
      ),
      findsOneWidget,
    );

    for (final f in [
      PkProfileField.description,
      PkProfileField.tag,
      PkProfileField.avatar,
    ]) {
      final tile = tester.widget<CheckboxListTile>(_row(f));
      expect(tile.value, isTrue, reason: '${f.name} should be pre-checked');
    }
  });

  testWidgets('Import invokes onConfirm with selected set', (tester) async {
    Set<PkProfileField>? accepted;
    await tester.pumpWidget(_wrap(PkSystemProfileDisclosureSheet(
      pkSystem: const PKSystem(id: 'sys', name: 'Nova', tag: '| Nova'),
      currentPrismSettings: const SystemSettings(),
      onConfirm: (s) => accepted = s,
      onSkip: () {},
    )));

    // Untick the tag row.
    await tester.tap(_row(PkProfileField.tag));
    await tester.pump();

    await tester.tap(find.text('Import selected'));
    await tester.pump();

    expect(accepted, {PkProfileField.name});
  });

  testWidgets('Skip invokes onSkip', (tester) async {
    var skipped = false;
    await tester.pumpWidget(_wrap(PkSystemProfileDisclosureSheet(
      pkSystem: const PKSystem(id: 'sys', name: 'Nova'),
      currentPrismSettings: const SystemSettings(),
      onConfirm: (_) {},
      onSkip: () => skipped = true,
    )));

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(skipped, isTrue);
  });
}
