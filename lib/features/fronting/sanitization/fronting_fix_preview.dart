import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_models.dart';

class FrontingFixPreview {
  final FrontingFixPlan plan;
  final String summary;
  final List<String> bulletPoints;

  const FrontingFixPreview({
    required this.plan,
    required this.summary,
    required this.bulletPoints,
  });
}
