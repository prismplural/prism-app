import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'data_export_sheet.dart';
import 'data_import_sheet.dart';

/// Main import/export screen with list of options.
class ImportExportScreen extends ConsumerWidget {
  const ImportExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Import & Export', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          // Export section
          const _SectionHeader(title: 'Export'),
          ListTile(
            leading: const _IconCircle(
              icon: Icons.upload_outlined,
              color: Colors.blue,
            ),
            title: const Text('Export Data'),
            subtitle: Text(
              'Create a password-protected backup',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            onTap: () => _showExportSheet(context),
          ),

          // Import section
          const _SectionHeader(title: 'Import'),
          ListTile(
            leading: const _IconCircle(
              icon: Icons.download_outlined,
              color: Colors.green,
            ),
            title: const Text('Import Data'),
            subtitle: Text(
              'Restore data from a Prism export file (.json or .prism)',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            onTap: () => _showImportSheet(context),
          ),

          // Import from other apps
          const _SectionHeader(title: 'Import from Other Apps'),
          ListTile(
            leading: const _IconCircle(
              icon: Icons.cloud_sync,
              color: Colors.deepPurple,
            ),
            title: const Text('PluralKit'),
            subtitle: Text(
              'Import members & fronting via API token',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            onTap: () => context.push(AppRoutePaths.settingsPluralkit),
          ),
          ListTile(
            leading: const _IconCircle(
              icon: Icons.swap_horiz,
              color: Colors.purple,
            ),
            title: const Text('Simply Plural'),
            subtitle: Text(
              'Import from a Simply Plural export file',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            onTap: () => context.push(AppRoutePaths.settingsMigration),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}
