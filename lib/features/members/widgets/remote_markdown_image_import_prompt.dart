import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/services/remote_markdown_image_refs.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

Future<bool> promptAndStageRemoteMarkdownImages({
  required BuildContext context,
  required WidgetRef ref,
  required TextEditingController controller,
  required String sessionId,
}) async {
  final dataRefs = findDataMarkdownImageRefs(controller.text);
  final remoteRefs = findRemoteMarkdownImageRefs(controller.text);
  if (dataRefs.isEmpty && remoteRefs.isEmpty) return true;

  final processor = ref.read(bioImageProcessorProvider(sessionId));
  final library = await readImageLibrarySnapshot(
    ref,
    useCachedValueOnError: true,
  );
  if (!context.mounted) return false;

  final unavailableTags = [
    ...library.map((a) => a.tag),
    ...processor.staged.map((s) => s.tag),
  ];
  int? embeddedStageStart;
  String? embeddedOriginalText;
  TextSelection? embeddedOriginalSelection;

  void rollbackEmbeddedStaging() {
    final stageStart = embeddedStageStart;
    if (stageStart != null && processor.staged.length > stageStart) {
      processor.staged.removeRange(stageStart, processor.staged.length);
    }

    final originalText = embeddedOriginalText;
    if (originalText != null) {
      controller.value = TextEditingValue(
        text: originalText,
        selection:
            embeddedOriginalSelection ??
            TextSelection.collapsed(offset: originalText.length),
      );
    }
  }

  if (dataRefs.isNotEmpty) {
    embeddedStageStart = processor.staged.length;
    embeddedOriginalText = controller.text;
    embeddedOriginalSelection = controller.selection;
    final imports = buildDataMarkdownImageImports(
      dataRefs,
      unavailableTags: unavailableTags,
    );

    final notifier = ref.read(bioImageProcessingStateProvider.notifier);
    notifier.setProcessing(imports.length);

    final successes = <String, String>{};
    for (final item in imports) {
      try {
        final bytes = decodeDataMarkdownImageRef(item.ref);
        final stagedTag = await processor.stageDeviceImage(
          bytes,
          item.suggestedTag,
          altText: item.ref.altText.isEmpty ? null : item.ref.altText,
        );
        successes[item.ref.fullMatch] = '![${item.ref.altText}]($stagedTag)';
        notifier.incrementCompleted();
      } catch (e) {
        rollbackEmbeddedStaging();
        final message = _stageEmbeddedFailureMessage(e);
        notifier.setError(message);
        if (context.mounted) {
          PrismToast.error(context, message: message);
        }
        return false;
      }
    }

    controller.text = rewriteDataMarkdownImageRefs(controller.text, successes);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  final refs = findRemoteMarkdownImageRefs(controller.text);
  if (refs.isEmpty) return true;
  final imports = buildRemoteMarkdownImageImports(
    refs,
    unavailableTags: [
      ...library.map((a) => a.tag),
      ...processor.staged.map((s) => s.tag),
    ],
  );
  if (imports.isEmpty) return true;
  if (!context.mounted) {
    rollbackEmbeddedStaging();
    return false;
  }

  final choices = await _showRemoteImageImportPrompt(context, imports: imports);
  if (choices == null) {
    rollbackEmbeddedStaging();
    return false;
  }
  if (choices.isEmpty) return true;

  final latestLibrary = await readImageLibrarySnapshot(
    ref,
    useCachedValueOnError: true,
  );
  if (!context.mounted) {
    rollbackEmbeddedStaging();
    return false;
  }
  final validation = validateRemoteMarkdownImageTagChoices(
    choices,
    unavailableTags: [
      ...latestLibrary.map((a) => a.tag),
      ...processor.staged.map((s) => s.tag),
    ],
  );
  if (!validation.isValid) {
    final message = validation.errorMessage ?? 'Could not save image tags';
    PrismToast.error(context, message: message);
    rollbackEmbeddedStaging();
    return false;
  }

  final notifier = ref.read(bioImageProcessingStateProvider.notifier);
  notifier.setProcessing(validation.normalizedTags.length);

  final successes = <String, String>{};
  final failures = <String>[];
  for (final entry in validation.normalizedTags.entries) {
    try {
      final stagedTag = await processor.stageUrlImage(entry.key, entry.value);
      successes[entry.key] = stagedTag;
    } catch (e) {
      failures.add(_stageFailureMessage(e));
    } finally {
      notifier.incrementCompleted();
    }
  }

  if (successes.isEmpty) {
    final message = failures.isNotEmpty
        ? failures.first
        : 'Could not fetch image';
    notifier.setError(message);
    if (context.mounted) {
      PrismToast.error(context, message: message);
    }
    rollbackEmbeddedStaging();
    return false;
  }

  controller.text = rewriteRemoteMarkdownImageRefs(controller.text, successes);
  controller.selection = TextSelection.collapsed(
    offset: controller.text.length,
  );

  if (context.mounted && successes.length < choices.length) {
    notifier.setError('Some images could not be fetched');
    PrismToast.error(context, message: 'Some images could not be fetched');
  }
  return true;
}

String _stageEmbeddedFailureMessage(Object error) {
  if (error is FormatException) {
    return 'Could not read embedded image';
  }
  if (error is StateError) return error.message;
  return 'Could not save embedded image';
}

String _stageFailureMessage(Object error) {
  if (error is StateError) return error.message;
  return 'Could not fetch image';
}

Future<Map<String, String>?> _showRemoteImageImportPrompt(
  BuildContext context, {
  required List<RemoteMarkdownImageImport> imports,
}) {
  final nav = Navigator.of(context, rootNavigator: true);
  final fieldsKey = GlobalKey<_RemoteImageImportFieldsState>();
  return PrismDialog.show<Map<String, String>>(
    context: context,
    title: 'Save web images to Prism?',
    message:
        'Prism does not load web images directly from saved markdown. Download these into your encrypted image library and replace the links with Prism tags.',
    builder: (_) => _RemoteImageImportFields(key: fieldsKey, imports: imports),
    actions: [
      PrismButton(
        label: 'Cancel',
        tone: PrismButtonTone.outlined,
        onPressed: () => nav.pop(null),
      ),
      PrismButton(
        label: 'Leave links',
        tone: PrismButtonTone.outlined,
        onPressed: () => nav.pop(<String, String>{}),
      ),
      PrismButton(
        label: 'Download',
        tone: PrismButtonTone.filled,
        onPressed: () => nav.pop(fieldsKey.currentState?.choices ?? {}),
      ),
    ],
  );
}

class _RemoteImageImportFields extends StatefulWidget {
  const _RemoteImageImportFields({super.key, required this.imports});

  final List<RemoteMarkdownImageImport> imports;

  @override
  State<_RemoteImageImportFields> createState() =>
      _RemoteImageImportFieldsState();
}

class _RemoteImageImportFieldsState extends State<_RemoteImageImportFields> {
  late final Map<String, TextEditingController> _controllers;

  Map<String, String> get choices => {
    for (final entry in _controllers.entries)
      entry.key: entry.value.text.trim(),
  };

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final item in widget.imports)
        item.url: TextEditingController(text: item.suggestedTag),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in widget.imports) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 6),
          PrismTextField(
            controller: _controllers[item.url]!,
            hintText: 'Tag',
            textCapitalization: TextCapitalization.none,
          ),
          if (item != widget.imports.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}
