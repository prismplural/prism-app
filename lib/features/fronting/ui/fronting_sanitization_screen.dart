import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/providers/fronting_sanitization_providers.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_models.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_preview.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/ui/validation_issue_tile.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Settings / debug screen for scanning the fronting timeline for validation
/// issues and applying automated fixes.
class FrontingSanitizationScreen extends ConsumerStatefulWidget {
  const FrontingSanitizationScreen({super.key});

  @override
  ConsumerState<FrontingSanitizationScreen> createState() =>
      _FrontingSanitizationScreenState();
}

class _FrontingSanitizationScreenState
    extends ConsumerState<FrontingSanitizationScreen> {
  List<FrontingValidationIssue>? _issues; // null = not yet scanned
  bool _scanning = false;
  int _fixedCount = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(
        title: 'Timeline Sanitization',
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_scanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning timeline…'),
          ],
        ),
      );
    }

    if (_issues == null) {
      return _buildInitialState(theme);
    }

    if (_issues!.isEmpty) {
      return _buildCleanState(theme);
    }

    return _buildResultsList(theme);
  }

  // ── Initial (not yet scanned) ─────────────────────────────────────────────

  Widget _buildInitialState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.healthAndSafetyOutlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Timeline Sanitization',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan your fronting history for overlapping, '
              'duplicate, or invalid sessions, then apply '
              'automatic fixes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PrismButton(
              icon: AppIcons.search,
              label: 'Scan Timeline',
              onPressed: _scan,
              tone: PrismButtonTone.filled,
            ),
          ],
        ),
      ),
    );
  }

  // ── Clean (no issues found) ───────────────────────────────────────────────

  Widget _buildCleanState(ThemeData theme) {
    return Column(
      children: [
        if (_fixedCount > 0) _buildFixedBanner(theme),
        Expanded(
          child: EmptyState(
            icon: Icon(AppIcons.checkCircleOutline),
            iconColor: Colors.green,
            title: 'Timeline looks clean!',
            subtitle: 'No overlaps, duplicates, or invalid sessions found.',
            actionLabel: 'Scan Again',
            actionIcon: AppIcons.refresh,
            onAction: _scan,
          ),
        ),
      ],
    );
  }

  // ── Results list ──────────────────────────────────────────────────────────

  Widget _buildResultsList(ThemeData theme) {
    final issues = _issues!;
    // Group by issue type
    final grouped = <FrontingIssueType, List<FrontingValidationIssue>>{};
    for (final issue in issues) {
      grouped.putIfAbsent(issue.type, () => []).add(issue);
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (_fixedCount > 0) _buildFixedBanner(theme),
              _buildSummaryBanner(theme, issues.length),
            ],
          ),
        ),
        for (final entry in grouped.entries) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(type: entry.key),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: entry.value.length,
              itemBuilder: (context, index) {
                final issue = entry.value[index];
                return ValidationIssueTile(
                  issue: issue,
                  onTap: () => _showFixOptions(issue),
                );
              },
            ),
          ),
        ],
        // Re-scan button + bottom padding
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              24,
              16,
              NavBarInset.of(context) + 16,
            ),
            child: PrismButton(
              icon: AppIcons.refresh,
              label: 'Scan Again',
              onPressed: _scan,
              tone: PrismButtonTone.outlined,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBanner(ThemeData theme, int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(AppIcons.warningAmber, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Found $count ${count == 1 ? 'issue' : 'issues'} in your timeline.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedBanner(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.checkCircle, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$_fixedCount ${_fixedCount == 1 ? 'fix' : 'fixes'} applied successfully.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final service = ref.read(frontingSanitizerServiceProvider);
      final issues = await service.scan();
      if (mounted) {
        setState(() {
          _issues = issues;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        PrismToast.error(context, message: 'Scan failed: $e');
      }
    }
  }

  Future<void> _showFixOptions(FrontingValidationIssue issue) async {
    final service = ref.read(frontingSanitizerServiceProvider);
    List<FrontingFixPlan> plans;
    try {
      plans = await service.plansForIssue(issue);
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Could not load fix options: $e');
      }
      return;
    }

    if (!mounted) return;

    await PrismSheet.showFullScreen<void>(
      context: context,
      useRootNavigator: false,
      builder: (ctx, sc) => _FixOptionsSheet(
        issue: issue,
        plans: plans,
        service: service,
        onApplied: _applyFix,
        scrollController: sc,
      ),
    );
  }

  Future<void> _applyFix(FrontingFixPlan plan) async {
    final service = ref.read(frontingSanitizerServiceProvider);
    try {
      await service.applyPlan(plan);
      if (mounted) {
        setState(() => _fixedCount++);
      }
      await _scan(); // Re-scan after applying the fix
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Fix failed: $e');
      }
    }
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.type});

  final FrontingIssueType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        _label(type),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _label(FrontingIssueType type) {
    return switch (type) {
      FrontingIssueType.overlap => 'Overlapping Sessions',
      FrontingIssueType.gap => 'Gaps',
      FrontingIssueType.duplicate => 'Duplicates',
      FrontingIssueType.mergeableAdjacent => 'Mergeable Adjacent',
      FrontingIssueType.invalidRange => 'Invalid Ranges',
      FrontingIssueType.futureSession => 'Future Sessions',
    };
  }
}

// ── Fix options bottom sheet ─────────────────────────────────────────────────

class _FixOptionsSheet extends StatefulWidget {
  const _FixOptionsSheet({
    required this.issue,
    required this.plans,
    required this.service,
    required this.onApplied,
    this.scrollController,
  });

  final FrontingValidationIssue issue;
  final List<FrontingFixPlan> plans;
  final FrontingSanitizerService service;
  final Future<void> Function(FrontingFixPlan) onApplied;
  final ScrollController? scrollController;

  @override
  State<_FixOptionsSheet> createState() => _FixOptionsSheetState();
}

class _FixOptionsSheetState extends State<_FixOptionsSheet> {
  String? _expandedPlanId;
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Column(
      children: [
        const PrismSheetTopBar(title: 'Fix Options'),
        // Issue summary
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            widget.issue.summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const Divider(height: 1),
        // Plans list
        Expanded(
          child: widget.plans.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No automated fixes available for this issue.\n'
                      'Please review and resolve it manually.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  controller: widget.scrollController,
                  padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 16),
                  itemCount: widget.plans.length,
                  separatorBuilder: (context, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final plan = widget.plans[index];
                    return _PlanCard(
                      plan: plan,
                      preview: widget.service.buildPreview(plan),
                      isExpanded: _expandedPlanId == plan.id,
                      applying: _applying,
                      onTogglePreview: () {
                        setState(() {
                          _expandedPlanId =
                              _expandedPlanId == plan.id ? null : plan.id;
                        });
                      },
                      onApply: () => _apply(plan),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _apply(FrontingFixPlan plan) async {
    setState(() => _applying = true);
    try {
      await widget.onApplied(plan);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _applying = false);
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.preview,
    required this.isExpanded,
    required this.applying,
    required this.onTogglePreview,
    required this.onApply,
  });

  final FrontingFixPlan plan;
  final FrontingFixPreview preview;
  final bool isExpanded;
  final bool applying;
  final VoidCallback onTogglePreview;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan title
            Text(
              plan.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            // Plan description
            Text(
              plan.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            // Expanded preview
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (preview.bulletPoints.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final bullet in preview.bulletPoints)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  bullet,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Actions
            Row(
              children: [
                PrismButton(
                  label: isExpanded ? 'Hide Preview' : 'Preview',
                  onPressed: onTogglePreview,
                  enabled: !applying,
                  tone: PrismButtonTone.subtle,
                  density: PrismControlDensity.compact,
                ),
                const Spacer(),
                PrismButton(
                  label: 'Apply',
                  onPressed: onApply,
                  enabled: !applying,
                  isLoading: applying,
                  tone: PrismButtonTone.filled,
                  density: PrismControlDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
