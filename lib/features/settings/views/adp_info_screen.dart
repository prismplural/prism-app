import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Educational screen explaining how data is protected in Prism.
///
/// Covers local encryption, zero-knowledge sync, and best practices.
/// All content is informational — no interactive controls.
class AdpInfoScreen extends StatelessWidget {
  const AdpInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Encryption & Privacy', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, NavBarInset.of(context)),
        children: [
          // ── How Your Data is Protected ──────────────
          const _SectionTitle(title: 'How Your Data is Protected'),
          const SizedBox(height: 8),
          _InfoCard(
            icon: AppIcons.lockOutline,
            title: 'Encryption',
            body:
                'Your local database is always encrypted at rest using '
                'AES-256. A device-generated encryption key is stored '
                'in the platform keychain. When sync is enabled, your '
                'data is additionally encrypted end-to-end with '
                'XChaCha20-Poly1305 before leaving your device.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: AppIcons.accountTreeOutlined,
            title: 'Key Hierarchy',
            body: null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Two layers of encryption protect your data:',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Device encryption: a random key generated on your '
                      'device encrypts the local database using AES-256. '
                      'Sync encryption: your password and recovery phrase '
                      'derive a master key, which wraps a data encryption '
                      'key, which derives sync, identity, and pairing keys.',
                  child: ExcludeSemantics(
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontFamily: 'monospace',
                        height: 1.6,
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Device (always active)'),
                          Text('  Random Key → AES-256 → Local DB'),
                          Text(''),
                          Text('Sync (when enabled)'),
                          Text('  Password + Recovery Phrase'),
                          Text('    └─ MEK (Master Encryption Key)'),
                          Text('         └─ DEK (Data Encryption Key)'),
                          Text('              ├─ Sync Key'),
                          Text('              ├─ Identity Key'),
                          Text('              └─ Pairing Key'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Zero-Knowledge Sync ─────────────────────
          const _SectionTitle(title: 'Zero-Knowledge Sync'),
          const SizedBox(height: 8),
          _InfoCard(
            icon: AppIcons.cloudOffOutlined,
            title: 'Server Never Sees Your Data',
            body:
                'When sync is enabled, all data is encrypted on your '
                'device before it leaves. The server only stores '
                'encrypted blobs it cannot read.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: AppIcons.vpnKeyOutlined,
            title: 'Only You Hold the Keys',
            body:
                'Encryption and decryption happen entirely on your '
                'device. No keys are ever transmitted to the server.',
          ),

          const SizedBox(height: 24),

          // ── What This Means ─────────────────────────
          const _SectionTitle(title: 'What This Means'),
          const SizedBox(height: 8),
          _InfoCard(
            icon: AppIcons.shieldOutlined,
            title: 'Server Compromise Protection',
            body:
                'Even if the server is compromised, your data remains '
                'safe because only encrypted data is stored remotely.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: AppIcons.noEncryptionOutlined,
            title: 'Password Never Transmitted',
            body:
                'Your password is used locally to derive encryption '
                'keys and is never sent to any server.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: AppIcons.devicesOutlined,
            title: 'Per-Device Identity',
            body:
                'Each device generates its own identity key pair. '
                'Devices must be explicitly authorised to join your sync '
                'group.',
          ),

          const SizedBox(height: 24),

          // ── Best Practices ──────────────────────────
          const _SectionTitle(title: 'Best Practices'),
          const SizedBox(height: 8),
          _InfoCard(
            icon: AppIcons.passwordOutlined,
            title: 'Use a Strong Password',
            body:
                'Choose a unique, strong password that you do not '
                'reuse elsewhere. This is the root of your key '
                'hierarchy.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: AppIcons.phonelinkLockOutlined,
            title: 'Enable Device Lock Screen',
            body:
                'A device passcode or biometric lock adds an extra '
                'layer of protection against physical access.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: AppIcons.systemUpdateOutlined,
            title: 'Keep the App Updated',
            body:
                'Updates include the latest security patches and '
                'encryption improvements.',
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    this.body,
    this.child,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (body != null)
                    Text(body!, style: theme.textTheme.bodyMedium),
                  ?child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
