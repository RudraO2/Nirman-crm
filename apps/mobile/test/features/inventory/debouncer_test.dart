// Story 14.3-mobile — a burst of Realtime events collapses to one refetch.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/inventory/providers/debouncer.dart';

void main() {
  test('N rapid run() calls fire the action exactly once', () {
    fakeAsync((async) {
      final d = Debouncer(const Duration(milliseconds: 400));
      var calls = 0;
      // Simulate 5 realtime events landing 50ms apart (within the window).
      for (var i = 0; i < 5; i++) {
        d.run(() => calls++);
        async.elapse(const Duration(milliseconds: 50));
      }
      expect(calls, 0, reason: 'nothing fires while events keep arriving');
      async.elapse(const Duration(milliseconds: 400));
      expect(calls, 1, reason: 'only the final scheduled action runs');
      d.dispose();
    });
  });

  test('dispose cancels a pending action', () {
    fakeAsync((async) {
      final d = Debouncer(const Duration(milliseconds: 400));
      var calls = 0;
      d.run(() => calls++);
      d.dispose();
      async.elapse(const Duration(milliseconds: 500));
      expect(calls, 0);
    });
  });

  test('spaced-out calls each fire', () {
    fakeAsync((async) {
      final d = Debouncer(const Duration(milliseconds: 400));
      var calls = 0;
      d.run(() => calls++);
      async.elapse(const Duration(milliseconds: 400));
      d.run(() => calls++);
      async.elapse(const Duration(milliseconds: 400));
      expect(calls, 2);
      d.dispose();
    });
  });
}
