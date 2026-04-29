import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/sharing/share_invite.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
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
    final terms = watchTerminology(context, ref);

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
            Text(
              context.l10n.sharingUseSharingCode,
              style: theme.textTheme.titleLarge,
            ),
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
              labelText: context.l10n.sharingSharingCodeLabel,
              hintText: context.l10n.sharingSharingCodeHint,
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
                            ? context.l10n.sharingConnectingWith(
                                _parsedInvite!.displayName!,
                              )
                            : context.l10n.sharingReadyToSend,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            PrismTextField(
              controller: _nameController,
              labelText: context.l10n.sharingYourDisplayName,
              hintText: context.l10n.sharingDisplayNameHint,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.sharingWhatToShare,
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
                title: Text(scope.displayNameFor(termPlural: terms.plural)),
                subtitle: Text(
                  scope.descriptionFor(termSingular: terms.singular),
                ),
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
                    label: context.l10n.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                    tone: PrismButtonTone.subtle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrismButton(
                    label: _submitting
                        ? context.l10n.sharingSending
                        : context.l10n.sharingSendRequest,
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
        _error = context.l10n.sharingInvalidCode;
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
          _error = context.l10n.sharingSyncNotConfigured;
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
        _error = context.l10n.sharingFailedToSend(e);
        _submitting = false;
      });
    }
  }
}
