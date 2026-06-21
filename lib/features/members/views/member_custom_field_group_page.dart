import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/group_field_widgets.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

class MemberCustomFieldGroupPage extends ConsumerWidget {
  const MemberCustomFieldGroupPage({
    super.key,
    required this.memberId,
    required this.fieldId,
  });

  final String memberId;
  final String fieldId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));
    final fieldAsync = ref.watch(customFieldByIdProvider(fieldId));

    return memberAsync.when(
      loading: _loadingScaffold,
      error: (error, _) => _messageScaffold(context, '$error'),
      data: (member) {
        if (member == null || member.isDeleted) {
          return _messageScaffold(
            context,
            context.l10n.settingsCustomFieldNotFound,
          );
        }
        return fieldAsync.when(
          loading: _loadingScaffold,
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
            );
          },
        );
      },
    );
  }

  Widget _loadingScaffold() {
    return const PrismPageScaffold(
      topBar: PrismTopBar(title: ''),
      body: PrismLoadingState(),
    );
  }

  Widget _messageScaffold(BuildContext context, String message) {
    return PrismPageScaffold(
      topBar: const PrismTopBar(title: ''),
      body: Center(child: Text(message)),
    );
  }
}

class _MemberCustomFieldGroupPageBody extends StatelessWidget {
  const _MemberCustomFieldGroupPageBody({
    required this.memberId,
    required this.field,
  });

  final String memberId;
  final CustomField field;

  @override
  Widget build(BuildContext context) {
    final title = _groupDisplayName(context, field);
    return PrismPageScaffold(
      topBar: PrismTopBar(title: title),
      bodyPadding: EdgeInsets.zero,
      body: Builder(
        builder: (context) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            NavBarInset.of(context) + 32,
          ),
          child: CustomFieldGroupPageContent(field: field, memberId: memberId),
        ),
      ),
    );
  }
}

String _groupDisplayName(BuildContext context, CustomField field) {
  final trimmed = field.name.trim();
  if (trimmed.isNotEmpty) return trimmed;
  return context.l10n.customFieldGroupUntitledFallback;
}
