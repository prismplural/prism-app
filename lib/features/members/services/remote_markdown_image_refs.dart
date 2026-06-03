import 'package:prism_plurality/features/members/services/bio_image_processor.dart';

class RemoteMarkdownImageRef {
  const RemoteMarkdownImageRef({
    required this.fullMatch,
    required this.altText,
    required this.url,
    required this.fragment,
  });

  final String fullMatch;
  final String altText;
  final String url;
  final String fragment;
}

class RemoteMarkdownImageImport {
  const RemoteMarkdownImageImport({
    required this.url,
    required this.suggestedTag,
  });

  final String url;
  final String suggestedTag;
}

class RemoteMarkdownImageTagChoiceValidation {
  const RemoteMarkdownImageTagChoiceValidation({
    required this.normalizedTags,
    this.errorMessage,
  });

  final Map<String, String> normalizedTags;
  final String? errorMessage;

  bool get isValid => errorMessage == null;
}

final _remoteImagePattern = RegExp(r'!\[([^\]]*)\]\((https://[^)\s]+)\)');

List<RemoteMarkdownImageRef> findRemoteMarkdownImageRefs(String markdown) {
  if (!markdown.contains('http')) return const [];

  final refs = <RemoteMarkdownImageRef>[];
  for (final match in _remoteImagePattern.allMatches(markdown)) {
    final fullUrl = match.group(2);
    if (fullUrl == null) continue;

    final hashIdx = fullUrl.indexOf('#');
    final url = hashIdx >= 0 ? fullUrl.substring(0, hashIdx) : fullUrl;
    final fragment = hashIdx >= 0 ? fullUrl.substring(hashIdx) : '';
    refs.add(
      RemoteMarkdownImageRef(
        fullMatch: match.group(0)!,
        altText: match.group(1) ?? '',
        url: url,
        fragment: fragment,
      ),
    );
  }

  return refs;
}

List<RemoteMarkdownImageImport> buildRemoteMarkdownImageImports(
  Iterable<RemoteMarkdownImageRef> refs, {
  Iterable<String> unavailableTags = const [],
}) {
  final usedTags = unavailableTags.where((tag) => tag.isNotEmpty).toSet();
  final imports = <RemoteMarkdownImageImport>[];
  final seenUrls = <String>{};

  for (final ref in refs) {
    if (!seenUrls.add(ref.url)) continue;

    final base = suggestedRemoteImageTag(ref.url);
    final tag = _uniqueTag(base, usedTags);
    usedTags.add(tag);
    imports.add(RemoteMarkdownImageImport(url: ref.url, suggestedTag: tag));
  }

  return imports;
}

String rewriteRemoteMarkdownImageRefs(
  String markdown,
  Map<String, String> urlToTag,
) {
  if (urlToTag.isEmpty) return markdown;

  final refs = findRemoteMarkdownImageRefs(markdown);
  var result = markdown;
  for (final ref in refs) {
    final tag = urlToTag[ref.url];
    if (tag == null || tag.isEmpty) continue;
    result = result.replaceFirst(
      ref.fullMatch,
      '![${ref.altText}]($tag${ref.fragment})',
    );
  }
  return result;
}

String suggestedRemoteImageTag(String url) {
  String basename = '';
  try {
    final uri = Uri.parse(url);
    basename = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    basename = Uri.decodeComponent(basename);
  } catch (_) {}

  final dot = basename.lastIndexOf('.');
  if (dot > 0) basename = basename.substring(0, dot);

  final normalized = BioImageProcessor.normalizeTag(basename);
  return normalized.isEmpty ? 'image' : normalized;
}

String _uniqueTag(String base, Set<String> usedTags) {
  if (!usedTags.contains(base)) return base;
  for (var i = 2; ; i++) {
    final candidate = '$base-$i';
    if (!usedTags.contains(candidate)) return candidate;
  }
}

RemoteMarkdownImageTagChoiceValidation validateRemoteMarkdownImageTagChoices(
  Map<String, String> choices, {
  Iterable<String> unavailableTags = const [],
}) {
  final unavailable = unavailableTags.where((tag) => tag.isNotEmpty).toSet();
  final seen = <String>{};
  final normalized = <String, String>{};

  for (final entry in choices.entries) {
    final tag = BioImageProcessor.normalizeTag(entry.value);
    if (tag.isEmpty) {
      return const RemoteMarkdownImageTagChoiceValidation(
        normalizedTags: {},
        errorMessage: 'Tag has no usable characters',
      );
    }
    if (unavailable.contains(tag) || !seen.add(tag)) {
      return RemoteMarkdownImageTagChoiceValidation(
        normalizedTags: const {},
        errorMessage: 'Tag "$tag" is already in use',
      );
    }
    normalized[entry.key] = tag;
  }

  return RemoteMarkdownImageTagChoiceValidation(normalizedTags: normalized);
}
