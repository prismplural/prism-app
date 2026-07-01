import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';

void main() {
  group('resolveOnboardingRedirect', () {
    Future<String?> resolve({
      required bool? hasCompleted,
      required bool isOnboarding,
      bool completedLocally = false,
      bool recovers = false,
      int memberCount = 0,
    }) {
      return resolveOnboardingRedirect(
        hasCompleted: hasCompleted,
        isOnboarding: isOnboarding,
        completedLocally: completedLocally,
        tryRecoverPaired: () async => recovers,
        getMemberCount: () async => memberCount,
      );
    }

    test('stays put while settings are still loading', () async {
      expect(
        await resolve(hasCompleted: null, isOnboarding: true),
        isNull,
      );
    });

    test('sends an unfinished device to onboarding', () async {
      expect(
        await resolve(hasCompleted: false, isOnboarding: false),
        AppRoutePaths.onboarding,
      );
    });

    test(
      'a locally-finished empty system is allowed into home (the lockout fix)',
      () async {
        expect(
          await resolve(
            hasCompleted: true,
            isOnboarding: true,
            completedLocally: true,
            memberCount: 0,
          ),
          AppRoutePaths.home,
        );
      },
    );

    test(
      'a synced-in device with no members stays on onboarding (Device B '
      'protection preserved)',
      () async {
        expect(
          await resolve(
            hasCompleted: true,
            isOnboarding: true,
            completedLocally: false,
            memberCount: 0,
          ),
          isNull,
        );
      },
    );

    test('a synced-in device with members lands on home', () async {
      expect(
        await resolve(
          hasCompleted: true,
          isOnboarding: true,
          completedLocally: false,
          memberCount: 3,
        ),
        AppRoutePaths.home,
      );
    });

    test('a completed device already off onboarding is left alone', () async {
      expect(
        await resolve(hasCompleted: true, isOnboarding: false),
        isNull,
      );
    });

    test('paired recovery on the onboarding route routes to home', () async {
      expect(
        await resolve(
          hasCompleted: false,
          isOnboarding: true,
          recovers: true,
        ),
        AppRoutePaths.home,
      );
    });

    test('paired recovery off the onboarding route stays put', () async {
      expect(
        await resolve(
          hasCompleted: false,
          isOnboarding: false,
          recovers: true,
        ),
        isNull,
      );
    });
  });
}
