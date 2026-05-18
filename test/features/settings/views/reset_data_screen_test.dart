import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/providers/reset_data_provider.dart';
import 'package:prism_plurality/features/settings/views/reset_data_screen.dart';

void main() {
  test('all-data reset restart screen is skipped on Android', () {
    expect(
      shouldShowResetRestartScreenAfterSuccess(
        ResetCategory.all,
        isAndroid: true,
      ),
      isFalse,
    );
    expect(
      shouldShowResetRestartScreenAfterSuccess(
        ResetCategory.all,
        isAndroid: true,
        restartRequired: true,
      ),
      isTrue,
    );
    expect(
      shouldShowResetRestartScreenAfterSuccess(
        ResetCategory.all,
        isAndroid: false,
      ),
      isTrue,
    );
  });
}
