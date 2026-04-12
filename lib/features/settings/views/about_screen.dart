import 'package:flutter/material.dart';

import 'package:prism_plurality/features/settings/views/about_section.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.settingsAbout, showBackButton: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        child: const AboutSection(),
      ),
    );
  }
}
