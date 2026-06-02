import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
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
  final refs = findRemoteMarkdownImageRefs(controller.text);
  if (refs.isEmpty) return true;

  final processor = ref.read(bioImageProcessorProvider(sessionId));
  final library = await readImageLibrarySnapshot(
    ref,
    useCachedValueOnError: true,
  );
  if (!context.mounted) return false;

  final imports = buildRemoteMarkdownImageImports(
    refs,
    unavailableTags: [
      ...library.map((a) => a.tag),
      ...processor.staged.map((s) => s.tag),
    ],
  );
  if (imports.isEmpty) return true;

  final choices = await _showRemoteImageImportPrompt(context, imports: imports);
  if (choices == null) return false;
  if (choices.isEmpty) return true;

  final notifier = ref.read(bioImageProcessingStateProvider.notifier);
  notifier.setProcessing(choices.length);

  final successes = <String, String>{};
  for (final entry in choices.entries) {
    final tag = BioImageProcessor.normalizeTag(entry.value);
    if (tag.isEmpty) continue;

    try {
      final stagedTag = await processor.stageUrlImage(entry.key, tag);
      successes[entry.key] = stagedTag;
      notifier.incrementCompleted();
    } catch (_) {}
  }

  if (successes.isEmpty) {
    notifier.setError('Could not fetch image');
    if (context.mounted) {
      PrismToast.error(context, message: 'Could not fetch image');
    }
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
