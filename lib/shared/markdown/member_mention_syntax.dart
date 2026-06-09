import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

const memberMentionPattern =
    r'@\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]';

final memberMentionRegex = RegExp(memberMentionPattern);

const memberMentionTag = 'member_mention';

String? memberMentionIdFromMatch(Match match) => match.group(1);

bool containsMemberMention(String content) =>
    memberMentionRegex.hasMatch(content);

String memberMentionDisplayName(String memberId, Map<String, Member>? members) {
  return members?[memberId]?.name ?? 'Unknown';
}

Color memberMentionColor(Member? member, ThemeData theme, {Color? fallback}) {
  if (member != null &&
      member.customColorEnabled &&
      member.customColorHex != null) {
    return AppColors.fromHex(member.customColorHex!);
  }
  return fallback ?? theme.colorScheme.primary;
}

String replaceMemberMentionsWithNames(
  String content,
  Map<String, String> nameMap,
) {
  return content.replaceAllMapped(memberMentionRegex, (match) {
    final id = memberMentionIdFromMatch(match)!;
    return '@${nameMap[id] ?? 'Unknown'}';
  });
}

class MemberMentionSyntax extends md.InlineSyntax {
  MemberMentionSyntax() : super(memberMentionPattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.empty(memberMentionTag);
    element.attributes['id'] = memberMentionIdFromMatch(match)!;
    parser.addNode(element);
    return true;
  }
}

class MemberMentionBuilder extends MarkdownElementBuilder {
  MemberMentionBuilder({
    required this.memberMap,
    required this.theme,
    this.onTapMember,
  });

  final Map<String, Member>? memberMap;
  final ThemeData theme;
  final ValueChanged<String>? onTapMember;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final id = element.attributes['id'];
    if (id == null) return null;

    final member = memberMap?[id];
    final display = '@${memberMentionDisplayName(id, memberMap)}';
    final color = memberMentionColor(member, theme);
    final merged = (parentStyle ?? const TextStyle()).copyWith(
      color: color,
      fontWeight: FontWeight.w600,
    );
    final tap = member == null || onTapMember == null
        ? null
        : (TapGestureRecognizer()..onTap = () => onTapMember!(id));
    return Text.rich(
      TextSpan(
        text: display,
        style: merged,
        recognizer: tap,
        semanticsLabel: display,
      ),
    );
  }
}

TextSpan buildMemberMentionTextSpan({
  required String memberId,
  required Map<String, Member>? memberMap,
  required ThemeData theme,
  required TextStyle baseStyle,
  Color? fallbackColor,
}) {
  final member = memberMap?[memberId];
  final color = memberMentionColor(member, theme, fallback: fallbackColor);
  final display = '@${memberMentionDisplayName(memberId, memberMap)}';
  return TextSpan(
    text: display,
    style: baseStyle.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
      backgroundColor: color.withValues(alpha: 0.16),
    ),
    semanticsLabel: display,
  );
}

class MemberMentionTrigger {
  const MemberMentionTrigger({required this.atIndex, required this.filter});

  final int atIndex;
  final String filter;
}

MemberMentionTrigger? detectMemberMentionTrigger(String text, int cursorPos) {
  if (cursorPos < 0 || cursorPos > text.length) return null;

  final before = text.substring(0, cursorPos);
  final atIndex = before.lastIndexOf('@');
  if (atIndex < 0) return null;

  if (atIndex > 0 &&
      before[atIndex - 1] != ' ' &&
      before[atIndex - 1] != '\n') {
    return null;
  }

  final partial = before.substring(atIndex + 1);
  if (partial.contains(' ') || partial.contains('\n')) return null;

  return MemberMentionTrigger(atIndex: atIndex, filter: partial);
}

class AtomicMemberMentionFormatter extends TextInputFormatter {
  const AtomicMemberMentionFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) {
      return snapMemberMentionSelectionOutOfToken(
        oldValue.text,
        newValue,
        previousSelection: oldValue.selection,
      );
    }

    final diff = _computeDiff(oldValue.text, newValue.text);
    if (diff == null) {
      return snapMemberMentionSelectionOutOfToken(
        newValue.text,
        newValue,
        previousSelection: oldValue.selection,
      );
    }

    final affectedMentions =
        _mentionsOverlapping(oldValue.text, diff.oldStart, diff.oldEnd)
            .where(
              (range) => !_rangeFullyCovered(range, diff.oldStart, diff.oldEnd),
            )
            .toList();

    if (affectedMentions.isEmpty) {
      return snapMemberMentionSelectionOutOfToken(
        newValue.text,
        newValue,
        previousSelection: oldValue.selection,
      );
    }

    final expandedStart = affectedMentions
        .map((range) => range.start)
        .fold(diff.oldStart, (a, b) => a < b ? a : b);
    final expandedEnd = affectedMentions
        .map((range) => range.end)
        .fold(diff.oldEnd, (a, b) => a > b ? a : b);
    final insertedText = newValue.text.substring(diff.newStart, diff.newEnd);
    final repairedText =
        oldValue.text.substring(0, expandedStart) +
        insertedText +
        oldValue.text.substring(expandedEnd);
    final cursorOffset = expandedStart + insertedText.length;

    return TextEditingValue(
      text: repairedText,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
  }

  List<_MemberMentionRange> _mentionsOverlapping(
    String text,
    int start,
    int end,
  ) {
    final ranges = <_MemberMentionRange>[];
    for (final match in memberMentionRegex.allMatches(text)) {
      if (start < match.end && end > match.start) {
        ranges.add(_MemberMentionRange(match.start, match.end));
      }
    }
    return ranges;
  }

  bool _rangeFullyCovered(_MemberMentionRange range, int start, int end) {
    return start <= range.start && end >= range.end;
  }

  _DiffRange? _computeDiff(String oldText, String newText) {
    if (oldText == newText) return null;

    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    var oldSuffix = oldText.length;
    var newSuffix = newText.length;
    while (oldSuffix > prefix &&
        newSuffix > prefix &&
        oldText.codeUnitAt(oldSuffix - 1) ==
            newText.codeUnitAt(newSuffix - 1)) {
      oldSuffix--;
      newSuffix--;
    }

    return _DiffRange(
      oldStart: prefix,
      oldEnd: oldSuffix,
      newStart: prefix,
      newEnd: newSuffix,
    );
  }
}

TextEditingValue snapMemberMentionSelectionOutOfToken(
  String text,
  TextEditingValue value, {
  TextSelection? previousSelection,
}) {
  final selection = value.selection;
  if (!selection.isValid) return value;

  final snapped = snapMemberMentionSelection(
    text,
    selection,
    previousSelection: previousSelection?.isValid == true
        ? previousSelection
        : null,
  );
  if (snapped == selection) return value;
  return value.copyWith(selection: snapped, composing: TextRange.empty);
}

TextSelection snapMemberMentionSelection(
  String text,
  TextSelection selection, {
  TextSelection? previousSelection,
}) {
  if (!selection.isValid) return selection;

  final baseRange = _mentionContaining(text, selection.baseOffset);
  final extentRange = _mentionContaining(text, selection.extentOffset);
  if (baseRange == null && extentRange == null) return selection;

  final snappedBase = _snapMentionOffset(
    baseRange,
    selection.baseOffset,
    previousSelection?.baseOffset,
  );
  final snappedExtent = _snapMentionOffset(
    extentRange,
    selection.extentOffset,
    previousSelection?.extentOffset,
  );
  return TextSelection(
    baseOffset: snappedBase,
    extentOffset: snappedExtent,
    affinity: selection.affinity,
    isDirectional: selection.isDirectional,
  );
}

int _snapMentionOffset(
  _MemberMentionRange? range,
  int offset,
  int? previousOffset,
) {
  if (range == null) return offset;
  if (previousOffset != null) {
    if (offset > previousOffset) return range.end;
    if (offset < previousOffset) return range.start;
  }

  final leftDistance = offset - range.start;
  final rightDistance = range.end - offset;
  return leftDistance < rightDistance ? range.start : range.end;
}

_MemberMentionRange? _mentionContaining(String text, int offset) {
  if (offset < 0 || offset > text.length) return null;
  for (final match in memberMentionRegex.allMatches(text)) {
    if (match.start < offset && offset < match.end) {
      return _MemberMentionRange(match.start, match.end);
    }
  }
  return null;
}

class _MemberMentionRange {
  const _MemberMentionRange(this.start, this.end);

  final int start;
  final int end;
}

class _DiffRange {
  const _DiffRange({
    required this.oldStart,
    required this.oldEnd,
    required this.newStart,
    required this.newEnd,
  });

  final int oldStart;
  final int oldEnd;
  final int newStart;
  final int newEnd;
}
