import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/performance/debouncer.dart';

void main() {
  test('Debouncer cancels rapid consecutive triggers and executes only once', () async {
    final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
    int executionCount = 0;

    debouncer.run(() => executionCount++);
    debouncer.run(() => executionCount++);
    debouncer.run(() => executionCount++);

    expect(executionCount, equals(0));

    await Future.delayed(const Duration(milliseconds: 150));
    expect(executionCount, equals(1));

    debouncer.dispose();
  });
}