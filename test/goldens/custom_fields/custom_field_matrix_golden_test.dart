import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_display.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_editor.dart';

import '../../helpers/fake_repositories.dart';
import '../../helpers/prism_golden_test.dart';

void main() {
  setUpAll(loadPrismGoldenFonts);

  group('Custom field golden matrix', () {
    testWidgets('renders profile display variants', (tester) async {
      await _expectGolden(
        tester,
        surfaceSize: const Size(940, 3000),
        goldenPath: 'goldens/custom_field_profile_display_matrix.png',
        child: PrismGoldenBoard(
          key: _profileDisplayKey,
          scenarios: [
            PrismGoldenScenario(
              name: 'phone light',
              child: _profileDisplayScenario(
                themeVariant: PrismGoldenThemeVariant.light,
              ),
            ),
            PrismGoldenScenario(
              name: 'phone dark',
              child: _profileDisplayScenario(
                themeVariant: PrismGoldenThemeVariant.dark,
              ),
            ),
            PrismGoldenScenario(
              name: 'phone high text',
              child: _profileDisplayScenario(
                themeVariant: PrismGoldenThemeVariant.light,
                textScaleFactor: 1.3,
              ),
            ),
            PrismGoldenScenario(
              name: 'phone palette lime',
              child: _profileDisplayScenario(
                themeVariant: PrismGoldenThemeVariant.paletteLight,
              ),
            ),
            PrismGoldenScenario(
              name: 'tablet oled',
              width: prismGoldenTablet.size.width,
              child: _profileDisplayScenario(
                themeVariant: PrismGoldenThemeVariant.oled,
                device: prismGoldenTablet,
              ),
            ),
          ],
        ),
      );
    }, tags: ['golden']);

    testWidgets('renders editor variants', (tester) async {
      await _expectGolden(
        tester,
        surfaceSize: const Size(940, 2600),
        goldenPath: 'goldens/custom_field_editor_matrix.png',
        child: PrismGoldenBoard(
          key: _editorKey,
          scenarios: [
            PrismGoldenScenario(
              name: 'phone light',
              child: _editorScenario(
                themeVariant: PrismGoldenThemeVariant.light,
              ),
            ),
            PrismGoldenScenario(
              name: 'phone dark',
              child: _editorScenario(
                themeVariant: PrismGoldenThemeVariant.dark,
              ),
            ),
            PrismGoldenScenario(
              name: 'phone high text',
              child: _editorScenario(
                themeVariant: PrismGoldenThemeVariant.light,
                textScaleFactor: 1.3,
              ),
            ),
            PrismGoldenScenario(
              name: 'phone palette lime',
              child: _editorScenario(
                themeVariant: PrismGoldenThemeVariant.paletteLight,
              ),
            ),
            PrismGoldenScenario(
              name: 'tablet oled',
              width: prismGoldenTablet.size.width,
              child: _editorScenario(
                themeVariant: PrismGoldenThemeVariant.oled,
                device: prismGoldenTablet,
              ),
            ),
          ],
        ),
      );
    }, tags: ['golden']);
  });
}

const _profileDisplayKey = ValueKey('custom-field-profile-display-golden');
const _editorKey = ValueKey('custom-field-editor-golden');

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

Widget _profileDisplayScenario({
  required PrismGoldenThemeVariant themeVariant,
  PrismGoldenDevice device = prismGoldenPhone,
  double textScaleFactor = 1,
}) {
  return prismGoldenApp(
    themeVariant: themeVariant,
    device: device,
    textScaleFactor: textScaleFactor,
    overrides: _providerOverrides(),
    child: const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: CustomFieldsDisplay(memberId: _memberId),
    ),
  );
}

Widget _editorScenario({
  required PrismGoldenThemeVariant themeVariant,
  PrismGoldenDevice device = prismGoldenPhone,
  double textScaleFactor = 1,
}) {
  return prismGoldenApp(
    themeVariant: themeVariant,
    device: device,
    textScaleFactor: textScaleFactor,
    overrides: _providerOverrides(),
    child: const SizedBox(
      height: 760,
      child: CustomFieldsEditor(
        memberId: _memberId,
        padding: EdgeInsets.all(16),
      ),
    ),
  );
}

List<Override> _providerOverrides() {
  final memberRepo = FakeMemberRepository()..seed(_members);
  final fields = _fields();
  return [
    memberRepositoryProvider.overrideWithValue(memberRepo),
    membersByIdsListProvider(
      memberIdsKey(_supportMemberIds),
    ).overrideWithValue(AsyncValue.data(_membersById())),
    customFieldsProvider.overrideWithValue(AsyncValue.data(fields)),
    memberCustomFieldValuesProvider(
      _memberId,
    ).overrideWithValue(AsyncValue.data(_values())),
  ];
}

const _memberId = 'member-1';
const _supportMemberIds = ['alice', 'bob', 'charlie'];

final _members = [
  _member('alice', 'Alice'),
  _member('bob', 'Bob'),
  _member('charlie', 'Charlie', isActive: false),
];

Member _member(String id, String name, {bool isActive = true}) {
  return Member(
    id: id,
    name: name,
    isActive: isActive,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

Map<String, Member> _membersById() {
  return {for (final member in _members) member.id: member};
}

List<CustomField> _fields() {
  final createdAt = DateTime.utc(2026, 1, 1);
  return [
    _field(
      id: 'nickname',
      name: 'Nickname',
      typeId: 'text',
      createdAt: createdAt,
      typeConfig: const TextConfig(
        headerIcon: CustomFieldHeaderIcon.phosphor('identification-card'),
      ),
    ),
    _field(
      id: 'about',
      name: 'About this member',
      typeId: 'long_text',
      displayOrder: 1,
      createdAt: createdAt,
      typeConfig: const LongTextConfig(
        headerIcon: CustomFieldHeaderIcon.phosphor('article'),
      ),
    ),
    _field(
      id: 'accent',
      name: 'Accent color',
      typeId: 'color',
      displayOrder: 2,
      createdAt: createdAt,
      typeConfig: const ColorConfig(
        headerIcon: CustomFieldHeaderIcon.phosphor('palette'),
      ),
    ),
    _field(
      id: 'birthday',
      name: 'Birthday',
      typeId: 'date',
      displayOrder: 3,
      createdAt: createdAt,
      typeConfig: const DateConfig(
        headerIcon: CustomFieldHeaderIcon.phosphor('calendar'),
      ),
    ),
    _field(
      id: 'favorites',
      name: 'Favorite colors',
      typeId: 'choice',
      displayOrder: 4,
      createdAt: createdAt,
      typeConfig: const ChoiceConfig(
        allowsMultiple: true,
        allowsOther: true,
        headerIcon: CustomFieldHeaderIcon.phosphor('heart-fill'),
        options: [
          ChoiceOption(
            id: 'green',
            label: 'Green',
            colorHex: '#5B8F62',
            sortOrder: 0,
          ),
          ChoiceOption(
            id: 'blue',
            label: 'Blue',
            colorHex: '#5076B8',
            sortOrder: 1,
          ),
          ChoiceOption(
            id: 'old-red',
            label: 'Old red',
            colorHex: '#A85555',
            sortOrder: 2,
            isDeleted: true,
          ),
        ],
      ),
    ),
    _field(
      id: 'spark',
      name: 'Spark',
      typeId: 'scale',
      displayOrder: 5,
      createdAt: createdAt,
      typeConfig: const ScaleConfig(
        emoji: '*',
        steps: 5,
        stepLabels: ['Low', 'Soft', 'Bright', 'Loud', 'Blazing'],
        displayLayout: DisplayLayout.stacked,
        headerIcon: CustomFieldHeaderIcon.phosphor('sparkle'),
      ),
    ),
    _field(
      id: 'energy',
      name: 'Energy spectrum',
      typeId: 'slider',
      displayOrder: 6,
      createdAt: createdAt,
      typeConfig: const SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Quiet',
        centerLabel: 'Balanced',
        rightLabel: 'Bright',
        gradientPresetId: 'soft-hard',
        showTicks: true,
        headerIcon: CustomFieldHeaderIcon.phosphor('sliders-horizontal'),
      ),
    ),
    _field(
      id: 'support',
      name: 'Support team',
      typeId: 'member',
      displayOrder: 7,
      createdAt: createdAt,
      typeConfig: const MemberConfig(
        displayLayout: DisplayLayout.compact,
        headerIcon: CustomFieldHeaderIcon.phosphor('users-three'),
      ),
    ),
    _field(
      id: 'identity',
      name: 'Identity notes',
      typeId: 'group',
      displayOrder: 8,
      createdAt: createdAt,
      typeConfig: const GroupConfig(
        headerIcon: CustomFieldHeaderIcon.phosphor('folder-simple'),
      ),
    ),
    _field(
      id: 'group-pronouns',
      name: 'Pronouns',
      typeId: 'text',
      displayOrder: 0,
      parentFieldId: 'identity',
      createdAt: createdAt,
      typeConfig: const TextConfig(hideTitleOnProfile: true),
    ),
    _field(
      id: 'group-choice',
      name: 'Comfort colors',
      typeId: 'choice',
      displayOrder: 1,
      parentFieldId: 'identity',
      createdAt: createdAt,
      typeConfig: const ChoiceConfig(
        allowsMultiple: true,
        options: [
          ChoiceOption(id: 'soft', label: 'Soft', sortOrder: 0),
          ChoiceOption(id: 'bright', label: 'Bright', sortOrder: 1),
        ],
      ),
    ),
  ];
}

CustomField _field({
  required String id,
  required String name,
  required String typeId,
  required DateTime createdAt,
  int displayOrder = 0,
  String? parentFieldId,
  CustomFieldTypeConfig? typeConfig,
}) {
  return CustomField(
    id: id,
    name: name,
    fieldType: CustomFieldType.text,
    fieldTypeId: typeId,
    displayOrder: displayOrder,
    parentFieldId: parentFieldId,
    createdAt: createdAt,
    typeConfig: typeConfig,
  );
}

List<CustomFieldValue> _values() {
  return [
    _value('nickname', 'North Star'),
    _value(
      'about',
      '# A soft summary\n\nLikes fronting with **music**, tea, and quiet plans.',
    ),
    _value('accent', '#8E66C9'),
    _value('birthday', '2026-06-15T12:30:00.000Z'),
    _value(
      'favorites',
      '{"options":["blue","green","old-red"],"other":"Lilac"}',
    ),
    _value('spark', '4'),
    _value('energy', '65'),
    _value('support', '{"memberIds":["alice","bob","charlie"]}'),
    _value('group-pronouns', 'they / she'),
    _value('group-choice', '{"options":["soft","bright"]}'),
  ];
}

CustomFieldValue _value(String fieldId, String rawValue) {
  return CustomFieldValue(
    id: 'value-$fieldId',
    customFieldId: fieldId,
    memberId: _memberId,
    value: rawValue,
  );
}
