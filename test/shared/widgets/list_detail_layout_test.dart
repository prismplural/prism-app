import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';

/// Pumps a [ListDetailLayout] inside a fixed-size window so the LayoutBuilder
/// resolves against a known content width.
Future<void> _pumpAt(
  WidgetTester tester,
  double width, {
  double height = 800,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListDetailLayout(
          // Expanding boxes so the pane sizes can be measured directly via key.
          list: (context, isWide) => SizedBox.expand(
            key: const Key('list-pane'),
            child: Center(child: Text(isWide ? 'list-wide' : 'list-narrow')),
          ),
          detail: (context) => const SizedBox.expand(
            key: Key('detail-pane'),
            child: Center(child: Text('detail-pane-content')),
          ),
        ),
      ),
    ),
  );
}

// Ordinary local identity deliberately exposes ancestor remounts. A GlobalKey
// here would reparent the list and hide the lifecycle regression being tested.
class _RetainedList extends StatefulWidget {
  const _RetainedList({super.key});

  @override
  State<_RetainedList> createState() => _RetainedListState();
}

class _RetainedListState extends State<_RetainedList> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: controller,
    itemExtent: 50,
    itemCount: 500,
    itemBuilder: (context, index) => SizedBox(
      key: ValueKey('retained-row-$index'),
      height: 50,
      child: Text('Row $index'),
    ),
  );
}

Future<void> _pumpEditableLayout(
  WidgetTester tester, {
  required VoidCallback? clearSelection,
  required VoidCallback ancestorEscape,
  required FocusNode firstDetail,
  required FocusNode secondDetail,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): ancestorEscape,
          },
          child: ListDetailLayout(
            onClearSelection: clearSelection,
            list: (_, _) => const _RetainedList(key: ValueKey('retained-list')),
            detail: (_) => Column(
              children: [
                TextButton(
                  key: const ValueKey('detail-first'),
                  focusNode: firstDetail,
                  onPressed: () {},
                  child: const Text('First detail action'),
                ),
                TextButton(
                  key: const ValueKey('detail-second'),
                  focusNode: secondDetail,
                  onPressed: () {},
                  child: const Text('Second detail action'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _wideControlViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.reset);
}

void main() {
  group('ListDetailLayout', () {
    testWidgets(
      'edit callback transitions retain list state position and anchor',
      (tester) async {
        _wideControlViewport(tester);
        final first = FocusNode();
        final second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        void clear() {}
        Future<void> pump(VoidCallback? callback) => _pumpEditableLayout(
          tester,
          clearSelection: callback,
          ancestorEscape: () {},
          firstDetail: first,
          secondDetail: second,
        );
        await pump(clear);
        final listState = tester.state<_RetainedListState>(
          find.byType(_RetainedList),
        );
        final position = listState.controller.position;
        listState.controller.jumpTo(15000);
        await tester.pumpAndSettle();
        final anchor = find.byKey(const ValueKey('retained-row-301'));
        expect(anchor, findsOneWidget);
        final anchorY = tester.getTopLeft(anchor).dy;

        for (final callback in <VoidCallback?>[null, clear]) {
          await pump(callback);
          final current = tester.state<_RetainedListState>(
            find.byType(_RetainedList),
          );
          expect(
            current,
            same(listState),
            reason: 'edit mode must not remount the list',
          );
          expect(current.controller.position, same(position));
          expect(anchor, findsOneWidget);
          expect(tester.getTopLeft(anchor).dy, closeTo(anchorY, 0.1));
        }
      },
    );

    testWidgets(
      'disabled clear passes Escape to ancestor and disables pane taps',
      (tester) async {
        _wideControlViewport(tester);
        final first = FocusNode();
        final second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        var clears = 0;
        var ancestorEscapes = 0;
        void clear() => clears++;
        Future<void> pump(VoidCallback? callback) => _pumpEditableLayout(
          tester,
          clearSelection: callback,
          ancestorEscape: () => ancestorEscapes++,
          firstDetail: first,
          secondDetail: second,
        );
        await pump(clear);
        first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(clears, 1);
        expect(ancestorEscapes, 0);

        await pump(null);
        first.requestFocus();
        await tester.pump();
        final listTap = find
            .ancestor(
              of: find.byType(_RetainedList),
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(tester.widget<GestureDetector>(listTap).onTap, isNull);
        final controls = ListDetailPaneControls.maybeOf(
          tester.element(find.byKey(const ValueKey('detail-first'))),
        );
        expect(controls, isNotNull);
        expect(controls!.clearSelection, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(clears, 1);
        expect(
          ancestorEscapes,
          1,
          reason: 'disabled Escape must not be consumed',
        );

        await pump(clear);
        first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(clears, 2);
        expect(ancestorEscapes, 1);
      },
    );

    testWidgets(
      'edit callback transitions preserve detail focus and adjacent Tab order',
      (tester) async {
        _wideControlViewport(tester);
        final first = FocusNode();
        final second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        void clear() {}
        Future<void> pump(VoidCallback? callback) => _pumpEditableLayout(
          tester,
          clearSelection: callback,
          ancestorEscape: () {},
          firstDetail: first,
          secondDetail: second,
        );
        await pump(clear);
        first.requestFocus();
        await tester.pump();
        for (final callback in <VoidCallback?>[clear, null, clear]) {
          await pump(callback);
          expect(
            FocusManager.instance.primaryFocus,
            same(first),
            reason: 'changing editor mode must not steal detail focus',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(FocusManager.instance.primaryFocus, same(second));
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(FocusManager.instance.primaryFocus, same(first));
        }
      },
    );

    testWidgets('initial disabled clear has no invisible stop in full Tab cycle', (
      tester,
    ) async {
      _wideControlViewport(tester);
      final first = FocusNode(debugLabel: 'first detail action');
      final second = FocusNode(debugLabel: 'second detail action');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await _pumpEditableLayout(
        tester,
        clearSelection: null,
        ancestorEscape: () {},
        firstDetail: first,
        secondDetail: second,
      );
      first.requestFocus();
      await tester.pump();
      // This fixture's list contains only Text rows. Scrollable/ScrollView do
      // not add a Focus widget in the pinned Flutter SDK. Capture actual route
      // traversal nodes in the failure, rather than assuming wrapping shortcuts
      // and route/group focus scopes are themselves traversal stops.
      final traversable = FocusScope.of(
        first.context!,
      ).traversalDescendants.toList();
      final focusTree = traversable
          .map((node) => node.toStringShort())
          .join(', ');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(second));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(first),
        reason:
            'forward wrap must skip invisible layout focus; nodes: $focusTree',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(second),
        reason:
            'reverse wrap must skip invisible layout focus; nodes: $focusTree',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(first));
      expect(traversable, unorderedEquals([first, second]));
    });

    testWidgets('shows only the list below the breakpoint', (tester) async {
      await _pumpAt(tester, PrismTokens.listDetailBreakpoint - 1);

      expect(find.text('list-narrow'), findsOneWidget);
      expect(find.text('list-wide'), findsNothing);
      expect(find.byKey(const Key('detail-pane')), findsNothing);
    });

    testWidgets('shows list + detail side by side at the breakpoint', (
      tester,
    ) async {
      await _pumpAt(tester, PrismTokens.listDetailBreakpoint);

      expect(find.text('list-wide'), findsOneWidget);
      expect(find.byKey(const Key('detail-pane')), findsOneWidget);
      expect(find.text('list-narrow'), findsNothing);
    });

    testWidgets('uses the wide pane width in the wide tier', (tester) async {
      // Just inside the two-pane range but below the extra-wide breakpoint.
      await _pumpAt(tester, PrismTokens.listDetailBreakpointXWide - 1);

      final paneWidth = tester
          .getSize(find.byKey(const Key('list-pane')))
          .width;
      expect(paneWidth, PrismTokens.listPaneWidth);
    });

    testWidgets('steps up to the extra-wide pane width past its breakpoint', (
      tester,
    ) async {
      await _pumpAt(tester, 1600);

      final paneWidth = tester
          .getSize(find.byKey(const Key('list-pane')))
          .width;
      expect(paneWidth, PrismTokens.listPaneWidthXWide);
    });

    testWidgets('passes the active tier to the list builder', (tester) async {
      final reported = <bool>[];

      Future<void> pump(double width) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListDetailLayout(
                list: (context, isWide) {
                  reported.add(isWide);
                  return const SizedBox.shrink();
                },
                detail: (context) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
      }

      await pump(PrismTokens.listDetailBreakpoint - 1);
      expect(reported.last, isFalse);

      await pump(PrismTokens.listDetailBreakpoint);
      expect(reported.last, isTrue);
    });
  });
}
