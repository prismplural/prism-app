import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/migration/providers/migration_providers.dart';
import 'package:prism_plurality/features/migration/services/sp_importer.dart';

/// Import Data step — lets user choose between PluralKit, Simply Plural,
/// or skipping entirely (default: no import selected).
class ImportDataStep extends ConsumerStatefulWidget {
  const ImportDataStep({super.key});

  @override
  ConsumerState<ImportDataStep> createState() => _ImportDataStepState();
}

enum _ImportSource { none, pluralKit, simplyPlural }

class _ImportDataStepState extends ConsumerState<ImportDataStep> {
  _ImportSource _selected = _ImportSource.none;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (_selected) {
        _ImportSource.none => _SourcePicker(
            key: const ValueKey('picker'),
            onSelect: (source) {
              setState(() => _selected = source);
            },
            onSyncDevice: () {
              ref.read(onboardingProvider.notifier).enterSyncDeviceFlow();
            },
          ),
        _ImportSource.pluralKit => _PluralKitImportFlow(
            key: const ValueKey('pk'),
            onBack: () => setState(() => _selected = _ImportSource.none),
          ),
        _ImportSource.simplyPlural => _SimplyPluralImportFlow(
            key: const ValueKey('sp'),
            onBack: () => setState(() => _selected = _ImportSource.none),
          ),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Source picker (default view)
// ---------------------------------------------------------------------------

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    super.key,
    required this.onSelect,
    required this.onSyncDevice,
  });

  final void Function(_ImportSource) onSelect;
  final VoidCallback onSyncDevice;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'You can import your existing data or skip this step to start fresh.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _SourceCard(
            icon: Icons.devices,
            color: Colors.teal,
            title: 'Sync with Existing Device',
            description: 'Scan a pairing QR code to sync data from another device',
            onTap: onSyncDevice,
          ),
          const SizedBox(height: 16),
          _SourceCard(
            icon: Icons.sync,
            color: Colors.cyan,
            title: 'PluralKit',
            description: 'Import members and fronting history from PluralKit via API token',
            onTap: () => onSelect(_ImportSource.pluralKit),
          ),
          const SizedBox(height: 16),
          _SourceCard(
            icon: Icons.file_upload_outlined,
            color: Colors.deepPurple,
            title: 'Simply Plural',
            description: 'Import from a Simply Plural JSON export file',
            onTap: () => onSelect(_ImportSource.simplyPlural),
          ),
          const SizedBox(height: 32),
          Text(
            'You can always import data later from Settings.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _pressed
                ? Colors.white.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed
                  ? widget.color.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.2),
                ),
                child: Icon(widget.icon, color: widget.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PluralKit import flow
// ---------------------------------------------------------------------------

class _PluralKitImportFlow extends ConsumerStatefulWidget {
  const _PluralKitImportFlow({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_PluralKitImportFlow> createState() =>
      _PluralKitImportFlowState();
}

class _PluralKitImportFlowState extends ConsumerState<_PluralKitImportFlow> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _isImporting = false;
  bool _importSuccess = false;
  String? _errorMessage;
  int _importedCount = 0;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back to source picker
          Align(
            alignment: Alignment.centerLeft,
            child: _BackLink(onTap: widget.onBack),
          ),
          const SizedBox(height: 16),

          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to get your token:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                const _InstructionRow(number: '1', text: 'Open Discord'),
                const _InstructionRow(
                    number: '2', text: 'DM PluralKit bot: pk;token'),
                const _InstructionRow(
                    number: '3', text: 'Copy the token and paste below'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Token field
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _tokenController,
              obscureText: _obscureToken,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Paste your PluralKit token',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureToken ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  onPressed: () =>
                      setState(() => _obscureToken = !_obscureToken),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Import button or success
          if (_importSuccess)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Imported $_importedCount members from PluralKit!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            _ActionButton(
              label: 'Import Members',
              color: Colors.cyan,
              isLoading: _isImporting,
              onPressed: _handleImport,
            ),

          // Error
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade300, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleImport() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _errorMessage = 'Please enter your PluralKit token.');
      return;
    }

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final pkNotifier = ref.read(pluralKitSyncProvider.notifier);
      await pkNotifier.setToken(token);

      final connected = await pkNotifier.testConnection();
      if (!connected) {
        // Clear the invalid token so it doesn't persist
        await pkNotifier.clearToken();
        setState(() {
          _isImporting = false;
          _errorMessage = 'Could not connect. Please check your token.';
        });
        return;
      }

      // importMembersOnly() already creates/updates members in the DB via the
      // sync service's _importMembers helper (which deduplicates by PK UUID).
      // We intentionally do NOT create members again here — the previous code
      // duplicated every PK member on each import because createMember() does
      // not set pluralkitUuid, so the service's dedup couldn't catch them.
      final (systemName, importedMembers) = await pkNotifier.importMembersOnly();

      if (systemName != null && systemName.isNotEmpty) {
        ref.read(onboardingProvider.notifier).setSystemName(systemName);
      }
      ref.read(onboardingProvider.notifier).setWasImportedFromPluralKit(true);

      setState(() {
        _isImporting = false;
        _importSuccess = true;
        _importedCount = importedMembers.length;
      });
    } catch (e) {
      setState(() {
        _isImporting = false;
        _errorMessage = 'Import failed: $e';
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Simply Plural import flow
// ---------------------------------------------------------------------------

class _SimplyPluralImportFlow extends ConsumerStatefulWidget {
  const _SimplyPluralImportFlow({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_SimplyPluralImportFlow> createState() =>
      _SimplyPluralImportFlowState();
}

class _SimplyPluralImportFlowState
    extends ConsumerState<_SimplyPluralImportFlow> {
  @override
  Widget build(BuildContext context) {
    final migration = ref.watch(importerProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back to source picker
          if (migration.step == ImportState.idle)
            Align(
              alignment: Alignment.centerLeft,
              child: _BackLink(onTap: widget.onBack),
            ),
          const SizedBox(height: 16),

          // Instructions
          if (migration.step == ImportState.idle) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to export from Simply Plural:',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _InstructionRow(
                    number: '1',
                    text: 'Open Simply Plural app',
                  ),
                  const _InstructionRow(
                    number: '2',
                    text: 'Go to Settings → Export Data',
                  ),
                  const _InstructionRow(
                    number: '3',
                    text: 'Save the JSON file and select it below',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _ActionButton(
              label: 'Select Export File',
              color: Colors.deepPurple,
              onPressed: () {
                ref.read(importerProvider.notifier).selectAndParseFile();
              },
            ),
          ],

          // Parsing
          if (migration.step == ImportState.parsing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Reading file...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          // Preview
          if (migration.step == ImportState.previewing &&
              migration.exportData != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Found data:',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PreviewRow(
                    label: 'Members',
                    count: migration.exportData!.members.length +
                        migration.exportData!.customFronts.length,
                  ),
                  _PreviewRow(
                    label: 'Fronting sessions',
                    count: migration.exportData!.frontHistory.length,
                  ),
                  _PreviewRow(
                    label: 'Conversations',
                    count: migration.exportData!.channels.length,
                  ),
                  _PreviewRow(
                    label: 'Messages',
                    count: migration.exportData!.messages.length,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ActionButton(
              label: 'Import Data',
              color: Colors.deepPurple,
              onPressed: () {
                ref.read(importerProvider.notifier).executeImport();
              },
            ),
          ],

          // Importing / downloading avatars
          if (migration.step == ImportState.importing ||
              migration.step == ImportState.downloadingAvatars) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      migration.progressLabel.isNotEmpty
                          ? migration.progressLabel
                          : 'Importing... ${(migration.progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Complete
          if (migration.step == ImportState.complete) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Import complete! Your data is ready.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Error
          if (migration.step == ImportState.error) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      migration.error ?? 'Import failed.',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Try Again',
              color: Colors.deepPurple,
              onPressed: () {
                ref.read(importerProvider.notifier).reset();
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _BackLink extends StatelessWidget {
  const _BackLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back_ios,
              size: 14, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            'Other import options',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    this.isLoading = false,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isLoading
          ? null
          : (_) => setState(() => _pressed = true),
      onTapUp: widget.isLoading
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onPressed();
            },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _pressed
                ? widget.color.withValues(alpha: 0.7)
                : widget.color.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.cyan.withValues(alpha: 0.3),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
