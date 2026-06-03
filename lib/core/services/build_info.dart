/// Build-time metadata injected via `--dart-define` flags.
///
/// Populated by `build.sh`, which wraps `flutter run` and `flutter build` with
/// the current git state, pubspec version, and build timestamp. When running
/// `flutter` directly (e.g. from an IDE) the `--dart-define` values are absent
/// and the defaults below are used.
///
/// Surfaced in the debug screen so we can tell which revision a given binary
/// came from when users report bugs.
class BuildInfo {
  const BuildInfo._();

  /// App version from `pubspec.yaml`, or `unknown` when unset.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'unknown',
  );

  /// `User-Agent` for every outbound HTTP request the app makes directly, so
  /// image hosts that allowlist known tools (as PluralKit and Simply Plural do)
  /// will serve Prism. The `PrismPlural` token stays constant across releases so
  /// a host can allowlist it; the contact URL identifies the client in their
  /// logs. `dev` when [appVersion] is unset (builds not wrapped by `build.sh`).
  static const String userAgent =
      'PrismPlural/${appVersion == 'unknown' ? 'dev' : appVersion} '
      '(+https://prismplural.com/about)';

  /// Short git commit hash, or `dev` when the build was not wrapped by
  /// `build.sh`.
  static const String gitRev = String.fromEnvironment(
    'GIT_REV',
    defaultValue: 'dev',
  );

  /// Output of `git describe --always --dirty`. A `-dirty` suffix means the
  /// working tree had uncommitted changes at build time — useful for
  /// recognizing "I built this locally and forgot to commit" situations.
  static const String gitDescribe = String.fromEnvironment(
    'GIT_DESCRIBE',
    defaultValue: 'dev',
  );

  /// Git branch name at build time, or `dev` when unset.
  static const String gitBranch = String.fromEnvironment(
    'GIT_BRANCH',
    defaultValue: 'dev',
  );

  /// ISO-8601 UTC build timestamp (e.g. `2026-04-11T14:23:45Z`), or `unknown`
  /// when unset.
  static const String builtAt = String.fromEnvironment(
    'BUILT_AT',
    defaultValue: 'unknown',
  );

  /// True if the build was produced from a dirty working tree.
  static bool get isDirty => gitDescribe.endsWith('-dirty');

  /// True if the build was not wrapped by `build.sh` (all fields default).
  static bool get isLocalDev => gitDescribe == 'dev';

  /// Optional beta relay registration token baked into the binary at build
  /// time. Used to pre-fill the registration token field during sync setup
  /// so TestFlight/beta testers don't have to type it by hand. Empty when
  /// unset — the token itself is never committed; it's injected via
  /// `--dart-define=PRISM_BETA_REGISTRATION_TOKEN=…` from a build wrapper
  /// that reads the value from an environment file outside this repo.
  static const String betaRegistrationToken = String.fromEnvironment(
    'PRISM_BETA_REGISTRATION_TOKEN',
  );
}
