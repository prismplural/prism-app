import 'package:prism_plurality/domain/preferences/fronting_terms.dart';

/// Complete synthetic bundle for persistence/codec tests.
///
/// Product preset wording belongs to localization resources, so domain tests
/// use stable field-name values instead of depending on a locale.
FrontingTermBundle get testFrontingTermBundle =>
    FrontingTermBundle.tryDecode(<String, Object?>{
      for (final key in FrontingTermBundle.fieldKeys) key: 'test_$key',
    })!;
