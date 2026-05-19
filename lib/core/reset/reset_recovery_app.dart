import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/reset/full_reset_service.dart';
import 'package:prism_plurality/core/services/secure_storage_diagnostic.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

enum ResetRecoveryScreenMode {
  restartRequired,
  androidClearing,
  freshInstallAnomaly,
  sentinelRestored,
  keychainUnreadable,
}

/// Hook for tests to substitute the diagnostic share/save step.
///
/// Returns `true` when the diagnostic was handed off successfully (so the UI
/// can show a brief confirmation), `false` on cancel or failure.
typedef DiagnosticReportShareHandler =
    Future<bool> Function(String jsonPayload);

/// Hook for tests to substitute the "Re-pair from another device" hint check.
typedef SyncHistoryHintReader = Future<bool> Function();

/// Hook for tests to substitute the platform exit. Production calls
/// [SystemNavigator.pop], which on iOS is a no-op (Apple HIG: apps don't
/// exit themselves); the user is left on the "please restart" screen.
typedef AppExitHandler = Future<void> Function();

class ResetRecoveryApp extends StatelessWidget {
  const ResetRecoveryApp({
    super.key,
    required this.mode,
    this.service,
    this.diagnostic,
    this.shareDiagnostic,
    this.syncHistoryHintReader,
    this.appExit,
  });

  final ResetRecoveryScreenMode mode;
  final FullResetService? service;

  /// Secure-storage diagnostic surfaced by the §6 boot probe. Only meaningful
  /// for [ResetRecoveryScreenMode.keychainUnreadable].
  final SecureStorageDiagnostic? diagnostic;

  /// Test hook for the "Save diagnostic report" share action.
  final DiagnosticReportShareHandler? shareDiagnostic;

  /// Test hook for the "Re-pair from another device" gating check.
  final SyncHistoryHintReader? syncHistoryHintReader;

  /// Test hook for the platform "exit" action ("Restart and unlock and try
  /// again" primary button).
  final AppExitHandler? appExit;

  @override
  Widget build(BuildContext context) {
    // Wrap in a ProviderScope so [ResetRecoveryScreen]'s
    // ConsumerState can resolve [bootSecureStorageDiagnosticProvider].
    // The diagnostic passed via [diagnostic] is also threaded through
    // the provider so child widgets get a consistent view.
    return ProviderScope(
      overrides: [
        if (diagnostic != null)
          bootSecureStorageDiagnosticProvider.overrideWithValue(diagnostic),
      ],
      child: MaterialApp(
        title: 'Prism',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9070A0)),
          useMaterial3: true,
        ),
        home: ResetRecoveryScreen(
          mode: mode,
          service: service,
          diagnostic: diagnostic,
          shareDiagnostic: shareDiagnostic,
          syncHistoryHintReader: syncHistoryHintReader,
          appExit: appExit,
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class ResetRecoveryScreen extends StatefulWidget {
  const ResetRecoveryScreen({
    super.key,
    required this.mode,
    this.service,
    this.diagnostic,
    this.shareDiagnostic,
    this.syncHistoryHintReader,
    this.appExit,
  });

  final ResetRecoveryScreenMode mode;
  final FullResetService? service;
  final SecureStorageDiagnostic? diagnostic;
  final DiagnosticReportShareHandler? shareDiagnostic;
  final SyncHistoryHintReader? syncHistoryHintReader;
  final AppExitHandler? appExit;

  @override
  State<ResetRecoveryScreen> createState() => _ResetRecoveryScreenState();
}

class _ResetRecoveryScreenState extends State<ResetRecoveryScreen> {
  late ResetRecoveryScreenMode _mode = widget.mode;
  bool _busy = false;
  bool? _canContinueWithExistingData;

  /// Resolved asynchronously for [ResetRecoveryScreenMode.keychainUnreadable].
  /// Null while loading; true if any `prism_sync.*` SharedPref hint exists OR
  /// the `kPrismHadSyncSetup` marker was ever set.
  bool? _hasSyncHistoryHint;

  String? _error;
  String? _notice;

  FullResetService get _service => widget.service ?? FullResetService();

  @override
  void initState() {
    super.initState();
    if (_mode == ResetRecoveryScreenMode.freshInstallAnomaly) {
      _loadContinueAvailability();
    }
    if (_mode == ResetRecoveryScreenMode.keychainUnreadable) {
      _loadSyncHistoryHint();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAnomaly = _mode == ResetRecoveryScreenMode.freshInstallAnomaly;
    final isKeychainUnreadable =
        _mode == ResetRecoveryScreenMode.keychainUnreadable;
    final headerIcon = switch (_mode) {
      ResetRecoveryScreenMode.freshInstallAnomaly =>
        Icons.warning_amber_rounded,
      ResetRecoveryScreenMode.keychainUnreadable => Icons.lock_outline,
      _ => Icons.check_circle_outline,
    };
    final headerIconColor =
        (isAnomaly || isKeychainUnreadable)
            ? colorScheme.error
            : colorScheme.primary;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(headerIcon, size: 48, color: headerIconColor),
                  const SizedBox(height: 20),
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _notice!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.primary),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (isAnomaly)
                    ..._buildFreshInstallAnomalyActions(colorScheme)
                  else if (isKeychainUnreadable)
                    ..._buildKeychainUnreadableActions(colorScheme)
                  else
                    PrismButton(
                      label: _mode == ResetRecoveryScreenMode.androidClearing
                          ? 'Clearing...'
                          : _busy
                          ? 'Working...'
                          : 'Close and reopen Prism',
                      onPressed: () {},
                      enabled: false,
                      tone: PrismButtonTone.filled,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFreshInstallAnomalyActions(ColorScheme colorScheme) {
    return [
      if (_canContinueWithExistingData == true) ...[
        PrismButton(
          label: 'Continue with existing data',
          onPressed: _restoreSentinel,
          enabled: !_busy,
          tone: PrismButtonTone.filled,
        ),
        const SizedBox(height: 8),
      ] else if (_canContinueWithExistingData == null) ...[
        PrismButton(
          label: 'Checking existing data...',
          onPressed: () {},
          enabled: false,
          tone: PrismButtonTone.filled,
        ),
        const SizedBox(height: 8),
      ] else ...[
        Text(
          'Existing local data cannot be opened safely. Erase local data to start fresh.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
      ],
      PrismButton(
        label: 'Erase local data',
        onPressed: _eraseLocalData,
        enabled: !_busy,
        tone: PrismButtonTone.outlined,
      ),
    ];
  }

  List<Widget> _buildKeychainUnreadableActions(ColorScheme colorScheme) {
    final showRepair = _hasSyncHistoryHint == true;
    return [
      PrismButton(
        label: 'Restart and unlock once and try again',
        onPressed: _restartAndTryAgain,
        enabled: !_busy,
        tone: PrismButtonTone.filled,
      ),
      if (showRepair) ...[
        const SizedBox(height: 8),
        PrismButton(
          label: 'Re-pair from another device',
          onPressed: _repairFromAnotherDevice,
          enabled: !_busy,
          tone: PrismButtonTone.outlined,
        ),
      ],
      const SizedBox(height: 8),
      PrismButton(
        label: 'Reset local data',
        onPressed: _confirmAndResetLocalData,
        enabled: !_busy,
        tone: PrismButtonTone.destructive,
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: _busy ? null : _saveDiagnosticReport,
        child: Text(
          'Save diagnostic report',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
    ];
  }

  String get _title => switch (_mode) {
    ResetRecoveryScreenMode.restartRequired => 'Reset complete',
    ResetRecoveryScreenMode.androidClearing => 'Reset in progress',
    ResetRecoveryScreenMode.freshInstallAnomaly => 'Prism found existing data',
    ResetRecoveryScreenMode.sentinelRestored => 'Ready to continue',
    ResetRecoveryScreenMode.keychainUnreadable =>
      'Local data cannot be unlocked',
  };

  String get _message => switch (_mode) {
    ResetRecoveryScreenMode.restartRequired =>
      'Close Prism completely, then reopen it to start fresh.',
    ResetRecoveryScreenMode.androidClearing =>
      'Android is clearing Prism data. The app may close automatically.',
    ResetRecoveryScreenMode.freshInstallAnomaly =>
      'Prism found local data but the fresh-install marker is missing. You can keep this install or erase local data.',
    ResetRecoveryScreenMode.sentinelRestored =>
      'Close and reopen Prism to continue with the existing local data.',
    ResetRecoveryScreenMode.keychainUnreadable =>
      "Prism's encryption keys for this device are unreadable. This usually "
          'happens after an OS update or interrupted app update. Your data is '
          'still here, but Prism cannot decrypt it on this device.',
  };

  Future<void> _loadContinueAvailability() async {
    final canContinue = await _service
        .canContinueWithExistingDataAfterAnomaly();
    if (mounted) {
      setState(() => _canContinueWithExistingData = canContinue);
    }
  }

  Future<void> _loadSyncHistoryHint() async {
    final reader = widget.syncHistoryHintReader ?? _defaultSyncHistoryHint;
    bool hint;
    try {
      hint = await reader();
    } catch (_) {
      hint = false;
    }
    if (mounted) {
      setState(() => _hasSyncHistoryHint = hint);
    }
  }

  Future<void> _restoreSentinel() async {
    if (_busy) return;
    await _run(() async {
      final canContinue = await _service
          .canContinueWithExistingDataAfterAnomaly();
      if (!canContinue) {
        if (mounted) {
          setState(() => _canContinueWithExistingData = false);
        }
        throw StateError(
          'Existing local data cannot be opened safely. Erase local data to start fresh.',
        );
      }
      await _service.restoreInstallSentinelAfterAnomaly();
      if (mounted) {
        setState(() => _mode = ResetRecoveryScreenMode.sentinelRestored);
      }
    });
  }

  Future<void> _eraseLocalData() async {
    if (_busy) return;
    await _run(() async {
      if (Platform.isAndroid) {
        await _service.startAndroidClearApplicationData();
        if (mounted) {
          setState(() => _mode = ResetRecoveryScreenMode.androidClearing);
        }
      } else {
        await _service.wipeLocalData();
        if (mounted) {
          setState(() => _mode = ResetRecoveryScreenMode.restartRequired);
        }
      }
    });
  }

  Future<void> _restartAndTryAgain() async {
    if (_busy) return;
    final exit = widget.appExit ?? SystemNavigator.pop;
    await _run(() async {
      await exit();
      // On iOS SystemNavigator.pop is a no-op (HIG); leave a visible hint.
      if (mounted) {
        setState(
          () => _notice =
              'If Prism is still open, close it manually and restart your device.',
        );
      }
    });
  }

  /// Re-pair entry. Because the app DB is unrecoverable here, the local
  /// pairing UI can't load. The pragmatic flow: wipe local data so the next
  /// launch is a clean fresh install, then exit so the user reopens fresh
  /// and walks through normal pairing. The plan says "route to the pairing
  /// entry point", but without a usable DB the only route that works is
  /// "make next launch into a fresh install, then exit".
  Future<void> _repairFromAnotherDevice() async {
    if (_busy) return;
    final confirmed = await _confirmDialog(
      title: 'Re-pair from another device?',
      message:
          'Prism will erase local data on this device so you can pair fresh '
          'from a device with your existing sync history. Your data on the '
          'other device is unaffected. Continue?',
      confirmLabel: 'Erase and re-pair',
      destructive: true,
    );
    if (!confirmed) return;
    await _eraseLocalData();
  }

  Future<void> _confirmAndResetLocalData() async {
    if (_busy) return;
    final confirmed = await _confirmDialog(
      title: 'Reset local data?',
      message:
          'This will erase all local Prism data on this device. Continue?',
      confirmLabel: 'Erase',
      destructive: true,
    );
    if (!confirmed) return;
    await _eraseLocalData();
  }

  Future<void> _saveDiagnosticReport() async {
    if (_busy) return;
    await _run(() async {
      final payload = _buildDiagnosticJson();
      final handler = widget.shareDiagnostic ?? _shareDiagnosticDefault;
      final shared = await handler(payload);
      if (mounted) {
        setState(() {
          _notice = shared
              ? 'Diagnostic report saved. Share it with support if asked.'
              : 'Could not save the diagnostic report.';
        });
      }
    });
  }

  String _buildDiagnosticJson() {
    // Prefer the diagnostic passed via the constructor (the boot path
    // threads it in directly). Fall back to the Riverpod provider for
    // in-app callers — settings screen etc. — that don't have a
    // reference handy. Pretty-printed so users can read the file.
    SecureStorageDiagnostic? diag = widget.diagnostic;
    if (diag == null) {
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        diag = container.read(bootSecureStorageDiagnosticProvider);
      } catch (_) {
        // No ProviderScope ancestor (e.g. direct ResetRecoveryScreen use
        // in tests). Tolerate; the diagnostic just stays null.
      }
    }
    const encoder = JsonEncoder.withIndent('  ');
    final payload = <String, Object?>{
      'prism_diagnostic_version': 1,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'platform_version': Platform.operatingSystemVersion,
      'diagnostic': diag?.toJson(),
    };
    return encoder.convert(payload);
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive
                  ? TextButton.styleFrom(foregroundColor: colorScheme.error)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

/// Default sync-history hint check.
///
/// Returns `true` when any `prism_sync.*` SharedPref key exists OR the
/// `kPrismHadSyncSetup` marker is set. The keychain isn't readable in this
/// mode (that's why we're here), so SharedPref is the only signal.
Future<bool> _defaultSyncHistoryHint() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kPrismHadSyncSetup) == true) return true;
    for (final key in prefs.getKeys()) {
      if (key.startsWith('prism_sync.') || key.startsWith('prism.sync.')) {
        return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// Default share handler. Writes the diagnostic JSON to a file in the temp
/// dir and invokes the platform share sheet.
Future<bool> _shareDiagnosticDefault(String jsonPayload) async {
  try {
    final dir = await getTemporaryDirectory();
    final filename =
        'prism_diagnostic_${DateTime.now().toUtc().millisecondsSinceEpoch}.json';
    final path = p.join(dir.path, filename);
    final file = File(path);
    await file.writeAsString(jsonPayload, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        subject: 'Prism diagnostic report',
      ),
    );
    return result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.dismissed;
  } catch (_) {
    return false;
  }
}
