import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/utils/simply_plural_urls.dart';

void main() {
  group('isRetiredSimplyPluralMediaUrl', () {
    test('recognizes Apparyllis hosts across supported URL forms', () {
      for (final url in [
        'https://serve.apparyllis.com/avatars/system/avatar',
        'HTTPS://SERVE.APPARYLLIS.COM/avatars/system/avatar',
        '//serve.apparyllis.com/avatars/system/avatar',
        'serve.apparyllis.com/avatars/system/avatar',
        'https://serve.apparyllis.com./avatars/system/avatar',
      ]) {
        expect(isRetiredSimplyPluralMediaUrl(url), isTrue, reason: url);
      }
    });

    test('does not classify lookalikes or third-party hosts as retired', () {
      for (final url in [
        'https://apparyllis.com.example.org/avatar.png',
        'https://notapparyllis.com/avatar.png',
        'https://cdn.example.com/apparyllis.com/avatar.png',
        'https://example.com/avatar.png',
        'not a URL',
      ]) {
        expect(isRetiredSimplyPluralMediaUrl(url), isFalse, reason: url);
      }
    });
  });
}
