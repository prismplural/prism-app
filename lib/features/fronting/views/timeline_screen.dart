import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_view.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(tabRetapProvider, (_, _) {
      ref.read(timelineJumpTargetProvider.notifier).jumpTo(DateTime.now());
    });

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.navTimeline),
      bodyPadding: EdgeInsets.zero,
      body: Padding(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        child: const TimelineView(),
      ),
    );
  }
}
