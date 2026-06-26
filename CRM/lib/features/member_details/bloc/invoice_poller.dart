import 'dart:async';

/// Fires a fixed sequence of refresh ticks after a charge /
/// purchase so a webhook-delivered invoice shows up on its own.
///
/// The schedule is **dumb**: each offset is an absolute delay from
/// [start], the tick just fires, and there is no "did an invoice
/// arrive yet" check or early stop. The default beats are 5s, 10s,
/// 15s, 30s, 60s (every 5s for the first 15s, then 30s, then 60s —
/// five refreshes, window ends at 60s).
///
/// This is a **light client-side safety net**: the backend now
/// deterministically pulls the new invoice from Stripe right after the
/// op (the on-demand post-op fetch, with webhooks + the reconciler as
/// backstops), so the bill is in our DB within seconds — the poll just
/// re-renders the sections to pick it up. A long client window is no
/// longer needed, so it stays at 1 minute.
///
/// [start] **cancels any in-flight schedule first**, so a second
/// charge mid-window simply resets the timer — there is never more
/// than one polling sequence running. [cancel] stops everything
/// (the bloc calls it from `close()`).
///
/// The schedule is injectable so tests can drive it with millisecond
/// offsets instead of waiting a real minute.
class InvoicePoller {
  /// Absolute offsets from [start] at which a tick fires.
  static const List<Duration> defaultSchedule = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final List<Duration> _schedule;
  final List<Timer> _timers = [];

  InvoicePoller({List<Duration> schedule = defaultSchedule})
      : _schedule = schedule;

  /// Begins (or restarts) the schedule. Cancels any pending ticks
  /// first so only one sequence is ever live, then fires [onTick]
  /// once at each scheduled offset.
  void start(void Function() onTick) {
    cancel();
    for (final offset in _schedule) {
      _timers.add(Timer(offset, onTick));
    }
  }

  /// Cancels all pending ticks.
  void cancel() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}
