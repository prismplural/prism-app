import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

/// Modal sheet that prompts for the sync password when the cached DEK is
/// missing but other credentials exist (e.g. after an app update that
/// introduced Signal-style key caching).
class SyncPasswordSheet extends ConsumerStatefulWidget {
  const SyncPasswordSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PrismSheet.show(
      context: context,
      isDismissible: true,
      builder: (_) => const SyncPasswordSheet(),
    );
  }

  @override
  ConsumerState<SyncPasswordSheet> createState() => _SyncPasswordSheetState();
}

class _SyncPasswordSheetState extends ConsumerState<SyncPasswordSheet> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _controller.text;
    if (password.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final success =
        await ref.read(syncHealthProvider.notifier).attemptUnlock(password);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isLoading = false;
        _error = 'Incorrect password. Please try again.';
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
            Icons.lock_outline,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Enter your sync password',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Your sync password is needed to unlock encryption keys on this device.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            enabled: !_isLoading,
            onSubmitted: (_) => _unlock(),
            decoration: InputDecoration(
              hintText: 'Password',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          PrismButton(
            label: 'Unlock',
            onPressed: _unlock,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }
}
