import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/files/prism_file_dialog_service.dart';
import 'package:prism_plurality/features/data_management/providers/data_management_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_expandable_section.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
import '../services/pluralport_bundle.dart';
import '../services/pluralport_mapper.dart';
import '../services/pluralport_service.dart';
import '../widgets/pluralport_brand.dart';

final pluralPortServiceProvider = Provider(
  (ref) => PluralPortService(
    db: ref.watch(databaseProvider),
    exporter: ref.watch(dataExportServiceProvider),
    importer: ref.watch(dataImportServiceProvider),
  ),
);

class PluralPortSheet extends ConsumerStatefulWidget {
  const PluralPortSheet({
    super.key,
    this.scrollController,
    this.allowExport = true,
    this.onImported,
    this.onActionChanged,
  });
  final bool allowExport;
  final ValueChanged<ImportResult>? onImported;

  /// Exposes the current import action to a containing onboarding footer.
  final void Function(bool busy, Future<void> Function() action)?
  onActionChanged;
  final ScrollController? scrollController;
  @override
  ConsumerState<PluralPortSheet> createState() => _PluralPortSheetState();
}

class _PluralPortSheetState extends ConsumerState<PluralPortSheet> {
  PluralPortImportPlan? _plan;
  bool _busy = false;
  bool _systemProfile = false;
  bool _restorePreferences = false;
  String? _status;
  File? _exportFile;
  Directory? _exportDirectory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyAction();
    });
  }

  Future<void> _continue() async {
    if (!mounted || _busy) return;
    if (_plan == null) {
      await _pick();
    } else {
      await _import();
    }
  }

  void _notifyAction() => widget.onActionChanged?.call(_busy, _continue);

  @override
  void dispose() {
    final directory = _exportDirectory;
    if (directory != null) directory.delete(recursive: true).ignore();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    _notifyAction();
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _notifyAction();
      }
    }
  }

  Future<void> _pick() => _run(() async {
    final file = await ref
        .read(prismFileDialogServiceProvider)
        .pickFile(
          allowedExtensions: const ['zip', 'json', 'pluralport', 'openplural'],
        );
    if (file == null) return;
    if (mounted) setState(() => _plan = null);
    if ((file.size ?? 0) > PluralPortBundle.maxUpload) {
      throw const FormatException(
        'PluralPort files must be smaller than 128 MiB.',
      );
    }
    final output = BytesBuilder(copy: false);
    final stream = file.openRead?.call();
    if (stream != null) {
      await for (final chunk in stream) {
        if (output.length + chunk.length > PluralPortBundle.maxUpload) {
          throw const FormatException('PluralPort file exceeds 128 MiB.');
        }
        output.add(chunk);
      }
    } else {
      output.add(await file.readAsBytes());
    }
    final plan = await ref
        .read(pluralPortServiceProvider)
        .preview(output.takeBytes());
    if (mounted) {
      setState(() {
        _plan = plan;
        _systemProfile = false;
        _restorePreferences = false;
      });
    }
  });

  Future<void> _import() => _run(() async {
    final plan = _plan!;
    final result = await ref
        .read(pluralPortServiceProvider)
        .importPlan(
          plan,
          importSystemProfile: _systemProfile,
          restorePrismPreferences: _restorePreferences,
        );
    if (mounted) {
      setState(() {
        _status = context.l10n.pluralPortImportComplete(
          result.totalRecordsCreated,
        );
        _plan = null;
      });
      widget.onImported?.call(result);
    }
  });

  static Uint8List _encode(PluralPortBundle bundle) => bundle.encode();
  Future<void> _export() => _run(() async {
    final bundle = await ref.read(pluralPortServiceProvider).exportBundle();
    final bytes = await compute(_encode, bundle);
    final directory = await getTemporaryDirectory();
    final staging = await Directory(
      '${directory.path}/pluralport-${const Uuid().v4()}',
    ).create();
    final file = File('${staging.path}/prism.pluralport.zip');
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted) {
      await staging.delete(recursive: true);
      return;
    }
    final oldDirectory = _exportDirectory;
    _exportDirectory = staging;
    _exportFile = file;
    if (oldDirectory != null) await oldDirectory.delete(recursive: true);
    if (!mounted) return;
    final warnings = bundle.envelope['warnings'] as List;
    if (warnings.isNotEmpty) {
      setState(
        () => _status = warnings.map((w) => (w as Map)['message']).join('\n'),
      );
    }
    await _save();
  });

  Future<void> _save() async {
    final file = _exportFile;
    if (file == null) return;
    if (mounted) setState(() => _plan = null);
    final outcome = await ref
        .read(prismFileDialogServiceProvider)
        .saveExistingFile(
          ExistingFileSaveRequest(
            sourceFile: file,
            suggestedName: 'prism.pluralport.zip',
            allowedExtensions: const ['zip'],
            sourceIsDurable: false,
            mimeType: 'application/zip',
            dialogTitle: context.l10n.pluralPortSaveTitle,
          ),
        );
    if (!mounted) return;
    setState(() {
      if (outcome.didSave) {
        _status =
            '${_status == null ? '' : '$_status\n'}${context.l10n.pluralPortSaved}';
      }
      if (outcome.status == SaveFileStatus.failed) {
        _status = outcome.error.toString();
      }
    });
  }

  List<Widget> _preview(PluralPortImportPlan plan) {
    final summary = plan.summary;
    final ready = <String, int?>{...summary.ready};
    final retained = <String, int?>{...summary.retained};
    if (_systemProfile && summary.hasSystemProfile) ready['profiles'] = 1;
    final keptProfiles = summary.systemProfiles - (_systemProfile ? 1 : 0);
    if (keptProfiles > 0) retained['profiles'] = keptProfiles;
    if (summary.hasPreferences) {
      (_restorePreferences ? ready : retained)['preferences'] = null;
    }
    final l10n = context.l10n;
    return [
      _categoryCard(
        Icons.check_circle_outline,
        l10n.pluralPortReadyTitle,
        l10n.pluralPortReadyDescription,
        ready,
        empty: l10n.pluralPortNoReadyData,
      ),
      if (retained.isNotEmpty)
        _categoryCard(
          Icons.inventory_2_outlined,
          l10n.pluralPortRetainedTitle,
          l10n.pluralPortRetainedDescription,
          retained,
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          l10n.pluralPortExtraDetails,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      if (summary.bundledFiles + summary.missingFiles + summary.unbundledMedia >
          0)
        _previewCard(
          Icons.attach_file,
          l10n.pluralPortFilesTitle,
          l10n.pluralPortFilesDescription,
          [
            if (summary.bundledFiles > 0)
              Text(l10n.pluralPortBundledFiles(summary.bundledFiles)),
            if (summary.missingFiles > 0)
              Text(l10n.pluralPortMissingFiles(summary.missingFiles)),
            if (summary.unbundledMedia > 0)
              Text(l10n.pluralPortUnbundledMedia(summary.unbundledMedia)),
          ],
        ),
    ];
  }

  Widget _categoryCard(
    IconData icon,
    String title,
    String description,
    Map<String, int?> categories, {
    String? empty,
  }) => _previewCard(icon, title, description, [
    if (categories.isEmpty && empty != null) Text(empty),
    for (final entry in categories.entries)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(context.l10n.pluralPortCategory(entry.key))),
            if (entry.value != null)
              Text(
                '${entry.value}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
          ],
        ),
      ),
  ]);

  Widget _previewCard(
    IconData icon,
    String title,
    String description,
    List<Widget> children,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(description),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        controller: widget.scrollController,
        children: [
          const PluralPortLogo(),
          if (_plan == null) ...[
            Text(context.l10n.pluralPortDescription),
            const SizedBox(height: 16),
          ],
          PrismButton(
            label: context.l10n.pluralPortChooseFile,
            onPressed: _pick,
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          if (_plan case final plan?) ...[
            if (plan.summary.hasSystemProfile)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _systemProfile,
                onChanged: _busy
                    ? null
                    : (value) =>
                          setState(() => _systemProfile = value ?? false),
                title: Text(context.l10n.pluralPortReplaceProfile),
                subtitle: Text(
                  context.l10n.pluralPortReplaceProfileDescription,
                ),
              ),
            if (plan.summary.hasPreferences)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _restorePreferences,
                onChanged: _busy
                    ? null
                    : (value) =>
                          setState(() => _restorePreferences = value ?? false),
                title: Text(context.l10n.pluralPortRestorePreferences),
                subtitle: Text(
                  context.l10n.pluralPortRestorePreferencesDescription,
                ),
              ),
            ..._preview(plan),
            if (plan.warnings.isNotEmpty)
              PrismExpandableSection(
                title: Text(context.l10n.pluralPortWarningDetails),
                children: [
                  for (final warning in plan.warnings.take(100)) Text(warning),
                  if (plan.warnings.length > 100)
                    Text(
                      context.l10n.pluralPortMoreWarnings(
                        plan.warnings.length - 100,
                      ),
                    ),
                ],
              ),
            PrismButton(
              label: context.l10n.pluralPortImport,
              onPressed: _import,
              enabled: !_busy,
            ),
            const SizedBox(height: 24),
          ],
          if (widget.allowExport) ...[
            Text(context.l10n.pluralPortPlaintextNotice),
            const SizedBox(height: 12),
            PrismButton(
              label: context.l10n.pluralPortExport,
              onPressed: _export,
              enabled: !_busy,
            ),
          ],
          if (_exportFile != null)
            PrismButton(
              label: context.l10n.pluralPortSaveAgain,
              onPressed: () => _run(_save),
              enabled: !_busy,
            ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: PrismSpinner(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(_status!),
            ),
        ],
      ),
    ),
  );
}

void showPluralPortSheet(BuildContext context) => PrismSheet.showFullScreen(
  context: context,
  builder: (context, scrollController) =>
      PluralPortSheet(scrollController: scrollController),
);
