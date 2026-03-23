import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sharing/share_invite.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Bottom sheet for creating and sharing an invite.
class CreateInviteSheet extends ConsumerStatefulWidget {
  const CreateInviteSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<CreateInviteSheet> createState() => _CreateInviteSheetState();
}

class _CreateInviteSheetState extends ConsumerState<CreateInviteSheet> {
  final _nameController = TextEditingController();
  final _selectedScopes = <ShareScope>{ShareScope.frontStatusOnly};

  ShareInvite? _invite;
  bool _generating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canGenerate =>
      !_generating && _nameController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canGenerate = _canGenerate;

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: _invite != null ? 'Share Invite' : 'Create Invite',
            trailing: _invite == null
                ? (_generating
                    ? SizedBox(
                        width: PrismTokens.topBarActionSize,
                        height: PrismTokens.topBarActionSize,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : PrismGlassIconButton(
                        icon: Icons.check,
                        size: PrismTokens.topBarActionSize,
                        tint: canGenerate ? theme.colorScheme.primary : null,
                        accentIcon: canGenerate,
                        onPressed: canGenerate ? _generate : null,
                      ))
                : null,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              children: [
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

                if (_invite == null) ...[
                  // ── Input form ────────────────────────────────
                  PrismTextField(
                    controller: _nameController,
                    labelText: 'Your display name',
                    hintText: 'How your friend will see you',
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
                    (scope) => CheckboxListTile(
                      dense: true,
                      secondary: Icon(scope.icon, size: 20),
                      title: Text(scope.displayName),
                      subtitle: Text(
                        scope.description,
                        style: theme.textTheme.bodySmall,
                      ),
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
                ] else ...[
                  // ── Invite display ────────────────────────────
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.link, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Invite Code',
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              _invite!.toShareString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                              maxLines: 4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Expires in 24 hours',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: PrismButton(
                          label: 'Copy',
                          icon: Icons.copy,
                          onPressed: _copyToClipboard,
                          tone: PrismButtonTone.subtle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrismButton(
                          label: 'Done',
                          onPressed: () => Navigator.of(context).pop(),
                          tone: PrismButtonTone.filled,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final sharingService = ref.read(sharingServiceProvider);
      if (sharingService == null) {
        setState(() {
          _error = 'Sync is not configured';
          _generating = false;
        });
        return;
      }
      final invite = await sharingService.createInvite(name);
      setState(() {
        _invite = invite;
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to create invite: $e';
        _generating = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_invite == null) return;
    Clipboard.setData(ClipboardData(text: _invite!.toShareString()));
    PrismToast.show(context, message: 'Invite copied to clipboard');
  }
}
