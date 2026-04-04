import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Settings screen for PIN lock, biometric unlock, and auto-lock delay.
class PinLockSettingsScreen extends ConsumerStatefulWidget {
  const PinLockSettingsScreen({super.key});

  @override
  ConsumerState<PinLockSettingsScreen> createState() =>
      _PinLockSettingsScreenState();
}

class _PinLockSettingsScreenState extends ConsumerState<PinLockSettingsScreen> {
  void _showSetPinFlow() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SetPinFlowScreen(
          onComplete: () {
            ref.invalidate(isPinSetProvider);
            ref
                .read(settingsNotifierProvider.notifier)
                .updatePinLockEnabled(true);
            Navigator.of(context).pop();
          },
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _changePinFlow() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SetPinFlowScreen(
          onComplete: () {
            ref.invalidate(isPinSetProvider);
            Navigator.of(context).pop();
          },
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _removePin() async {
    final service = ref.read(pinLockServiceProvider);
    await service.clearPin();
    ref.invalidate(isPinSetProvider);
    ref.read(settingsNotifierProvider.notifier).updatePinLockEnabled(false);
    ref.read(settingsNotifierProvider.notifier).updateBiometricLockEnabled(false);
  }

  @override
  Widget build(BuildContext context) {
    // Guard: wait for settings to load before showing interactive controls.
    // Without this, pinLockEnabled defaults to false on cold start, which
    // would briefly show the toggle as off for users who have PIN enabled.
    final settingsLoaded = ref.watch(
      systemSettingsProvider.select((s) => s.hasValue),
    );
    final isPinEnabled = ref.watch(pinLockEnabledProvider);
    final biometricLockEnabled = ref.watch(biometricLockEnabledProvider);
    final autoLockDelay = ref.watch(autoLockDelaySecondsProvider);
    final isPinSetAsync = ref.watch(isPinSetProvider);
    final biometricAvailableAsync = ref.watch(isBiometricAvailableProvider);

    final pinSet = isPinSetAsync.value ?? false;
    final biometricAvailable = biometricAvailableAsync.value ?? false;

    if (!settingsLoaded) {
      return PrismPageScaffold(
        topBar: const PrismTopBar(
          title: 'Privacy & Security',
          showBackButton: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Privacy & Security',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          // PIN toggle
          PrismSection(
            title: 'PIN Lock',
            child: PrismSectionCard(
              child: Column(
                children: [
                  PrismSwitchRow(
                    icon: AppIcons.lockOutline,
                    iconColor: Colors.indigo,
                    title: 'Enable PIN Lock',
                    subtitle: 'Require a PIN to open the app',
                    value: isPinEnabled && pinSet,
                    onChanged: (value) {
                      if (value) {
                        _showSetPinFlow();
                      } else {
                        _removePin();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // Biometric (shown when available, disabled when PIN is not set)
          if (biometricAvailable)
            Opacity(
              opacity: isPinEnabled && pinSet ? 1.0 : 0.5,
              child: PrismSection(
                title: 'Biometric',
                child: PrismSectionCard(
                  child: PrismSwitchRow(
                    icon: AppIcons.fingerprint,
                    iconColor: Colors.teal,
                    title: 'Biometric Unlock',
                    subtitle: isPinEnabled && pinSet
                        ? 'Use Face ID or fingerprint to unlock'
                        : 'Enable PIN Lock to use biometric unlock',
                    value: biometricLockEnabled,
                    enabled: isPinEnabled && pinSet,
                    onChanged: (value) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .updateBiometricLockEnabled(value);
                    },
                  ),
                ),
              ),
            ),

          // Auto-lock delay
          if (isPinEnabled && pinSet)
            PrismSection(
              title: 'Auto-Lock',
              child: PrismSectionCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 6,
                          bottom: 8,
                        ),
                        child: Text(
                          'Lock after leaving the app',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in const {
                            0: 'Instant',
                            15: '15s',
                            60: '1m',
                            300: '5m',
                            900: '15m',
                          }.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected:
                                  autoLockDelay == entry.key,
                              onSelected: (selected) {
                                if (selected) {
                                  ref
                                      .read(settingsNotifierProvider
                                          .notifier)
                                      .updateAutoLockDelaySeconds(
                                          entry.key);
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Change PIN / Remove PIN buttons
          if (isPinEnabled && pinSet)
            PrismSection(
              title: 'Manage',
              child: PrismSectionCard(
                child: Column(
                  children: [
                    PrismListRow(
                      leading: Icon(AppIcons.pinOutlined),
                      title: const Text('Change PIN'),
                      trailing: Icon(
                        AppIcons.chevronRightRounded,
                        size: 20,
                      ),
                      onTap: _changePinFlow,
                    ),
                    const Divider(height: 1, indent: 56, endIndent: 12),
                    PrismListRow(
                      leading: Icon(
                        AppIcons.deleteOutline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        'Remove PIN',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      onTap: _removePin,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Two-step set-PIN flow: set then confirm.
class _SetPinFlowScreen extends ConsumerStatefulWidget {
  const _SetPinFlowScreen({
    required this.onComplete,
    required this.onCancel,
  });

  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  ConsumerState<_SetPinFlowScreen> createState() => _SetPinFlowScreenState();
}

class _SetPinFlowScreenState extends ConsumerState<_SetPinFlowScreen> {
  String? _pendingPin;

  @override
  Widget build(BuildContext context) {
    if (_pendingPin == null) {
      // Step 1: Set PIN
      return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) widget.onCancel();
        },
        child: _CapturePinScreen(
          mode: PinInputMode.set,
          onPinEntered: (pin) {
            setState(() => _pendingPin = pin);
          },
        ),
      );
    }

    // Step 2: Confirm PIN
    return _CapturePinScreen(
      mode: PinInputMode.confirm,
      pinToConfirm: _pendingPin,
      onPinEntered: (_) async {
        final service = ref.read(pinLockServiceProvider);
        await service.storePin(_pendingPin!);
        widget.onComplete();
      },
    );
  }
}

/// Wraps PinInputScreen but captures the entered PIN string.
class _CapturePinScreen extends StatefulWidget {
  const _CapturePinScreen({
    required this.mode,
    required this.onPinEntered,
    this.pinToConfirm,
  });

  final PinInputMode mode;
  final void Function(String pin) onPinEntered;
  final String? pinToConfirm;

  @override
  State<_CapturePinScreen> createState() => _CapturePinScreenState();
}

class _CapturePinScreenState extends State<_CapturePinScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  static const _pinLength = 6;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  String get _title {
    return switch (widget.mode) {
      PinInputMode.set => 'Set PIN',
      PinInputMode.confirm => 'Confirm PIN',
      PinInputMode.unlock => 'Enter PIN',
    };
  }

  String get _subtitle {
    return switch (widget.mode) {
      PinInputMode.set => 'Choose a $_pinLength-digit PIN',
      PinInputMode.confirm => 'Re-enter your PIN to confirm',
      PinInputMode.unlock => 'Enter your PIN to unlock',
    };
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength) return;
    Haptics.light();
    setState(() => _pin += digit);
    if (_pin.length == _pinLength) {
      _onPinComplete();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    Haptics.selection();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _onPinComplete() {
    if (widget.mode == PinInputMode.confirm) {
      if (_pin == widget.pinToConfirm) {
        widget.onPinEntered(_pin);
      } else {
        _showError();
      }
    } else {
      widget.onPinEntered(_pin);
    }
  }

  void _showError() {
    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0);
    setState(() => _pin = '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // Back button
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: IconButton(
                  icon: Icon(AppIcons.arrowBack),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            const Spacer(flex: 2),
            Text(
              _title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) => Transform.translate(
                offset: Offset(_shakeAnimation.value, 0),
                child: child,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (i) {
                  final filled = i < _pin.length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? accentColor
                            : accentColor.withValues(alpha: 0.15),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  for (var row = 0; row < 4; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: _buildRow(row),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRow(int row) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return _NumpadKey(
          label: digit,
          onTap: () => _onDigit(digit),
        );
      });
    }
    return [
      const SizedBox(width: 72, height: 72),
      _NumpadKey(
        label: '0',
        onTap: () => _onDigit('0'),
      ),
      _NumpadKey(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
      ),
    ];
  }
}

class _NumpadKey extends StatelessWidget {
  const _NumpadKey({
    this.label,
    this.icon,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        child: label != null
            ? Text(
                label!,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              )
            : Icon(icon, size: 24, color: theme.colorScheme.onSurface),
      ),
    );
  }
}
