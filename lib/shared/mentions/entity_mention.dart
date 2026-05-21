import 'package:flutter/services.dart';

enum EntityMentionType {
  member('member'),
  group('group'),
  note('note'),
  board('board'),
  conversation('conversation');

  const EntityMentionType(this.tokenName);

  final String tokenName;

  static EntityMentionType? fromTokenName(String value) {
    for (final type in EntityMentionType.values) {
      if (type.tokenName == value) return type;
    }
    return null;
  }
}

const legacyMemberMentionPattern =
    r'@\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]';

final legacyMemberMentionRegex = RegExp(legacyMemberMentionPattern);
final entityMentionTokenRegex = RegExp(r'@\[([a-z]+):([^\]\r\n]{1,128})\]');
final entityOrLegacyMentionRegex = RegExp(
  '$legacyMemberMentionPattern|@\\[([a-z]+):([^\\]\\r\\n]{1,128})\\]',
);

String serializeEntityMention(EntityMentionType type, String id) {
  if (!isValidEntityMentionId(id)) {
    throw ArgumentError.value(id, 'id', 'Invalid entity mention id.');
  }
  return '@[${type.tokenName}:$id]';
}

bool isValidEntityMentionId(String id) {
  if (id.isEmpty || id.length > 128) return false;
  if (id.trim() != id) return false;
  for (var i = 0; i < id.length; i++) {
    final unit = id.codeUnitAt(i);
    if (unit == 0x5d || unit < 0x20 || unit == 0x7f) return false;
  }
  return true;
}

class EntityMentionTarget {
  const EntityMentionTarget({
    required this.type,
    required this.id,
    this.isLegacyMember = false,
  });

  final EntityMentionType type;
  final String id;
  final bool isLegacyMember;

  String get token =>
      isLegacyMember ? '@[$id]' : serializeEntityMention(type, id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityMentionTarget &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          id == other.id &&
          isLegacyMember == other.isLegacyMember;

  @override
  int get hashCode => Object.hash(type, id, isLegacyMember);
}

class EntityMentionMatch {
  const EntityMentionMatch({
    required this.start,
    required this.end,
    required this.raw,
    required this.target,
  });

  final int start;
  final int end;
  final String raw;
  final EntityMentionTarget target;
}

List<EntityMentionMatch> extractEntityMentions(String text) {
  if (text.isEmpty || !text.contains('@[')) return const [];

  final ignoredRanges = _collectIgnoredMarkdownRanges(text);
  final matches = <EntityMentionMatch>[];
  for (final match in entityOrLegacyMentionRegex.allMatches(text)) {
    if (_rangeOverlapsAny(match.start, match.end, ignoredRanges)) continue;

    final legacyId = match.group(1);
    if (legacyId != null) {
      matches.add(
        EntityMentionMatch(
          start: match.start,
          end: match.end,
          raw: match.group(0)!,
          target: EntityMentionTarget(
            type: EntityMentionType.member,
            id: legacyId,
            isLegacyMember: true,
          ),
        ),
      );
      continue;
    }

    final type = EntityMentionType.fromTokenName(match.group(2)!);
    final id = match.group(3)!;
    if (type == null || !isValidEntityMentionId(id)) continue;

    matches.add(
      EntityMentionMatch(
        start: match.start,
        end: match.end,
        raw: match.group(0)!,
        target: EntityMentionTarget(type: type, id: id),
      ),
    );
  }
  return matches;
}

List<EntityMentionTarget> extractEntityMentionTargets(String text) =>
    extractEntityMentions(text).map((match) => match.target).toList();

class EntityMentionTrigger {
  const EntityMentionTrigger({required this.atIndex, required this.filter});

  final int atIndex;
  final String filter;
}

EntityMentionTrigger? detectEntityMentionTrigger(String text, int cursorPos) {
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
  if (partial.contains(' ') ||
      partial.contains('\n') ||
      partial.contains('[') ||
      partial.contains(']')) {
    return null;
  }
  return EntityMentionTrigger(atIndex: atIndex, filter: partial);
}

class AtomicEntityMentionFormatter extends TextInputFormatter {
  const AtomicEntityMentionFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) {
      return _snapSelectionOutOfMention(oldValue.text, newValue);
    }

    final diff = _computeDiff(oldValue.text, newValue.text);
    if (diff == null) {
      return _snapSelectionOutOfMention(newValue.text, newValue);
    }

    final affectedMentions =
        _mentionsOverlapping(oldValue.text, diff.oldStart, diff.oldEnd)
            .where(
              (range) => !_rangeFullyCovered(range, diff.oldStart, diff.oldEnd),
            )
            .toList();

    if (affectedMentions.isEmpty) {
      return _snapSelectionOutOfMention(newValue.text, newValue);
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

  TextEditingValue _snapSelectionOutOfMention(
    String text,
    TextEditingValue value,
  ) {
    final selection = value.selection;
    if (!selection.isValid) return value;

    final baseRange = _mentionContaining(text, selection.baseOffset);
    final extentRange = _mentionContaining(text, selection.extentOffset);
    if (baseRange == null && extentRange == null) return value;

    return value.copyWith(
      selection: TextSelection(
        baseOffset: _snapOffset(baseRange, selection.baseOffset),
        extentOffset: _snapOffset(extentRange, selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }

  int _snapOffset(_MentionRange? range, int offset) {
    if (range == null) return offset;
    final leftDistance = offset - range.start;
    final rightDistance = range.end - offset;
    return leftDistance < rightDistance ? range.start : range.end;
  }

  _MentionRange? _mentionContaining(String text, int offset) {
    if (offset < 0 || offset > text.length) return null;
    for (final match in extractEntityMentions(text)) {
      if (match.start < offset && offset < match.end) {
        return _MentionRange(match.start, match.end);
      }
    }
    return null;
  }

  List<_MentionRange> _mentionsOverlapping(String text, int start, int end) {
    final ranges = <_MentionRange>[];
    for (final match in extractEntityMentions(text)) {
      if (start < match.end && end > match.start) {
        ranges.add(_MentionRange(match.start, match.end));
      }
    }
    return ranges;
  }

  bool _rangeFullyCovered(_MentionRange range, int start, int end) {
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

List<_MentionRange> _collectIgnoredMarkdownRanges(String text) {
  final ranges = <_MentionRange>[];
  _collectFencedCodeRanges(text, ranges);
  _collectInlineCodeRanges(text, ranges);
  _collectMarkdownLinkDestinationRanges(text, ranges);
  ranges.sort((a, b) => a.start.compareTo(b.start));
  return ranges;
}

void _collectFencedCodeRanges(String text, List<_MentionRange> ranges) {
  var offset = 0;
  while (offset < text.length) {
    final lineEnd = text.indexOf('\n', offset);
    final end = lineEnd == -1 ? text.length : lineEnd;
    final line = text.substring(offset, end);
    final marker = _fenceMarker(line);
    if (marker == null) {
      offset = lineEnd == -1 ? text.length : lineEnd + 1;
      continue;
    }

    final fenceStart = offset;
    offset = lineEnd == -1 ? text.length : lineEnd + 1;
    while (offset < text.length) {
      final closeLineEnd = text.indexOf('\n', offset);
      final closeEnd = closeLineEnd == -1 ? text.length : closeLineEnd;
      final closeLine = text.substring(offset, closeEnd);
      final closeMarker = _fenceMarker(closeLine);
      if (closeMarker != null &&
          closeMarker.character == marker.character &&
          closeMarker.length >= marker.length) {
        ranges.add(
          _MentionRange(fenceStart, closeLineEnd == -1 ? closeEnd : closeEnd),
        );
        offset = closeLineEnd == -1 ? text.length : closeLineEnd + 1;
        break;
      }
      offset = closeLineEnd == -1 ? text.length : closeLineEnd + 1;
    }
    if (offset >= text.length) {
      ranges.add(_MentionRange(fenceStart, text.length));
    }
  }
}

_FenceMarker? _fenceMarker(String line) {
  var index = 0;
  while (index < line.length && index < 3 && line.codeUnitAt(index) == 0x20) {
    index++;
  }
  if (index >= line.length) return null;
  final unit = line.codeUnitAt(index);
  if (unit != 0x60 && unit != 0x7e) return null;

  var end = index;
  while (end < line.length && line.codeUnitAt(end) == unit) {
    end++;
  }
  if (end - index < 3) return null;
  return _FenceMarker(String.fromCharCode(unit), end - index);
}

void _collectInlineCodeRanges(String text, List<_MentionRange> ranges) {
  var i = 0;
  while (i < text.length) {
    if (_rangeOverlapsAny(i, i + 1, ranges) || text.codeUnitAt(i) != 0x60) {
      i++;
      continue;
    }

    var tickCount = 1;
    while (i + tickCount < text.length &&
        text.codeUnitAt(i + tickCount) == 0x60) {
      tickCount++;
    }

    var j = i + tickCount;
    while (j < text.length) {
      if (text.codeUnitAt(j) != 0x60) {
        j++;
        continue;
      }
      var closeCount = 1;
      while (j + closeCount < text.length &&
          text.codeUnitAt(j + closeCount) == 0x60) {
        closeCount++;
      }
      if (closeCount == tickCount) {
        ranges.add(_MentionRange(i, j + closeCount));
        i = j + closeCount;
        break;
      }
      j += closeCount;
    }
    if (j >= text.length) i += tickCount;
  }
}

void _collectMarkdownLinkDestinationRanges(
  String text,
  List<_MentionRange> ranges,
) {
  var i = 0;
  while (i < text.length) {
    final openBracket = text.indexOf('[', i);
    if (openBracket == -1) return;
    final closeBracket = text.indexOf(']', openBracket + 1);
    if (closeBracket == -1 ||
        closeBracket + 1 >= text.length ||
        text.codeUnitAt(closeBracket + 1) != 0x28) {
      i = openBracket + 1;
      continue;
    }

    var depth = 1;
    var j = closeBracket + 2;
    while (j < text.length && depth > 0) {
      final unit = text.codeUnitAt(j);
      if (unit == 0x5c) {
        j += 2;
        continue;
      }
      if (unit == 0x28) depth++;
      if (unit == 0x29) depth--;
      j++;
    }
    if (depth == 0) {
      ranges.add(_MentionRange(closeBracket + 2, j - 1));
      i = j;
    } else {
      i = openBracket + 1;
    }
  }
}

bool _rangeOverlapsAny(int start, int end, List<_MentionRange> ranges) {
  for (final range in ranges) {
    if (start < range.end && end > range.start) return true;
  }
  return false;
}

class _FenceMarker {
  const _FenceMarker(this.character, this.length);

  final String character;
  final int length;
}

class _MentionRange {
  const _MentionRange(this.start, this.end);

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
