import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

extension SleepQualityL10n on SleepQuality {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    SleepQuality.unknown => l10n.sleepQualityNotRated,
    SleepQuality.veryPoor => l10n.sleepQualityVeryPoor,
    SleepQuality.poor => l10n.sleepQualityPoor,
    SleepQuality.fair => l10n.sleepQualityFair,
    SleepQuality.good => l10n.sleepQualityGood,
    SleepQuality.excellent => l10n.sleepQualityExcellent,
  };
}
