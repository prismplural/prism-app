import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/sleep_fronting_provider.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class SleepFrontingSetting extends ConsumerStatefulWidget {
  const SleepFrontingSetting({super.key});

  @override
  ConsumerState<SleepFrontingSetting> createState() =>
      _SleepFrontingSettingState();
}

class _SleepFrontingSettingState extends ConsumerState<SleepFrontingSetting> {
  bool _saving = false;

  Future<void> _set(bool value) async {
    setState(() => _saving = true);
    try {
      await ref.read(keepFrontingDuringSleepProvider.notifier).set(value);
    } catch (error) {
      if (mounted) PrismToast.error(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(keepFrontingDuringSleepProvider);
    final terms = watchFrontingTerms(context, ref);
    return PrismSwitchRow(
      icon: AppIcons.bedtimeOutlined,
      title: context.l10n.sleepKeepFrontersTitle(
        terms.activePluralLabel.toLowerCase(),
      ),
      subtitle: context.l10n.sleepKeepFrontersSubtitle,
      value: preference.value ?? false,
      enabled: preference.hasValue && !_saving,
      onChanged: _set,
    );
  }
}
