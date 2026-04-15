import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/widgets/floating_nav_bar_backdrop.dart';

void main() {
  testWidgets('absorbs taps in the footer strip', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));

    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tapCount++,
                  child: const SizedBox.expand(),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FloatingNavBarBackdrop(height: 120, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(200, 760));
    await tester.pump();
    expect(tapCount, 0);

    await tester.tapAt(const Offset(200, 100));
    await tester.pump();
    expect(tapCount, 1);
  });
}
