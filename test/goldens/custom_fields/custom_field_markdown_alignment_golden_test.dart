import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_display.dart';

import '../../helpers/fake_repositories.dart';
import '../../helpers/prism_golden.dart';

void main() {
  setUpAll(loadPrismGoldenFonts);

  testWidgets('renders long-text markdown alignment fences', (tester) async {
    await _expectGolden(
      tester,
      surfaceSize: const Size(520, 780),
      goldenPath: 'goldens/custom_field_markdown_alignment.png',
      child: PrismGoldenBoard(
        key: _alignmentKey,
        scenarios: [
          PrismGoldenScenario(
            name: 'phone light',
            child: _alignmentScenario(
              themeVariant: PrismGoldenThemeVariant.light,
            ),
          ),
        ],
      ),
    );
  }, tags: ['golden']);
}

const _alignmentKey = ValueKey('custom-field-markdown-alignment-golden');
const _memberId = 'member-1';

Future<void> _expectGolden(
  WidgetTester tester, {
  required Size surfaceSize,
  required String goldenPath,
  required Widget child,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    RepaintBoundary(
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
  await tester.pumpAndSettle();

  final targetKey = child.key;
  assert(targetKey != null, 'Golden root widgets must have a key.');
  await expectLater(find.byKey(targetKey!), matchesGoldenFile(goldenPath));
}

Widget _alignmentScenario({
  required PrismGoldenThemeVariant themeVariant,
  PrismGoldenDevice device = prismGoldenPhone,
}) {
  return prismGoldenApp(
    themeVariant: themeVariant,
    device: device,
    overrides: _providerOverrides(),
    child: const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: CustomFieldsDisplay(memberId: _memberId),
    ),
  );
}

List<Override> _providerOverrides() {
  final memberRepo = FakeMemberRepository()..seed([_member]);
  return [
    memberRepositoryProvider.overrideWithValue(memberRepo),
    customFieldsProvider.overrideWithValue(AsyncValue.data([_field])),
    memberCustomFieldValuesProvider(
      _memberId,
    ).overrideWithValue(AsyncValue.data([_value])),
  ];
}

final _member = Member(
  id: _memberId,
  name: 'Robin',
  createdAt: DateTime.utc(2026, 1, 1),
);

final _field = CustomField(
  id: 'alignment-notes',
  name: 'Markdown alignment',
  fieldType: CustomFieldType.text,
  fieldTypeId: 'long_text',
  createdAt: DateTime.utc(2026, 1, 1),
  typeConfig: const LongTextConfig(
    headerIcon: CustomFieldHeaderIcon.phosphor('article'),
  ),
);

final _value = CustomFieldValue(
  id: 'value-alignment-notes',
  customFieldId: 'alignment-notes',
  memberId: _memberId,
  value:
      'Default reference line\n\n'
      ':::center\n'
      'Centered marker line\n'
      ':::\n\n'
      ':::right\n'
      'Right marker line\n'
      ':::',
);
