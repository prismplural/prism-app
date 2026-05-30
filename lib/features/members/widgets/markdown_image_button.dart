import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/services/bio_image_processor.dart';
import 'package:prism_plurality/features/members/widgets/image_library_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/remote_image_fetcher.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// A dropdown button that inserts an image reference (`![](tag)`) into [controller]
/// at the cursor, from one of five sources: Prism library, camera, photo
/// library, file, or URL.
///
/// Newly-added images (camera/file/URL) are *staged* in the editor's
/// session-scoped [bioImageProcessorProvider] (keyed by [sessionId]); the host
/// surface must call `commitStaged()` on that session when it saves. The
/// session is discarded automatically when the editor closes. The "Prism
/// library" source inserts an already-committed tag and needs no commit.
///
/// Drop this anywhere a markdown text field is edited — bios, notes, custom
/// fields, group descriptions — passing the host editor's [sessionId].
class MarkdownImageButton extends ConsumerStatefulWidget {
  const MarkdownImageButton({
    super.key,
    required this.controller,
    required this.sessionId,
  });

  /// The text field whose content receives the inserted `![](tag)` reference.
  final TextEditingController controller;

  /// The host editor's processor session id (see [bioImageProcessorProvider]).
  /// The host keeps this session alive for its lifetime, so reads here are safe.
  final String sessionId;

  @override
  ConsumerState<MarkdownImageButton> createState() =>
      _MarkdownImageButtonState();
}

class _MarkdownImageButtonState extends ConsumerState<MarkdownImageButton> {
  static const _uuid = Uuid();

  // Owned by the State (not created per-dialog) and disposed only when this
  // widget tears down. Disposing a dialog's TextEditingController synchronously
  // right after the dialog future resolves crashes: the route is still playing
  // its exit transition, and the dismissing keyboard rebuilds the still-mounted
  // TextField, whose internal AnimatedBuilder(Listenable.merge([focusNode,
  // controller])) re-subscribes to the now-disposed controller. Reusing
  // State-scoped controllers (cleared on each open) sidesteps that race.
  final _tagController = TextEditingController();
  final _altController = TextEditingController();
  final _urlController = TextEditingController();

  BioImageProcessor get _processor =>
      ref.read(bioImageProcessorProvider(widget.sessionId));

  @override
  void dispose() {
    _tagController.dispose();
    _altController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing = ref.watch(bioImageProcessingStateProvider).status ==
        BioImageProcessingStatus.processing;

    final l10n = context.l10n;
    return PrismPopupMenu<_ImageSource>(
      icon: AppIcons.imageOutlined,
      tooltip: l10n.mediaAddImageTooltip,
      width: 210,
      preferredDirection: BlurPopupDirection.up,
      items: [
        PrismMenuItem(
          value: _ImageSource.prismLibrary,
          label: l10n.mediaSourcePrismLibrary,
          icon: AppIcons.photoLibrary,
        ),
        PrismMenuItem(
          value: _ImageSource.camera,
          label: l10n.mediaSourceCamera,
          icon: AppIcons.cameraAlt,
        ),
        PrismMenuItem(
          value: _ImageSource.photoLibrary,
          label: l10n.mediaSourcePhotoLibrary,
          icon: AppIcons.imageOutlined,
        ),
        PrismMenuItem(
          value: _ImageSource.file,
          label: l10n.mediaSourceFile,
          icon: AppIcons.fileUploadOutlined,
        ),
        PrismMenuItem(
          value: _ImageSource.url,
          label: l10n.mediaSourceUrl,
          icon: AppIcons.link,
        ),
      ],
      onSelected: isProcessing ? null : _handleSource,
    );
  }

  Future<void> _handleSource(_ImageSource source) async {
    switch (source) {
      case _ImageSource.camera:
        await _addFromPicker(ImageSource.camera);
      case _ImageSource.photoLibrary:
        await _addFromPicker(ImageSource.gallery);
      case _ImageSource.file:
        await _addFromPicker(ImageSource.gallery); // closest cross-platform
      case _ImageSource.url:
        await _addFromUrl();
      case _ImageSource.prismLibrary:
        await _insertFromLibrary();
    }
  }

  Future<void> _addFromPicker(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    await _stageAndInsert(bytes);
  }

  Future<void> _addFromUrl() async {
    final nav = Navigator.of(context, rootNavigator: true);
    _urlController.clear();
    final l10n = context.l10n;
    final url = await PrismDialog.show<String>(
      context: context,
      title: l10n.mediaImageUrlTitle,
      builder: (_) => PrismTextField(
        controller: _urlController,
        autofocus: true,
        hintText: l10n.mediaImageUrlHint,
        keyboardType: TextInputType.url,
      ),
      actions: [
        PrismButton(
          label: l10n.cancel,
          tone: PrismButtonTone.outlined,
          onPressed: () => nav.pop(null),
        ),
        PrismButton(
          label: l10n.mediaFetchButton,
          tone: PrismButtonTone.filled,
          onPressed: () => nav.pop(_urlController.text.trim()),
        ),
      ],
    );

    if (url == null || url.isEmpty || !mounted) return;
    final bytes = await fetchRemoteImageBytes(url);
    if (bytes == null) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.mediaFetchImageFailed);
      }
      return;
    }
    if (!mounted) return;
    await _stageAndInsert(bytes);
  }

  Future<void> _insertFromLibrary() async {
    final tag = await showImageLibraryPicker(context, ref);
    if (tag != null && mounted) _insertAtCursor('![]($tag)');
  }

  Future<void> _stageAndInsert(Uint8List bytes) async {
    final result = await _showTagDialog(bytes);
    if (result == null || !mounted) return;

    final notifier = ref.read(bioImageProcessingStateProvider.notifier);
    notifier.setProcessing(1);
    try {
      final tagInput = result.tag.isNotEmpty
          ? result.tag
          : 'img-${_uuid.v4().substring(0, 8)}';
      final tag = await _processor.stageDeviceImage(
        bytes,
        tagInput,
        altText: result.altText,
      );
      if (!mounted) return;
      final alt = result.altText ?? '';
      _insertAtCursor(alt.isEmpty ? '![]($tag)' : '![$alt]($tag)');
      notifier.incrementCompleted();
    } catch (e) {
      if (!mounted) return;
      notifier.setError(e.toString());
      PrismToast.error(context, message: e.toString());
    }
  }

  void _insertAtCursor(String markdown) {
    final c = widget.controller;
    final sel = c.selection;
    final text = c.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    c.value = c.value.copyWith(
      text: text.replaceRange(start, end, markdown),
      selection: TextSelection.collapsed(offset: start + markdown.length),
    );
  }

  Future<({String tag, String? altText})?> _showTagDialog(
    Uint8List imageBytes,
  ) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;
    _tagController.clear();
    _altController.clear();
    final result = await PrismDialog.show<({String tag, String? altText})>(
      context: context,
      title: l10n.mediaAddImageToLibraryTitle,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: Image.memory(imageBytes, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 16),
          PrismTextField(
            controller: _tagController,
            autofocus: true,
            hintText: l10n.mediaTagFieldHint,
            textCapitalization: TextCapitalization.none,
          ),
          const SizedBox(height: 8),
          PrismTextField(
            controller: _altController,
            hintText: l10n.mediaAltTextFieldHint,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
      actions: [
        PrismButton(
          label: l10n.cancel,
          tone: PrismButtonTone.outlined,
          onPressed: () => nav.pop(null),
        ),
        PrismButton(
          label: l10n.add,
          tone: PrismButtonTone.filled,
          onPressed: () => nav.pop((
            tag: _tagController.text.trim(),
            altText: _altController.text.trim().isEmpty
                ? null
                : _altController.text.trim(),
          )),
        ),
      ],
    );
    return result;
  }
}

enum _ImageSource { prismLibrary, camera, photoLibrary, file, url }
