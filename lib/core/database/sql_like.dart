const sqlLikeEscapeChar = r'\';

String escapedSqlLikeContainsPattern(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}
