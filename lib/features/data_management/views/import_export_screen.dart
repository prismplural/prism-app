import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'data_export_sheet.dart';
import 'data_import_sheet.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Main import/export screen with list of options.
class ImportExportScreen extends ConsumerWidget {
  const ImportExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.dataManagementImportExportTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          PrismSection(
            title: context.l10n.dataManagementExportSectionTitle,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSettingsRow(
                icon: AppIcons.uploadOutlined,
                iconColor: Colors.blue,
                title: context.l10n.dataManagementExportRowTitle,
                subtitle: context.l10n.dataManagementExportRowSubtitle,
                onTap: () => _showExportSheet(context),
              ),
            ),
          ),
          PrismSection(
            title: context.l10n.dataManagementImportSectionTitle,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: PrismSettingsRow(
                icon: AppIcons.downloadOutlined,
                iconColor: Colors.green,
                title: context.l10n.dataManagementImportRowTitle,
                subtitle: context.l10n.dataManagementImportRowSubtitle,
                onTap: () => _showImportSheet(context),
              ),
            ),
          ),
          PrismSection(
            title: context.l10n.dataManagementImportFromOtherApps,
            child: PrismSectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  PrismSettingsRow(
                    icon: AppIcons.cloudSync,
                    iconColor: Colors.deepPurple,
                    title: context.l10n.pluralkitTitle,
                    subtitle: context.l10n.dataManagementPluralKitRowSubtitle,
                    onTap: () => context.push(AppRoutePaths.settingsPluralkit),
                  ),
                  const Divider(height: 1, indent: 60, endIndent: 12),
                  PrismSettingsRow(
                    icon: AppIcons.swapHoriz,
                    iconColor: Colors.purple,
                    title: context.l10n.dataManagementSimplyPluralRowTitle,
                    subtitle: context.l10n.dataManagementSimplyPluralRowSubtitle,
                    onTap: () => context.push(AppRoutePaths.settingsMigration),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, sc) => DataExportSheet(scrollController: sc),
    );
  }

  void _showImportSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, sc) => DataImportSheet(scrollController: sc),
    );
  }
}
