import 'dart:convert';
import 'dart:typed_data';

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

class DataMarkdownImageRef {
  const DataMarkdownImageRef({
    required this.fullMatch,
    required this.altText,
    required this.mimeType,
    required this.base64Payload,
  });

  final String fullMatch;
  final String altText;
  final String mimeType;
  final String base64Payload;
}

class DataMarkdownImageImport {
  const DataMarkdownImageImport({
    required this.ref,
    required this.suggestedTag,
  });

  final DataMarkdownImageRef ref;
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
final _dataImagePattern = RegExp(
  r'!\[([^\]]*)\]\((data:(image/[A-Za-z0-9.+-]+);base64,([A-Za-z0-9+/=\r\n]+))\)',
);

bool hasStageableMarkdownImageRefs(String markdown) {
  return findRemoteMarkdownImageRefs(markdown).isNotEmpty ||
      findDataMarkdownImageRefs(markdown).isNotEmpty;
}

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

List<DataMarkdownImageRef> findDataMarkdownImageRefs(String markdown) {
  if (!markdown.contains('data:image')) return const [];

  final refs = <DataMarkdownImageRef>[];
  for (final match in _dataImagePattern.allMatches(markdown)) {
    refs.add(
      DataMarkdownImageRef(
        fullMatch: match.group(0)!,
        altText: match.group(1) ?? '',
        mimeType: match.group(3) ?? 'image',
        base64Payload: match.group(4) ?? '',
      ),
    );
  }
  return refs;
}

List<DataMarkdownImageImport> buildDataMarkdownImageImports(
  Iterable<DataMarkdownImageRef> refs, {
  Iterable<String> unavailableTags = const [],
}) {
  final usedTags = unavailableTags.where((tag) => tag.isNotEmpty).toSet();
  final seenMatches = <String>{};
  var index = 1;
  final imports = <DataMarkdownImageImport>[];

  for (final ref in refs) {
    if (!seenMatches.add(ref.fullMatch)) continue;

    final tag = _uniqueTag('embedded-image-${index++}', usedTags);
    usedTags.add(tag);
    imports.add(DataMarkdownImageImport(ref: ref, suggestedTag: tag));
  }
  return imports;
}

Uint8List decodeDataMarkdownImageRef(DataMarkdownImageRef ref) {
  final normalized = ref.base64Payload.replaceAll(RegExp(r'\s+'), '');
  return base64Decode(base64.normalize(normalized));
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

String rewriteDataMarkdownImageRefs(
  String markdown,
  Map<String, String> fullMatchToReplacement,
) {
  if (fullMatchToReplacement.isEmpty) return markdown;

  var result = markdown;
  for (final entry in fullMatchToReplacement.entries) {
    result = result.replaceAll(entry.key, entry.value);
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
