import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';

import '../../helpers/prism_golden.dart';

void main() {
  setUpAll(loadPrismGoldenFonts);

  group('Custom field sheet goldens', () {
    testWidgets('renders create/edit shell variants', (tester) async {
      await _expectGolden(
        tester,
        surfaceSize: const Size(940, 3200),
        goldenPath: 'goldens/custom_field_sheet_shell_matrix.png',
        child: PrismGoldenBoard(
          key: _sheetShellKey,
          scenarios: [
            PrismGoldenScenario(
              name: 'new field / phone light',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.light,
              ),
            ),
            PrismGoldenScenario(
              name: 'new child / phone dark',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.dark,
                parentFieldId: 'identity',
              ),
            ),
            PrismGoldenScenario(
              name: 'edit group / high text',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.light,
                textScaleFactor: 1.3,
                field: _groupField(),
              ),
            ),
            PrismGoldenScenario(
              name: 'new field / palette lime',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.paletteLight,
              ),
            ),
            PrismGoldenScenario(
              name: 'new field / tablet oled',
              width: _sheetTablet.size.width,
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.oled,
                device: _sheetTablet,
              ),
            ),
          ],
        ),
      );
    }, tags: ['golden']);

    testWidgets('renders configured field type sections', (tester) async {
      await _expectGolden(
        tester,
        surfaceSize: const Size(940, 3800),
        goldenPath: 'goldens/custom_field_sheet_config_matrix.png',
        child: PrismGoldenBoard(
          key: _sheetConfigKey,
          scenarios: [
            PrismGoldenScenario(
              name: 'choice options',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.light,
                device: _sheetTallPhone,
                field: _choiceField(),
              ),
            ),
            PrismGoldenScenario(
              name: 'scale palette',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.dark,
                device: _sheetTallPhone,
                field: _scaleField(),
              ),
            ),
            PrismGoldenScenario(
              name: 'slider labeled',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.light,
                textScaleFactor: 1.3,
                device: _sheetTallPhone,
                field: _labeledSliderField(),
              ),
            ),
            PrismGoldenScenario(
              name: 'slider numeric',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.dark,
                device: _sheetTallPhone,
                field: _numericSliderField(),
              ),
            ),
            PrismGoldenScenario(
              name: 'member layout',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.oled,
                device: _sheetTallPhone,
                field: _memberField(),
              ),
            ),
            PrismGoldenScenario(
              name: 'choice options / palette dark',
              child: _sheetScenario(
                themeVariant: PrismGoldenThemeVariant.paletteDark,
                device: _sheetTallPhone,
                field: _choiceField(),
              ),
            ),
          ],
        ),
      );
    }, tags: ['golden']);
  });
}

const _sheetShellKey = ValueKey('custom-field-sheet-shell-golden');
const _sheetConfigKey = ValueKey('custom-field-sheet-config-golden');

const _sheetPhone = PrismGoldenDevice(
  name: 'sheet-phone',
  size: Size(390, 980),
);

const _sheetTallPhone = PrismGoldenDevice(
  name: 'sheet-tall-phone',
  size: Size(390, 1180),
);

const _sheetTablet = PrismGoldenDevice(
  name: 'sheet-tablet',
  size: Size(834, 980),
);

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

Widget _sheetScenario({
  required PrismGoldenThemeVariant themeVariant,
  CustomField? field,
  String? parentFieldId,
  PrismGoldenDevice device = _sheetPhone,
  double textScaleFactor = 1,
}) {
  return prismGoldenApp(
    themeVariant: themeVariant,
    device: device,
    textScaleFactor: textScaleFactor,
    overrides: _providerOverrides(),
    child: _CreateEditFieldSheetFixture(
      field: field,
      parentFieldId: parentFieldId,
    ),
  );
}

List<Override> _providerOverrides() {
  return [
    customFieldNotifierProvider.overrideWith(_GoldenCustomFieldNotifier.new),
    terminologySettingProvider.overrideWithValue((
      term: SystemTerminology.headmates,
      customSingular: null,
      customPlural: null,
      useEnglish: false,
    )),
  ];
}

class _GoldenCustomFieldNotifier extends CustomFieldNotifier {
  @override
  Future<void> build() async {}
}

class _CreateEditFieldSheetFixture extends StatefulWidget {
  const _CreateEditFieldSheetFixture({this.field, this.parentFieldId});

  final CustomField? field;
  final String? parentFieldId;

  @override
  State<_CreateEditFieldSheetFixture> createState() =>
      _CreateEditFieldSheetFixtureState();
}

class _CreateEditFieldSheetFixtureState
    extends State<_CreateEditFieldSheetFixture> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CreateEditFieldSheet(
      field: widget.field,
      parentFieldId: widget.parentFieldId,
      scrollController: _scrollController,
    );
  }
}

CustomField _choiceField() {
  return _field(
    id: 'favorite-colors',
    name: 'Favorite colors',
    typeId: 'choice',
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
          id: 'violet',
          label: 'Violet',
          colorHex: '#8E66C9',
          sortOrder: 2,
        ),
      ],
    ),
  );
}

CustomField _scaleField() {
  return _field(
    id: 'spark',
    name: 'Spark',
    typeId: 'scale',
    typeConfig: const ScaleConfig(
      emoji: '*',
      steps: 8,
      displayLayout: DisplayLayout.compact,
      headerIcon: CustomFieldHeaderIcon.phosphor('sparkle'),
    ),
  );
}

CustomField _labeledSliderField() {
  return _field(
    id: 'energy',
    name: 'Energy spectrum',
    typeId: 'slider',
    typeConfig: const SliderConfig(
      mode: SliderMode.labeled,
      leftLabel: 'Quiet',
      centerLabel: 'Balanced',
      rightLabel: 'Bright',
      gradientPresetId: 'soft-hard',
      snapToPositions: true,
      showTicks: true,
      headerIcon: CustomFieldHeaderIcon.phosphor('sliders-horizontal'),
    ),
  );
}

CustomField _numericSliderField() {
  return _field(
    id: 'comfort',
    name: 'Comfort score',
    typeId: 'slider',
    typeConfig: const SliderConfig(
      mode: SliderMode.numeric,
      min: -5,
      max: 5,
      step: 0.5,
      unit: 'pts',
      showTicks: true,
      headerIcon: CustomFieldHeaderIcon.phosphor('gauge'),
    ),
  );
}

CustomField _memberField() {
  return _field(
    id: 'support',
    name: 'Support team',
    typeId: 'member',
    typeConfig: const MemberConfig(
      displayLayout: DisplayLayout.stacked,
      headerIcon: CustomFieldHeaderIcon.phosphor('users-three'),
    ),
  );
}

CustomField _groupField() {
  return _field(
    id: 'identity',
    name: 'Identity notes',
    typeId: 'group',
    typeConfig: const GroupConfig(
      headerIcon: CustomFieldHeaderIcon.phosphor('folder-simple'),
    ),
  );
}

CustomField _field({
  required String id,
  required String name,
  required String typeId,
  CustomFieldTypeConfig? typeConfig,
}) {
  return CustomField(
    id: id,
    name: name,
    fieldType: CustomFieldType.text,
    fieldTypeId: typeId,
    displayOrder: 0,
    createdAt: DateTime.utc(2026, 1, 1),
    typeConfig: typeConfig,
  );
}
