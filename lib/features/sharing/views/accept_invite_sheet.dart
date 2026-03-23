import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/share_invite.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Bottom sheet for accepting an incoming share invite.
///
/// Flow:
/// 1. Show inviter's display name
/// 2. "Accept" performs ECDH and shows SAS code
/// 3. User confirms SAS code match
/// 4. Select scopes to share back
class AcceptInviteSheet extends ConsumerStatefulWidget {
  const AcceptInviteSheet({super.key, required this.invite});

  final ShareInvite invite;

  @override
  ConsumerState<AcceptInviteSheet> createState() => _AcceptInviteSheetState();
}

enum _AcceptStep { preview, verifying, scopeSelection }

class _AcceptInviteSheetState extends ConsumerState<AcceptInviteSheet> {
  _AcceptStep _step = _AcceptStep.preview;
  Friend? _friend;
  String? _sasCode;
  String? _error;
  final Set<ShareScope> _selectedScopes = {ShareScope.frontStatusOnly};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
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
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            switch (_step) {
              _AcceptStep.preview => 'Incoming Invite',
              _AcceptStep.verifying => 'Verify Connection',
              _AcceptStep.scopeSelection => 'Choose What to Share',
            },
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          switch (_step) {
            _AcceptStep.preview => _buildPreview(theme),
            _AcceptStep.verifying => _buildVerification(theme),
            _AcceptStep.scopeSelection => _buildScopeSelection(theme),
          },
        ],
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrismListRow(
          leading: CircleAvatar(
            child: Text(
              widget.invite.displayName.isNotEmpty
                  ? widget.invite.displayName[0].toUpperCase()
                  : '?',
            ),
          ),
          title: Text(widget.invite.displayName),
          subtitle: widget.invite.isExpired
              ? Text(
                  'Expired',
                  style: TextStyle(color: theme.colorScheme.error),
                )
              : const Text('Wants to connect'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: PrismButton(
                label: 'Decline',
                onPressed: () => Navigator.of(context).pop(),
                tone: PrismButtonTone.subtle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrismButton(
                label: 'Accept',
                onPressed: _acceptInvite,
                enabled: !widget.invite.isExpired,
                tone: PrismButtonTone.filled,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVerification(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Compare this code with ${widget.invite.displayName}:',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            _sasCode ?? '------',
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Do NOT confirm if the codes don\'t match.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        const SizedBox(height: 24),
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
                label: 'Codes Match',
                onPressed: _confirmSas,
                tone: PrismButtonTone.filled,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScopeSelection(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose what ${widget.invite.displayName} can see:',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        ...ShareScope.values.map(
          (scope) => CheckboxListTile(
            secondary: Icon(scope.icon),
            title: Text(scope.displayName),
            subtitle: Text(scope.description),
            value: _selectedScopes.contains(scope),
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  _selectedScopes.add(scope);
                } else {
                  _selectedScopes.remove(scope);
                }
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        PrismButton(
          label: 'Done',
          onPressed: _finishAccept,
          enabled: _selectedScopes.isNotEmpty,
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }

  Future<void> _acceptInvite() async {
    try {
      final sharingService = ref.read(sharingServiceProvider);
      if (sharingService == null) {
        setState(() => _error = 'Sync is not configured');
        return;
      }
      final (friend, sasCode) = await sharingService.acceptInvite(
        widget.invite,
      );
      setState(() {
        _friend = friend;
        _sasCode = sasCode;
        _step = _AcceptStep.verifying;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Failed to accept invite: $e');
    }
  }

  void _confirmSas() {
    if (_friend == null) return;

    setState(() {
      _friend = _friend!.copyWith(isVerified: true);
      _step = _AcceptStep.scopeSelection;
    });
  }

  void _finishAccept() {
    if (_friend == null) return;

    final friend = _friend!.copyWith(
      grantedScopes: _selectedScopes.toList(),
    );

    ref.read(friendsProvider.notifier).addFriend(friend);
    Navigator.of(context).pop();
  }
}
