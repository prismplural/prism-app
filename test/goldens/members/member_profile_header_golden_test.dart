import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/member_profile_header.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';

import '../../helpers/prism_golden.dart';

void main() {
  setUpAll(loadPrismGoldenFonts);

  group('Member profile header goldens', () {
    testWidgets('renders header variants', (tester) async {
      await _expectGolden(
        tester,
        surfaceSize: const Size(940, 1900),
        goldenPath: 'goldens/member_profile_header_matrix.png',
        child: PrismGoldenBoard(
          key: _profileHeaderKey,
          scenarios: [
            PrismGoldenScenario(
              name: 'compact / no image',
              child: _headerScenario(
                themeVariant: PrismGoldenThemeVariant.light,
                member: _member(
                  name: 'North Star',
                  displayName: 'Navigator',
                  pronouns: 'they / she',
                  birthday: '2011-06-15',
                  customColorHex: '#8E66C9',
                ),
                isFronting: true,
              ),
            ),
            PrismGoldenScenario(
              name: 'compact / image',
              child: _headerScenario(
                themeVariant: PrismGoldenThemeVariant.dark,
                member: _member(
                  name: 'Echo',
                  pronouns: 'he / him',
                  profileHeaderImageData: _appIconPng,
                  avatarImageData: _noisePng,
                  customColorHex: '#5076B8',
                ),
              ),
            ),
            PrismGoldenScenario(
              name: 'classic / high text',
              child: _headerScenario(
                themeVariant: PrismGoldenThemeVariant.light,
                textScaleFactor: 1.3,
                member: _member(
                  name: 'Sunlit Archivist',
                  displayName: 'Archive',
                  pronouns: 'She/Her, Sae/Saers, Lace/Laces, Bliss/Blissful',
                  profileHeaderLayout: MemberProfileHeaderLayout.classicOverlap,
                  profileHeaderImageData: _logoPng,
                  avatarImageData: _appIconPng,
                  customColorHex: '#5B8F62',
                  isAdmin: true,
                ),
              ),
            ),
            PrismGoldenScenario(
              name: 'hidden banner / oled',
              child: _headerScenario(
                themeVariant: PrismGoldenThemeVariant.oled,
                member: _member(
                  name: 'Quiet Signal',
                  pronouns: 'it / its',
                  profileHeaderVisible: false,
                  profileHeaderImageData: _logoPng,
                  customColorHex: '#A85555',
                  isActive: false,
                ),
              ),
            ),
            PrismGoldenScenario(
              name: 'compact / palette lime',
              child: _headerScenario(
                themeVariant: PrismGoldenThemeVariant.paletteLight,
                member: _member(
                  name: 'Highlighter',
                  displayName: 'Glint',
                  pronouns: 'xe / xem',
                  profileHeaderImageData: _logoPng,
                  avatarImageData: _noisePng,
                  customColorHex: prismGoldenPaletteSeedColorHex,
                ),
              ),
            ),
          ],
        ),
      );
    }, tags: ['golden']);
  });
}

const _profileHeaderKey = ValueKey('member-profile-header-golden');
const _headerDevice = PrismGoldenDevice(
  name: 'profile-header-phone',
  size: Size(390, 520),
);

final Uint8List _appIconPng = _assetPng(
  'assets/AppIcon.icon/Assets/ChatGPT Image Aug 14, 2025 at 09_47_20 PM.png',
);
final Uint8List _logoPng = _assetPng(
  'assets/icon_layers/Prism-Logo-Foreground.png',
);
final Uint8List _noisePng = _assetPng('assets/textures/noise_64x64.png');

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
  await tester.pump();
  await _pumpUntilDecodedImages(tester, expectedCount: 6);
  await tester.pumpAndSettle();

  final targetKey = child.key;
  assert(targetKey != null, 'Golden root widgets must have a key.');
  await expectLater(find.byKey(targetKey!), matchesGoldenFile(goldenPath));
}

Future<void> _pumpUntilDecodedImages(
  WidgetTester tester, {
  required int expectedCount,
}) async {
  const maxAttempts = 60;
  const interval = Duration(milliseconds: 50);

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (_decodedImageCount() >= expectedCount) return;

    await tester.runAsync(() async {
      await Future<void>.delayed(interval);
    });
    await tester.pump(interval);
  }

  expect(_decodedImageCount(), greaterThanOrEqualTo(expectedCount));
}

int _decodedImageCount() {
  return find
      .byWidgetPredicate((widget) => widget is RawImage && widget.image != null)
      .evaluate()
      .length;
}

Widget _headerScenario({
  required PrismGoldenThemeVariant themeVariant,
  required Member member,
  bool isFronting = false,
  double textScaleFactor = 1,
}) {
  return prismGoldenApp(
    themeVariant: themeVariant,
    device: _headerDevice,
    textScaleFactor: textScaleFactor,
    overrides: _providerOverrides(),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MemberProfileHeader(member: member, isFronting: isFronting),
    ),
  );
}

List<Override> _providerOverrides() {
  return [
    // Pin legacy mode so this golden keeps exercising the name + display-name
    // secondary layout (display mode shows only the effective name).
    memberNamePreferDisplayProvider.overrideWithValue(false),
    terminologySettingProvider.overrideWithValue((
      term: SystemTerminology.headmates,
      customSingular: null,
      customPlural: null,
      useEnglish: false,
    )),
  ];
}

Uint8List _assetPng(String path) => File(path).readAsBytesSync();

Member _member({
  required String name,
  String id = 'member-1',
  String? displayName,
  String? pronouns,
  String? birthday,
  String? customColorHex,
  bool isAdmin = false,
  bool isActive = true,
  MemberProfileHeaderLayout profileHeaderLayout =
      MemberProfileHeaderLayout.compactBackground,
  bool profileHeaderVisible = true,
  Uint8List? profileHeaderImageData,
  Uint8List? avatarImageData,
}) {
  return Member(
    id: id,
    name: name,
    displayName: displayName,
    pronouns: pronouns,
    birthday: birthday,
    emoji: '*',
    avatarImageData: avatarImageData,
    customColorEnabled: customColorHex != null,
    customColorHex: customColorHex,
    isAdmin: isAdmin,
    isActive: isActive,
    createdAt: DateTime.utc(2026, 1, 1),
    profileHeaderLayout: profileHeaderLayout,
    profileHeaderVisible: profileHeaderVisible,
    profileHeaderImageData: profileHeaderImageData,
  );
}
