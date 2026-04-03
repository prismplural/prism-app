import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/error_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Displays the in-memory error history with severity-coded entries.
class ErrorHistoryScreen extends ConsumerWidget {
  const ErrorHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errors = ref.watch(errorHistoryProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Error History',
        showBackButton: true,
        trailing: errors.isNotEmpty
            ? PrismTopBarAction(
                icon: AppIcons.deleteOutline,
                tooltip: 'Clear History',
                onPressed: () {
                  ref.read(errorHistoryProvider.notifier).clear();
                },
              )
            : null,
      ),
      bodyPadding: EdgeInsets.zero,
      body: errors.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
              itemCount: errors.length,
              itemBuilder: (context, index) {
                // Show newest first.
                final error = errors[errors.length - 1 - index];
                return _ErrorTile(error: error);
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.duotoneSuccess,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No errors recorded',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Errors will appear here when they occur',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorTile extends StatefulWidget {
  const _ErrorTile({required this.error});

  final AppError error;

  @override
  State<_ErrorTile> createState() => _ErrorTileState();
}

class _ErrorTileState extends State<_ErrorTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, h:mm:ss a');

    return Column(
      children: [
        ListTile(
          leading: _severityIcon(widget.error.severity, theme),
          title: Text(
            widget.error.message,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? null : TextOverflow.ellipsis,
          ),
          subtitle: Text(
            dateFormat.format(widget.error.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(AppIcons.copy, size: 18),
                tooltip: 'Copy error details',
                onPressed: () => _copyError(context),
              ),
              if (widget.error.stackTrace != null)
                Icon(
                  _expanded ? AppIcons.expandLess : AppIcons.expandMore,
                  size: 20,
                ),
            ],
          ),
          onTap: widget.error.stackTrace != null
              ? () => setState(() => _expanded = !_expanded)
              : null,
        ),
        if (_expanded && widget.error.stackTrace != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              widget.error.stackTrace.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  void _copyError(BuildContext context) {
    final buffer = StringBuffer()
      ..writeln('[${widget.error.severity.name.toUpperCase()}]')
      ..writeln(widget.error.message)
      ..writeln(widget.error.timestamp.toIso8601String());

    if (widget.error.stackTrace != null) {
      buffer
        ..writeln()
        ..writeln('Stack trace:')
        ..writeln(widget.error.stackTrace);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    PrismToast.show(context, message: 'Error details copied');
  }

  Widget _severityIcon(ErrorSeverity severity, ThemeData theme) {
    switch (severity) {
      case ErrorSeverity.info:
        return Icon(AppIcons.infoOutline, color: Colors.blue);
      case ErrorSeverity.warning:
        return Icon(AppIcons.warningAmberRounded, color: Colors.orange);
      case ErrorSeverity.error:
        return Icon(AppIcons.errorOutline, color: Colors.red);
      case ErrorSeverity.fatal:
        return Icon(AppIcons.dangerousOutlined, color: Colors.purple);
    }
  }
}
