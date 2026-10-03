import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';

class SleepFrontingInfoBanner extends StatefulWidget {
  const SleepFrontingInfoBanner({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<SleepFrontingInfoBanner> createState() =>
      _SleepFrontingInfoBannerState();
}

class _SleepFrontingInfoBannerState extends State<SleepFrontingInfoBanner> {
  static const _dismissedKey = 'prism.sleep.fronting_info_dismissed';
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _visible = !(prefs.getBool(_dismissedKey) ?? false));
      }
    } catch (_) {
      // An unavailable hint preference must not block sleep tracking.
    }
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissedKey, true);
    } catch (_) {
      // Keep the hint dismissed for this visit if persistence is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: InfoBanner(
        icon: AppIcons.bedtimeOutlined,
        iconColor: Theme.of(context).colorScheme.primary,
        title: l10n.sleepFrontingInfoTitle,
        message: l10n.sleepFrontingInfoBody,
        buttonText: l10n.sleepFrontingInfoAction,
        onButtonPressed: () {
          _dismiss();
          widget.onOpenSettings();
        },
        onDismiss: _dismiss,
        dismissLabel: l10n.dismiss,
        dismissTooltip: l10n.dismiss,
        actionsBelow: true,
      ),
    );
  }
}
