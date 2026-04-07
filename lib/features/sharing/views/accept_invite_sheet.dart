import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sharing/share_invite.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

/// Bottom sheet for sending a sharing request from someone else's sharing code.
class AcceptInviteSheet extends ConsumerStatefulWidget {
  const AcceptInviteSheet({super.key});

  @override
  ConsumerState<AcceptInviteSheet> createState() => _AcceptInviteSheetState();
}

class _AcceptInviteSheetState extends ConsumerState<AcceptInviteSheet> {
  final _inviteController = TextEditingController();
  final _nameController = TextEditingController();
  final _selectedScopes = <ShareScope>{ShareScope.frontStatusOnly};

  bool _submitting = false;
  String? _error;
  ShareInvite? _parsedInvite;

  @override
  void dispose() {
    _inviteController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Use Sharing Code', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_error != null) ...[
              PrismSurface(
                padding: const EdgeInsets.all(12),
                fillColor: theme.colorScheme.errorContainer,
                borderColor: theme.colorScheme.error.withValues(alpha: 0.2),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: 12),
            ],
            PrismTextField(
              controller: _inviteController,
              labelText: 'Sharing code',
              hintText: 'Paste the code you received',
              maxLines: 4,
              minLines: 3,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => _parseInvite(),
            ),
            const SizedBox(height: 12),
            if (_parsedInvite != null)
              PrismSurface(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(AppIcons.link, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _parsedInvite!.displayName != null
                            ? 'Connecting with ${_parsedInvite!.displayName}'
                            : 'Ready to send a sharing request',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            PrismTextField(
              controller: _nameController,
              labelText: 'Your display name',
              hintText: 'How they will see you',
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              'What to share',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...ShareScope.values.map(
              (scope) => PrismCheckboxRow(
                dense: true,
                leading: Icon(scope.icon, size: 20),
                title: Text(scope.displayName),
                subtitle: Text(scope.description),
                value: _selectedScopes.contains(scope),
                onChanged: (checked) {
                  setState(() {
                    if (checked) {
                      _selectedScopes.add(scope);
                    } else {
                      _selectedScopes.remove(scope);
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PrismButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                    tone: PrismButtonTone.subtle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrismButton(
                    label: _submitting ? 'Sending…' : 'Send Request',
                    icon: AppIcons.personAdd,
                    enabled:
                        !_submitting &&
                        _parsedInvite != null &&
                        _nameController.text.trim().isNotEmpty &&
                        _selectedScopes.isNotEmpty,
                    onPressed: _submit,
                    tone: PrismButtonTone.filled,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _parseInvite() {
    final raw = _inviteController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _parsedInvite = null;
        _error = null;
      });
      return;
    }

    try {
      final invite = ShareInvite.fromShareString(raw);
      setState(() {
        _parsedInvite = invite;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _parsedInvite = null;
        _error = 'Invalid sharing code';
      });
    }
  }

  Future<void> _submit() async {
    final invite = _parsedInvite;
    if (invite == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final sharingService = ref.read(sharingServiceProvider);
      if (sharingService == null) {
        setState(() {
          _error = 'Sync is not configured';
          _submitting = false;
        });
        return;
      }

      await sharingService.initiateFromInvite(
        invite,
        displayName: _nameController.text.trim(),
        offeredScopes: _selectedScopes.toList(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Failed to send sharing request: $e';
        _submitting = false;
      });
    }
  }
}
