class PairingSasDisplay {
  static const currentVersion = 2;
  static const wordCount = 5;

  const PairingSasDisplay._(this.words);

  final List<String> words;

  factory PairingSasDisplay.fromJson(Map<String, dynamic> json) {
    final version = _asInt(json['sas_version']);
    if (version != currentVersion) {
      throw FormatException('Unsupported pairing SAS version: $version');
    }

    final words = _parseWords(json['sas_word_list'] ?? json['sas_words']);
    if (words.length != wordCount) {
      throw FormatException(
        'Expected $wordCount pairing SAS words, got ${words.length}',
      );
    }

    return PairingSasDisplay._(List.unmodifiable(words));
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  static List<String> _parseWords(Object? raw) {
    if (raw is List) {
      return raw
          .map((word) {
            if (word is! String) {
              throw const FormatException('Pairing SAS words must be strings');
            }
            return word.trim();
          })
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
    }

    if (raw is String) {
      return raw
          .split(RegExp(r'[\s-]+'))
          .map((word) => word.trim())
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
    }

    throw const FormatException('Missing pairing SAS words');
  }
}
