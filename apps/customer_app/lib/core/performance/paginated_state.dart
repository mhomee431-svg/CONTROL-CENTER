import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_error_handler.dart';

class PaginatedState<T> {
  final List<T> items;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;
  final ApiException? error;

  const PaginatedState({
    this.items = const [],
    this.isLoadingInitial = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
  });

  PaginatedState<T> copyWith({
    List<T>? items,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
    ApiException? error,
  }) {
    return PaginatedState<T>(
      items: items ?? this.items,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

/// Generic AutoDispose Paginated Controller with Cancellation Support
abstract class PaginatedNotifier<T> extends Notifier<PaginatedState<T>> {
  final Dio dio;
  CancelToken? _cancelToken;

  PaginatedNotifier(this.dio);

  @override
  PaginatedState<T> build() {
    ref.onDispose(() {
      _cancelToken?.cancel('Controller disposed');
    });
    Future.microtask(fetchNextPage);
    return PaginatedState<T>();
  }

  Future<List<T>> fetchItems(int page, CancelToken cancelToken);

  Future<void> fetchNextPage() async {
    if (state.isLoadingMore || (!state.isLoadingInitial && !state.hasMore)) return;

    if (state.currentPage == 1) {
      state = state.copyWith(isLoadingInitial: true, error: null);
    } else {
      state = state.copyWith(isLoadingMore: true, error: null);
    }

    _cancelToken?.cancel('New fetch requested');
    _cancelToken = CancelToken();

    try {
      final newItems = await fetchItems(state.currentPage, _cancelToken!);
      state = state.copyWith(
        items: [...state.items, ...newItems],
        isLoadingInitial: false,
        isLoadingMore: false,
        hasMore: newItems.isNotEmpty,
        currentPage: state.currentPage + 1,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      state = state.copyWith(
        isLoadingInitial: false,
        isLoadingMore: false,
        error: ApiException.fromDioError(e),
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingInitial: false,
        isLoadingMore: false,
        error: ApiException(type: ApiErrorType.unknown, message: e.toString()),
      );
    }
  }

  Future<void> refresh() async {
    _cancelToken?.cancel('Refresh initiated');
    state = PaginatedState<T>();
    await fetchNextPage();
  }
}