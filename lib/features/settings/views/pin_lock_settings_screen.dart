import 'dart:async';

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
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/pin_numpad_button.dart';

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
    unawaited(ref.read(settingsNotifierProvider.notifier).updatePinLockEnabled(false));
    unawaited(ref
        .read(settingsNotifierProvider.notifier)
        .updateBiometricLockEnabled(false));
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
        topBar: PrismTopBar(title: context.l10n.privacySecurityTitle, showBackButton: true),
        body: const PrismLoadingState(),
      );
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.privacySecurityTitle,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          // PIN toggle
          PrismSection(
            title: context.l10n.pinLockSection,
            child: PrismSectionCard(
              child: Column(
                children: [
                  PrismSwitchRow(
                    icon: AppIcons.lockOutline,
                    iconColor: Colors.indigo,
                    title: context.l10n.pinLockEnableTitle,
                    subtitle: context.l10n.pinLockEnableSubtitle,
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
                title: context.l10n.pinLockBiometricSection,
                child: PrismSectionCard(
                  child: PrismSwitchRow(
                    icon: AppIcons.fingerprint,
                    iconColor: Colors.teal,
                    title: context.l10n.pinLockBiometricTitle,
                    subtitle: isPinEnabled && pinSet
                        ? context.l10n.pinLockBiometricSubtitle
                        : context.l10n.pinLockBiometricDisabledSubtitle,
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
              title: context.l10n.pinLockAutoLockSection,
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
                        padding: const EdgeInsets.only(left: 6, bottom: 8),
                        child: Text(
                          context.l10n.pinLockAfterLeaving,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in {
                            0: context.l10n.pinLockInstant,
                            15: context.l10n.pinLock15s,
                            60: context.l10n.pinLock1m,
                            300: context.l10n.pinLock5m,
                            900: context.l10n.pinLock15m,
                          }.entries)
                            PrismChip(
                              label: entry.value,
                              selected: autoLockDelay == entry.key,
                              onTap: () => ref
                                  .read(settingsNotifierProvider.notifier)
                                  .updateAutoLockDelaySeconds(entry.key),
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
              title: context.l10n.pinLockManageSection,
              child: PrismSectionCard(
                child: Column(
                  children: [
                    PrismListRow(
                      leading: Icon(AppIcons.pinOutlined),
                      title: Text(context.l10n.pinLockChange),
                      trailing: Icon(AppIcons.chevronRightRounded, size: 20),
                      onTap: _changePinFlow,
                    ),
                    const Divider(height: 1, indent: 56, endIndent: 12),
                    PrismListRow(
                      leading: Icon(
                        AppIcons.deleteOutline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        context.l10n.pinLockRemove,
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
  const _SetPinFlowScreen({required this.onComplete, required this.onCancel});

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
    with TickerProviderStateMixin {
  String _pin = '';
  static const _pinLength = 6;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  late AnimationController _dotController;
  late Animation<double> _dotScaleAnim;
  int? _lastFilledDotIndex;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
        );
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _dotScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
    ]).animate(_dotController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  String _title(BuildContext context) {
    return switch (widget.mode) {
      PinInputMode.set => context.l10n.pinLockSetTitle,
      PinInputMode.confirm => context.l10n.pinLockConfirmTitle,
      PinInputMode.unlock => context.l10n.pinLockEnterTitle,
    };
  }

  String _subtitle(BuildContext context) {
    return switch (widget.mode) {
      PinInputMode.set => context.l10n.pinLockSetSubtitle,
      PinInputMode.confirm => context.l10n.pinLockConfirmSubtitle,
      PinInputMode.unlock => context.l10n.pinLockUnlockSubtitle,
    };
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength) return;
    Haptics.light();
    setState(() => _pin += digit);
    if (!MediaQuery.of(context).disableAnimations) {
      setState(() => _lastFilledDotIndex = _pin.length - 1);
      _dotController.forward(from: 0);
    }
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
    setState(() {
      _pin = '';
      _lastFilledDotIndex = null;
    });
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
                child: PrismInlineIconButton(
                  icon: AppIcons.arrowBack,
                  iconSize: 20,
                  tooltip: context.l10n.back,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            const Spacer(flex: 2),
            Text(
              _title(context),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle(context),
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
                    child: AnimatedBuilder(
                      animation: _dotScaleAnim,
                      builder: (context, child) => Transform.scale(
                        scale: i == _lastFilledDotIndex ? _dotScaleAnim.value : 1.0,
                        child: child,
                      ),
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
                        children: _buildRow(context, row),
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

  List<Widget> _buildRow(BuildContext context, int row) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = '${row * 3 + col + 1}';
        return PinNumpadButton(label: digit, onTap: () => _onDigit(digit), size: 72);
      });
    }
    return [
      const SizedBox(width: 72, height: 72),
      PinNumpadButton(label: '0', onTap: () => _onDigit('0'), size: 72),
      PinNumpadButton(
        icon: AppIcons.backspaceOutlined,
        onTap: _onBackspace,
        size: 72,
        semanticLabel: context.l10n.delete,
      ),
    ];
  }
}
