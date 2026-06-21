import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_display.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

class MemberCustomFieldGroupPage extends ConsumerWidget {
  const MemberCustomFieldGroupPage({
    super.key,
    required this.memberId,
    required this.fieldId,
    this.showBackButton = true,
    this.onBack,
  });

  final String memberId;
  final String fieldId;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));
    final fieldAsync = ref.watch(customFieldByIdProvider(fieldId));

    return memberAsync.when(
      loading: () => _loadingScaffold(context),
      error: (error, _) => _messageScaffold(context, '$error'),
      data: (member) {
        if (member == null || member.isDeleted) {
          return _messageScaffold(
            context,
            context.l10n.settingsCustomFieldNotFound,
          );
        }
        return fieldAsync.when(
          loading: () => _loadingScaffold(context),
          error: (error, _) => _messageScaffold(context, '$error'),
          data: (field) {
            if (field == null || field.fieldTypeId != kGroupFieldTypeId) {
              return _messageScaffold(
                context,
                context.l10n.settingsCustomFieldNotFound,
              );
            }
            return _MemberCustomFieldGroupPageBody(
              memberId: memberId,
              field: field,
              showBackButton: showBackButton,
              onBack: onBack,
            );
          },
        );
      },
    );
  }

  Widget _loadingScaffold(BuildContext context) {
    return PrismPageScaffold(
      topBar: _topBar(context, ''),
      body: const PrismLoadingState(),
    );
  }

  Widget _messageScaffold(BuildContext context, String message) {
    return PrismPageScaffold(
      topBar: _topBar(context, ''),
      body: Center(child: Text(message)),
    );
  }

  PreferredSizeWidget _topBar(BuildContext context, String title) {
    final back = onBack;
    return PrismTopBar(
      title: title,
      showBackButton: showBackButton && back == null,
      leading: back == null
          ? null
          : PrismTopBarAction(
              icon: AppIcons.arrowBack,
              tooltip: context.l10n.back,
              onPressed: back,
            ),
    );
  }
}

class _MemberCustomFieldGroupPageBody extends StatelessWidget {
  const _MemberCustomFieldGroupPageBody({
    required this.memberId,
    required this.field,
    required this.showBackButton,
    required this.onBack,
  });

  final String memberId;
  final CustomField field;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final title = _groupDisplayName(context, field);
    return PrismPageScaffold(
      topBar: _topBar(context, title),
      bodyPadding: EdgeInsets.zero,
      body: Builder(
        builder: (context) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            NavBarInset.of(context) + 32,
          ),
          child: _MemberCustomFieldGroupPageContent(
            field: field,
            memberId: memberId,
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _topBar(BuildContext context, String title) {
    final back = onBack;
    return PrismTopBar(
      title: title,
      showBackButton: showBackButton && back == null,
      leading: back == null
          ? null
          : PrismTopBarAction(
              icon: AppIcons.arrowBack,
              tooltip: context.l10n.back,
              onPressed: back,
            ),
    );
  }
}

String _groupDisplayName(BuildContext context, CustomField field) {
  final trimmed = field.name.trim();
  if (trimmed.isNotEmpty) return trimmed;
  return context.l10n.customFieldGroupUntitledFallback;
}

class _MemberCustomFieldGroupPageContent extends ConsumerWidget {
  const _MemberCustomFieldGroupPageContent({
    required this.field,
    required this.memberId,
  });

  final CustomField field;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(customFieldsProvider);
    final valuesAsync = ref.watch(memberCustomFieldValuesProvider(memberId));

    return fieldsAsync.when(
      loading: () => const PrismLoadingState(),
      error: (error, _) =>
          Center(child: Text(context.l10n.settingsCustomFieldsError('$error'))),
      data: (fields) => valuesAsync.when(
        loading: () => const PrismLoadingState(),
        error: (error, _) => Center(
          child: Text(context.l10n.settingsCustomFieldsError('$error')),
        ),
        data: (values) {
          final valuesByFieldId = {for (final v in values) v.customFieldId: v};
          final hasRenderableChild = fields.any(
            (child) =>
                child.parentFieldId == field.id &&
                (valuesByFieldId[child.id]?.value.isNotEmpty ?? false),
          );
          if (!hasRenderableChild) {
            return EmptyState(
              icon: Icon(AppIcons.folderOutlined),
              title: context.l10n.customFieldGroupChildrenEmptyTitle,
              subtitle: context.l10n.customFieldGroupChildrenEmptySubtitle,
            );
          }
          return CustomFieldsDisplay(
            memberId: memberId,
            parentFieldId: field.id,
          );
        },
      ),
    );
  }
}
