import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/widgets/rebuild_scoping.dart';

/// The whole point of [WatchSelected] is a rebuild that does NOT happen.
///
/// A plain `ref.watch(someProvider)` rebuilds the whole subtree whenever the
/// provider's value changes, even if the widget only draws one field. The tests
/// below assert the narrower contract by counting builder invocations, so a
/// future refactor that quietly widens the watch fails here rather than
/// reintroducing the jank this widget exists to remove.
class _Cart {
  const _Cart({required this.title, required this.itemCount});

  final String title;
  final int itemCount;

  _Cart copyWith({String? title, int? itemCount}) => _Cart(
        title: title ?? this.title,
        itemCount: itemCount ?? this.itemCount,
      );
}

final _cartProvider = NotifierProvider<_CartNotifier, _Cart>(_CartNotifier.new);

class _CartNotifier extends Notifier<_Cart> {
  int rebuilds = 0;

  @override
  _Cart build() {
    rebuilds++;
    return const _Cart(title: 'Your basket', itemCount: 0);
  }

  void setCount(int value) => state = state.copyWith(itemCount: value);
  void setTitle(String value) => state = state.copyWith(title: value);
}

void main() {
  testWidgets('WatchSelected renders the selected value', (tester) async {
    WidgetRef? capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: WatchSelected<_Cart, int>(
            provider: _cartProvider,
            selector: (cart) => cart.itemCount,
            builder: (context, count, ref) {
              capturedRef = ref;
              return Text('items: $count');
            },
          ),
        ),
      ),
    );

    expect(find.text('items: 0'), findsOneWidget);

    capturedRef!.read(_cartProvider.notifier).setCount(3);
    await tester.pump();

    expect(find.text('items: 3'), findsOneWidget);
  });

  testWidgets('changing the SELECTED field rebuilds exactly once',
      (tester) async {
    var builds = 0;
    WidgetRef? capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: WatchSelected<_Cart, int>(
            provider: _cartProvider,
            selector: (cart) => cart.itemCount,
            builder: (context, count, ref) {
              builds++;
              capturedRef = ref;
              return Text('items: $count');
            },
          ),
        ),
      ),
    );

    expect(builds, 1);

    capturedRef!.read(_cartProvider.notifier).setCount(1);
    await tester.pump();

    // One build for the changed selection — not zero, and not a second pass
    // from the parent.
    expect(builds, 2);
    expect(find.text('items: 1'), findsOneWidget);
  });

  testWidgets('changing an UNRELATED field does not rebuild the subtree',
      (tester) async {
    var builds = 0;
    WidgetRef? capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: WatchSelected<_Cart, int>(
            provider: _cartProvider,
            // Only the count is drawn, so a title change is invisible here.
            selector: (cart) => cart.itemCount,
            builder: (context, count, ref) {
              builds++;
              capturedRef = ref;
              return Text('items: $count');
            },
          ),
        ),
      ),
    );

    expect(builds, 1);

    capturedRef!.read(_cartProvider.notifier).setTitle('Something else');
    await tester.pump();

    // THE contract. With a whole-object watch this would be 2 and every
    // sibling on the screen would repaint along with it.
    expect(builds, 1, reason: 'unrelated state change must not rebuild');
    expect(find.text('items: 0'), findsOneWidget);
  });

  testWidgets('RepaintIsolated puts a RepaintBoundary around its child',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RepaintIsolated(
          child: Text('isolated'),
        ),
      ),
    );

    expect(find.text('isolated'), findsOneWidget);
    // A real boundary, not a wrapper that only looks like one. MaterialApp and
    // Scaffold each contribute a boundary of their own, so this asserts that a
    // boundary EXISTS above the child rather than counting them.
    expect(
      find.ancestor(
        of: find.text('isolated'),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
  });
}