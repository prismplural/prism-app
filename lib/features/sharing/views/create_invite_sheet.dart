import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sharing/share_invite.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/sensitive_clipboard.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Bottom sheet for publishing and sharing the local `sharing_id`.
class CreateInviteSheet extends ConsumerStatefulWidget {
  const CreateInviteSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<CreateInviteSheet> createState() => _CreateInviteSheetState();
}

class _CreateInviteSheetState extends ConsumerState<CreateInviteSheet> {
  final _nameController = TextEditingController();

  ShareInvite? _invite;
  bool _generating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: _invite != null ? 'Share Your Code' : 'Enable Sharing',
            trailing: _invite == null
                ? PrismGlassIconButton(
                          icon: AppIcons.check,
                          size: PrismTokens.topBarActionSize,
                          isLoading: _generating,
                          accentIcon: true,
                          onPressed: _generate,
                        )
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
                  PrismSurface(
                    padding: const EdgeInsets.all(12),
                    fillColor: theme.colorScheme.errorContainer,
                    borderColor: theme.colorScheme.error.withValues(alpha: 0.2),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_invite == null) ...[
                  Text(
                    'Sharing uses a stable code instead of an inline key exchange. '
                    'Anyone with this code can send you a sharing request.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  PrismTextField(
                    controller: _nameController,
                    labelText: 'Display name (optional)',
                    hintText: 'Shown to the person opening your code',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _generate(),
                  ),
                ] else ...[
                  PrismSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(AppIcons.link, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Sharing Code',
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
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This code stays valid until you turn sharing off.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: PrismButton(
                          label: 'Copy',
                          icon: AppIcons.copy,
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
    if (_generating) return;
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
      final invite = await sharingService.createInvite(
        displayName: _nameController.text.trim(),
      );
      setState(() {
        _invite = invite;
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to enable sharing: $e';
        _generating = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_invite == null) return;
    SensitiveClipboard.copy(_invite!.toShareString());
    PrismToast.show(
      context,
      message: 'Sharing code copied (auto-clears in 15s)',
    );
  }
}
