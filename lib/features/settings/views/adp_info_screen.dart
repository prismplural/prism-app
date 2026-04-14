import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Educational screen explaining how data is protected in Prism.
///
/// Prose-first: lead + body set the plain-language promise; a collapsible
/// "How it works" section surfaces the technical cryptographic detail for
/// users who want it.  No status indicators or checklist tiles.
class AdpInfoScreen extends StatelessWidget {
  const AdpInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Encryption & Privacy',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 24, 16, NavBarInset.of(context)),
        children: [
          // ── Lock icon ──────────────────────────────────────────────────────
          Center(
            child: Icon(
              AppIcons.duotoneLock,
              size: 56,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),

          // ── Lead ───────────────────────────────────────────────────────────
          Text(
            'Your data is encrypted on this device with keys only your PIN can unlock.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // ── Body ───────────────────────────────────────────────────────────
          Text(
            "Even if someone copies this device's storage, they can't read "
            'your data without your PIN and recovery phrase.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // ── Zero-knowledge note ────────────────────────────────────────────
          PrismSurface(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  AppIcons.cloudOffOutlined,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'When sync is enabled, data is encrypted on your device '
                    'before it leaves. The server only stores encrypted blobs '
                    'it cannot read.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── "How it works" collapsible ────────────────────────────────────
          PrismExpandableSection(
            leading: Icon(
              AppIcons.shieldOutlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              'How it works',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              const _TechItem(
                title: 'Database encryption',
                body: 'HKDF-SHA256(DEK, DeviceSecret) — per-device, '
                    'PIN-derived key. Your device generates this key; '
                    'no server ever sees it.',
              ),
              const _TechItem(
                title: 'Message encryption',
                body: 'XChaCha20-Poly1305 with per-message keys derived '
                    'from your Data Encryption Key (DEK).',
              ),
              const _TechItem(
                title: 'Post-quantum device identity',
                body: 'ML-KEM-768 (key exchange) and ML-DSA-65 (signatures) '
                    'protect against future quantum attacks on device '
                    'authentication.',
              ),
              const _TechItem(
                title: 'Recovery',
                body: 'Your 12-word BIP39 recovery phrase re-derives all '
                    'keys. Store it somewhere safe — it is the only way to '
                    'recover your data if you lose your PIN.',
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// A single technical detail row inside the "How it works" expansion.
class _TechItem extends StatelessWidget {
  const _TechItem({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(body, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
