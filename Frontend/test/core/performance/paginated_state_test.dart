import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/core/performance/paginated_state.dart';

void main() {
  group('PaginatedState', () {
    test('initial state has correct defaults', () {
      const state = PaginatedState<int>();

      expect(state.items, isEmpty);
      expect(state.isLoadingInitial, isTrue);
      expect(state.isLoadingMore, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.currentPage, equals(1));
      expect(state.error, isNull);
    });

    test('copyWith updates fields correctly', () {
      const state = PaginatedState<int>();

      final updated = state.copyWith(
        items: const [1, 2, 3],
        isLoadingInitial: false,
        hasMore: false,
        currentPage: 2,
      );

      expect(updated.items, equals([1, 2, 3]));
      expect(updated.isLoadingInitial, isFalse);
      expect(updated.hasMore, isFalse);
      expect(updated.currentPage, equals(2));
      expect(updated.isLoadingMore, isFalse);
      expect(updated.error, isNull);
    });
  });

  group('PaginatedNotifier', () {
    test('loads initial page on build', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = _TestPaginatedNotifier(
        Dio(),
        pageSize: 2,
      );

      final provider = NotifierProvider<_TestPaginatedNotifier, PaginatedState<int>>(
        () => notifier,
      );

      container.listen(provider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(provider);
      expect(state.items, equals([0, 1]));
      expect(state.isLoadingInitial, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.currentPage, equals(2));
    });
  });
}

class _TestPaginatedNotifier extends PaginatedNotifier<int> {
  final int pageSize;

  _TestPaginatedNotifier(super.dio, {required this.pageSize});

  @override
  Future<List<int>> fetchItems(int page, CancelToken cancelToken) async {
    final start = (page - 1) * pageSize;
    return List.generate(pageSize, (i) => start + i);
  }
}