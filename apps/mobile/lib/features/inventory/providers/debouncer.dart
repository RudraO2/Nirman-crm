// Story 14.3-mobile — collapse a burst of Realtime events into one refetch.
//
// The `units` Realtime channel can emit many row events in quick succession (a
// bulk grid regen, a cascade of releases). We don't want one RPC round-trip per
// event; [Debouncer.run] restarts a timer so only the final call within [duration]
// actually fires. Extracted + pure so it can be unit-tested with fakeAsync without
// a live Supabase connection.

import 'dart:async';

class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  /// Schedules [action], cancelling any pending one. N calls within [duration]
  /// collapse to a single [action] invocation.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
