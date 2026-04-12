import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Modal sheet that prompts for the app PIN when the cached DEK is missing
/// but other credentials exist (e.g. after an app update that introduced
/// Signal-style key caching).
class SyncPinSheet extends ConsumerStatefulWidget {
  const SyncPinSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PrismSheet.show(
      context: context,
      isDismissible: true,
      builder: (_) => const SyncPinSheet(),
    );
  }

  @override
  ConsumerState<SyncPinSheet> createState() => _SyncPinSheetState();
}

class _SyncPinSheetState extends ConsumerState<SyncPinSheet> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final pin = _controller.text.trim();
    if (pin.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final success = await ref
        .read(syncHealthProvider.notifier)
        .attemptUnlock(pin);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isLoading = false;
        _error = context.l10n.settingsSyncPinWrong;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 16 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            AppIcons.lockOutline,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.settingsSyncPinTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.settingsSyncPinBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          PrismTextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            enabled: !_isLoading,
            onSubmitted: (_) => _unlock(),
            labelText: context.l10n.settingsSyncPinFieldLabel,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            errorText: _error,
          ),
          const SizedBox(height: 16),
          PrismButton(
            label: context.l10n.settingsSyncPinUnlock,
            onPressed: _unlock,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }
}
