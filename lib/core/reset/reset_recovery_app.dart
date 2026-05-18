import 'dart:io';

import 'package:flutter/material.dart';

import 'package:prism_plurality/core/reset/full_reset_service.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

enum ResetRecoveryScreenMode {
  restartRequired,
  androidClearing,
  freshInstallAnomaly,
  sentinelRestored,
}

class ResetRecoveryApp extends StatelessWidget {
  const ResetRecoveryApp({super.key, required this.mode, this.service});

  final ResetRecoveryScreenMode mode;
  final FullResetService? service;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prism',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9070A0)),
        useMaterial3: true,
      ),
      home: ResetRecoveryScreen(mode: mode, service: service),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ResetRecoveryScreen extends StatefulWidget {
  const ResetRecoveryScreen({super.key, required this.mode, this.service});

  final ResetRecoveryScreenMode mode;
  final FullResetService? service;

  @override
  State<ResetRecoveryScreen> createState() => _ResetRecoveryScreenState();
}

class _ResetRecoveryScreenState extends State<ResetRecoveryScreen> {
  late ResetRecoveryScreenMode _mode = widget.mode;
  bool _busy = false;
  bool? _canContinueWithExistingData;
  String? _error;

  FullResetService get _service => widget.service ?? FullResetService();

  @override
  void initState() {
    super.initState();
    if (_mode == ResetRecoveryScreenMode.freshInstallAnomaly) {
      _loadContinueAvailability();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAnomaly = _mode == ResetRecoveryScreenMode.freshInstallAnomaly;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    isAnomaly
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    size: 48,
                    color: isAnomaly ? colorScheme.error : colorScheme.primary,
                  ),
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
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (isAnomaly) ...[
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
                  ] else
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

  String get _title => switch (_mode) {
    ResetRecoveryScreenMode.restartRequired => 'Reset complete',
    ResetRecoveryScreenMode.androidClearing => 'Reset in progress',
    ResetRecoveryScreenMode.freshInstallAnomaly => 'Prism found existing data',
    ResetRecoveryScreenMode.sentinelRestored => 'Ready to continue',
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
  };

  Future<void> _loadContinueAvailability() async {
    final canContinue = await _service
        .canContinueWithExistingDataAfterAnomaly();
    if (mounted) {
      setState(() => _canContinueWithExistingData = canContinue);
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

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
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
