/// Pure usage-scan logic for the Media library screen: given the set of library
/// tags and the text blobs that may reference them, compute which surfaces use
/// each tag — with enough info to render a tappable "jump to it" target.
///
/// Kept widget-free and dependency-free so it can be unit-tested directly.
/// Runs on the calling isolate — the scan is O(total referencing text) and the
/// inputs are bounded (bios/notes/groups/custom fields, plus chat messages
/// pre-filtered to those containing `![`), so it's cheap enough to run inline.
library;

/// What kind of surface references a tag (drives the icon + grouping in the
/// usage view).
enum TagUsageKind { bio, note, group, customField, chat }

/// A text blob to scan, tagged with the label + navigation target to record if
/// it references a library tag.
class TagUsageSource {
  const TagUsageSource({
    required this.text,
    required this.kind,
    required this.label,
    required this.route,
  });

  final String text;
  final TagUsageKind kind;

  /// Human-readable description of where this is (e.g. "Alex's bio").
  final String label;

  /// go_router location to navigate to when the usage is tapped.
  final String route;
}

/// A concrete place a tag is used, tappable to navigate via [route].
class TagUsageRef {
  const TagUsageRef({
    required this.kind,
    required this.label,
    required this.route,
  });

  final TagUsageKind kind;
  final String label;
  final String route;
}

final _imageRefPattern = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');

/// Extract the bare image refs (tag or URL, with any `#WxH`/`#50%` sizing
/// fragment stripped) from [text].
Iterable<String> imageRefsIn(String text) sync* {
  for (final m in _imageRefPattern.allMatches(text)) {
    final raw = m.group(1)!;
    final hash = raw.indexOf('#');
    yield hash >= 0 ? raw.substring(0, hash) : raw;
  }
}

/// Builds the regex that matches `![alt](oldTag)` and `![alt](oldTag#frag)`
/// image refs for a specific [oldTag]. The trailing `(#[^)]*)?\)` requires
/// oldTag to be immediately followed by `#` or `)`, so a longer tag that merely
/// has oldTag as a prefix (e.g. `flagpole` for oldTag `flag`) does NOT match.
RegExp _renamePattern(String oldTag) => RegExp(
      r'!\[([^\]]*)\]\(' + RegExp.escape(oldTag) + r'(#[^)]*)?\)',
    );

/// Whether [text] contains at least one `![…](oldTag)` / `![…](oldTag#frag)`
/// image ref. Cheap guard so callers can skip a write when nothing changes.
bool textReferencesTag(String text, String oldTag) {
  if (!text.contains('![')) return false;
  return _renamePattern(oldTag).hasMatch(text);
}

/// Rewrites every `![alt](oldTag)` / `![alt](oldTag#fragment)` image ref in
/// [text] to point at [newTag], preserving the alt text and any `#WxH` / `#50%`
/// sizing fragment. Refs to other tags (including ones that have [oldTag] as a
/// prefix) are left untouched. Returns [text] unchanged when there's nothing to
/// rewrite.
String rewriteImageTag(String text, String oldTag, String newTag) {
  if (!text.contains('![')) return text;
  return text.replaceAllMapped(
    _renamePattern(oldTag),
    (m) => '![${m.group(1)!}]($newTag${m.group(2) ?? ''})',
  );
}

/// Returns `tag -> list of places it's used`, with an entry for every tag in
/// [tags] (empty list = unused). A source that references the same tag more
/// than once is credited only once (one card per surface).
Map<String, List<TagUsageRef>> scanTagUsage({
  required Set<String> tags,
  required List<TagUsageSource> sources,
}) {
  final usage = <String, List<TagUsageRef>>{
    for (final t in tags) t: <TagUsageRef>[],
  };
  if (tags.isEmpty) return usage;

  for (final src in sources) {
    if (!src.text.contains('![')) continue;
    final creditedHere = <String>{};
    for (final ref in imageRefsIn(src.text)) {
      if (tags.contains(ref) && creditedHere.add(ref)) {
        usage[ref]!.add(TagUsageRef(
          kind: src.kind,
          label: src.label,
          route: src.route,
        ));
      }
    }
  }

  return usage;
}
