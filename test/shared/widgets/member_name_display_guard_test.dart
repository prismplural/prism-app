// Guard: flags UI code that renders a member's name via raw `.name` instead of
// the system-wide display preference (`Member.effectiveName(preferDisplayName:)`).
//
// The `memberNameDisplay` setting lets a system show every member by their
// display name or their canonical name. For that to be consistent, every place
// that shows a member's name to the user must resolve it through
// `effectiveName` (sourced from `memberNamePreferDisplayProvider`). Raw
// `member.name` is correct ONLY for storage, sync, search-matching, sort keys,
// logging, and a few intentional canonical-name surfaces.
//
// This guard scans for the common *visible-render* shapes of a raw member name
// (Text(...), label:/title:/subtitle:/semanticLabel:/tooltip:/memberName:,
// string interpolation, and l10n calls). It also catches the member-resolution
// idiom `someMap[id].name` / `someById[id].name` (a name laundered through a
// `Map<id, Member>` lookup), which the render-shape patterns miss. A match
// fails the test unless the line is exempted with a trailing
// `// raw-name-ok: <reason>` comment.
//
// It is a heuristic, not a proof: it cannot catch a name laundered through an
// intermediate variable far from its render. But it catches the dominant
// "show member.name directly" mistake and forces a conscious decision on
// every new occurrence.
//
// Run from app/: flutter test test/shared/widgets/member_name_display_guard_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Variable names that denote a `Member` (or nullable `Member?`) in UI code.
const _receiver =
    r'(?:member|author|fronter|headmate|alter|part|voter|reactor|owner|target|'
    r'selectedMember|currentMember|authorMember|targetMember|displayMember|'
    r'ownerMember|profileMember|coFronter)';

/// Visible-render shapes. Each must contain a member receiver followed by
/// `.name` / `?.name`. Routed code says `effectiveName(...)` and never matches.
final _renderPatterns = <RegExp>[
  // Text(member.name ...) — \b anchors so we don't match e.g.
  // normalizeMemberSearchText(member.name) (a search key, not a render).
  RegExp('\\bText\\(\\s*$_receiver\\??\\.name\\b'),
  // label: member.name, title: author?.name, subtitle: ..., semanticLabel: ...
  // (Avatar `memberName:`/`authorName:` props are intentionally NOT scanned —
  // they drive avatar initials/screen-reader labels and are handled per-site.)
  RegExp(
    '(?:label|title|subtitle|semanticLabel)\\s*:\\s*$_receiver\\??\\.name\\b',
  ),
  // "...${member.name}..." string interpolation
  RegExp('\\\$\\{\\s*$_receiver\\??\\.name\\b'),
  // context.l10n.someLabel(member.name)
  RegExp('\\.l10n\\.\\w+\\(\\s*$_receiver\\??\\.name\\b'),
  // final name = member.name;  /  final memberName = author?.name ?? ...
  RegExp(
    '\\b(?:name|memberName|authorName|displayName|label|title)\\s*=\\s*'
    '$_receiver\\??\\.name\\b',
  ),
  // memberMap[id].name / participantMap[id]?.name / detailsById[id].name —
  // a member name laundered through a `Map<id, Member>` lookup. Anchored on a
  // variable whose name ends in `Map`/`ById` so it catches the member-resolution
  // idiom without flagging arbitrary list/group lookups like `groups[0].name`.
  RegExp(r'(?:Map|ById)\[[^\]]+\]\??\.name\b'),
];

/// Inline escape hatch: a line carrying this marker is intentionally canonical.
const _exemptMarker = 'raw-name-ok';

bool _skipFile(String path) =>
    path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

void main() {
  test(
    'UI renders member names via effectiveName, not raw .name',
    () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'Run from app/ directory');

      final violations = <String>[];

      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !_skipFile(f.path));

      for (final file in files) {
        final rel = file.path.startsWith('./')
            ? file.path.substring(2)
            : file.path;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('import ')) {
            continue;
          }
          // Already resolved, or deliberately canonical. The exemption marker
          // counts on the line itself or as a comment directly above it.
          if (line.contains('effectiveName')) continue;
          final prev = i > 0 ? lines[i - 1] : '';
          if (line.contains(_exemptMarker) || prev.contains(_exemptMarker)) {
            continue;
          }
          if (_renderPatterns.any((p) => p.hasMatch(line))) {
            violations.add('$rel:${i + 1}  ${trimmed.trim()}');
          }
        }
      }

      if (violations.isNotEmpty) {
        violations.sort();
        fail(
          'Found ${violations.length} UI site(s) rendering a member name via '
          'raw `.name` instead of '
          '`member.effectiveName(preferDisplayName: ...)`.\n\n'
          'Fix: read `memberNamePreferDisplayProvider` (once per Consumer '
          'build) and call `effectiveName`. If the canonical name is '
          'intentional here (sync, search, an external PluralKit object, an '
          'analytics axis, a frozen-at-send message), append a trailing '
          '`// $_exemptMarker: <reason>` comment to the line.\n\n'
          '${violations.join('\n')}',
        );
      }
    },
  );

  // `MemberChip` and `MemberCard` fall back to the canonical `member.name`
  // when `resolvedName` is omitted. That fallback is internal, so the `.name`
  // patterns above can't see it — a call that forgets `resolvedName` silently
  // ignores the display-name preference. Require it on every call.
  test(
    'MemberChip/MemberCard calls pass resolvedName',
    () {
      // `\b` so we match the real widget, not `_ResolvedMemberChip(` etc.
      final widgetCall = RegExp(r'\b(?:MemberChip|MemberCard)\(');
      final libDir = Directory('lib');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !_skipFile(f.path))
          // Skip the files that DEFINE these widgets.
          .where((f) =>
              !f.path.endsWith('member_chip.dart') &&
              !f.path.endsWith('member_card.dart'));

      final violations = <String>[];
      for (final file in files) {
        final rel = file.path.startsWith('./')
            ? file.path.substring(2)
            : file.path;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (!widgetCall.hasMatch(line)) continue;
          final prev = i > 0 ? lines[i - 1] : '';
          if (line.contains(_exemptMarker) || prev.contains(_exemptMarker)) {
            continue;
          }
          // Scan the call's argument window (to its closing paren, 25-line cap)
          // for `resolvedName`.
          var found = line.contains('resolvedName');
          for (var j = i + 1; !found && j < lines.length && j <= i + 25; j++) {
            if (lines[j].contains('resolvedName')) {
              found = true;
              break;
            }
            if (lines[j].trimLeft().startsWith(')')) break;
          }
          if (!found) {
            violations.add('$rel:${i + 1}  ${line.trimLeft()}');
          }
        }
      }

      if (violations.isNotEmpty) {
        violations.sort();
        fail(
          'Found ${violations.length} MemberChip/MemberCard call(s) without '
          '`resolvedName` — they fall back to the canonical `member.name`, '
          'ignoring the display-name preference. Pass '
          '`resolvedName: member.effectiveName(preferDisplayName: ...)` (or an '
          'already-resolved name). If canonical is intentional, add a '
          '`// $_exemptMarker: <reason>` comment.\n\n${violations.join('\n')}',
        );
      }
    },
  );
}
