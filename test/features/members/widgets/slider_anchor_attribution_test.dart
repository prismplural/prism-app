import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/members/widgets/slider_field_widgets.dart';

void main() {
  group('attributedSliderAnchorLabel', () {
    const withCenter = SliderConfig(
      mode: SliderMode.labeled,
      leftLabel: 'Low',
      centerLabel: 'Mid',
      rightLabel: 'High',
    );

    test('center label splits the range into equal thirds (1:1:1)', () {
      // Left owns 0–33⅓.
      expect(attributedSliderAnchorLabel(0, withCenter), 'Low');
      expect(attributedSliderAnchorLabel(30, withCenter), 'Low');
      expect(attributedSliderAnchorLabel(33, withCenter), 'Low');
      // Center owns 33⅓–66⅔.
      expect(attributedSliderAnchorLabel(34, withCenter), 'Mid');
      expect(attributedSliderAnchorLabel(50, withCenter), 'Mid');
      expect(attributedSliderAnchorLabel(66, withCenter), 'Mid');
      // Right owns 66⅔–100.
      expect(attributedSliderAnchorLabel(67, withCenter), 'High');
      expect(attributedSliderAnchorLabel(70, withCenter), 'High');
      expect(attributedSliderAnchorLabel(100, withCenter), 'High');
    });

    test('regression: 30 and 70 are no longer attributed to center', () {
      // Under the old nearest-anchor logic (anchors at 0/50/100) these fell to
      // the center label because crossovers sat at 25 and 75 (a 1:2:1 split).
      expect(attributedSliderAnchorLabel(30, withCenter), 'Low');
      expect(attributedSliderAnchorLabel(70, withCenter), 'High');
    });

    test('without a center label the range splits in half (1:1)', () {
      const noCenter = SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Low',
        rightLabel: 'High',
      );
      expect(attributedSliderAnchorLabel(0, noCenter), 'Low');
      expect(attributedSliderAnchorLabel(49, noCenter), 'Low');
      expect(attributedSliderAnchorLabel(60, noCenter), 'High');
      expect(attributedSliderAnchorLabel(100, noCenter), 'High');
    });

    test('non-finite values return null instead of throwing', () {
      // Compact rows pass raw parsed values; legacy/bad sync data may be
      // NaN or infinity, and floor() throws on those.
      expect(attributedSliderAnchorLabel(double.nan, withCenter), isNull);
      expect(attributedSliderAnchorLabel(double.infinity, withCenter), isNull);
      expect(
        attributedSliderAnchorLabel(double.negativeInfinity, withCenter),
        isNull,
      );
    });

    test('returns null when the owning anchor has no label', () {
      const onlyCenter = SliderConfig(
        mode: SliderMode.labeled,
        centerLabel: 'Mid',
      );
      expect(attributedSliderAnchorLabel(10, onlyCenter), isNull);
      expect(attributedSliderAnchorLabel(50, onlyCenter), 'Mid');
      expect(attributedSliderAnchorLabel(90, onlyCenter), isNull);
    });
  });
}
