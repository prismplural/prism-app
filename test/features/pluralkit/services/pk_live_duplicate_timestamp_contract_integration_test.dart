/// Live PluralKit contract test for duplicate switch timestamps.
///
/// Excluded from CI. Run manually with a dedicated PluralKit test account:
///
///   PK_TEST_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_live_duplicate_timestamp_contract_integration_test.dart
///
/// The test creates one temporary member, creates a switch at an explicit
/// timestamp, then verifies that PluralKit rejects a second switch at the exact
/// same timestamp with the documented duplicate-timestamp error contract.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:http/io_client.dart' as http_io;
// Use the pure Dart test package so Flutter's widget-test HTTP override does
// not intercept live PluralKit requests.
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

String? get _tokenOrNull {
  for (final name in const ['PK_TEST_TOKEN', 'PK_TOKEN']) {
    final value = Platform.environment[name]?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String get _token => _tokenOrNull!;

bool get _skipAll => _tokenOrNull == null;

String get _skipReason =>
    'Set PK_TEST_TOKEN or PK_TOKEN to run the live PluralKit contract test.';

final String _prefix = _buildPrefix();

String _buildPrefix() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random.secure().nextInt(0x7fffffff).toRadixString(36);
  return 'prism-dupe-ts-it-$ts-$rand-';
}

void main() {
  group(
    'PluralKit duplicate switch timestamp contract - live API',
    () {
      late PluralKitClient client;
      final createdSwitchIds = <String>[];
      final createdMemberIds = <String>[];

      setUp(() {
        client = PluralKitClient(token: _token, httpClient: http_io.IOClient());
      });

      tearDown(() async {
        for (final switchId in createdSwitchIds.toList().reversed) {
          try {
            await client.deleteSwitch(switchId);
            createdSwitchIds.remove(switchId);
          } catch (_) {
            // Best-effort cleanup.
          }
        }

        for (final memberId in createdMemberIds.toList().reversed) {
          try {
            await client.deleteMember(memberId);
            createdMemberIds.remove(memberId);
          } catch (_) {
            // Best-effort cleanup.
          }
        }

        try {
          final allMembers = await client.getMembers();
          for (final member in allMembers) {
            if (member.name.startsWith(_prefix)) {
              try {
                await client.deleteMember(member.id);
              } catch (_) {
                // Best-effort cleanup.
              }
            }
          }
        } catch (_) {
          // Best-effort cleanup.
        }

        client.dispose();
      });

      test(
        'rejects a second switch at the exact same timestamp',
        () async {
          final member = await client.createMember({
            'name': '${_prefix}member',
          });
          createdMemberIds.add(member.id);

          final timestamp = DateTime.now().toUtc().subtract(
            const Duration(days: 180),
          );
          final firstSwitch = await client.createSwitch([
            member.id,
          ], timestamp: timestamp);
          createdSwitchIds.add(firstSwitch.id);

          late final PluralKitApiError rejection;
          try {
            final unexpectedSwitch = await client.createSwitch(
              const [],
              timestamp: timestamp,
            );
            createdSwitchIds.add(unexpectedSwitch.id);
            fail('PluralKit unexpectedly accepted a duplicate timestamp.');
          } on PluralKitApiError catch (error) {
            rejection = error;
          }

          expect(rejection.statusCode, 400);

          final decoded = jsonDecode(rejection.message);
          expect(decoded, isA<Map<String, dynamic>>());
          final body = decoded as Map<String, dynamic>;

          expect(body['code'], 40005);
          expect(
            body['message'],
            isA<String>().having(
              (message) => message.toLowerCase(),
              'lowercase message',
              allOf(
                contains('switch'),
                contains('timestamp'),
                contains('already exists'),
              ),
            ),
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    skip: _skipAll ? _skipReason : false,
  );
}
