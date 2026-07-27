import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// How long a dispatched refresh is waited on before the pull's spinner is
/// allowed to stop regardless. A bloc handler that hangs on a dead socket must
/// not leave the indicator spinning forever.
const Duration kRefreshTimeout = Duration(seconds: 20);

/// A one-shot completion side-channel carried BY a refresh event.
///
/// Blocs are event-driven: `bloc.add(...)` returns immediately, so a
/// `RefreshIndicator` that only dispatched an event would resolve its spinner
/// long before the work landed. Watching the state stream instead is not
/// reliable either — a handler that early-returns (no member selected) or that
/// re-emits an equal state emits nothing at all, and `RefreshIndicator` would
/// hang until the timeout.
///
/// So every refresh event carries an optional [RefreshSignal] and its handler
/// completes it in a `finally`: the dispatcher awaits real completion, success
/// or failure, with no fixed delay anywhere. The field is optional and
/// POSITIONAL so the existing `const XRefreshRequested()` call sites keep
/// working untouched, and so the constructor tears off as
/// `XRefreshRequested.new` for [dispatchRefresh].
class RefreshSignal {
  final Completer<void> _completer = Completer<void>();

  /// Resolves when the handler that received this signal has finished.
  Future<void> get future => _completer.future;

  /// Mark the work done. Safe to call more than once (a handler may complete
  /// in both a success path and its `finally`).
  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Add a refresh event built by [build] to [bloc] and await its handler.
///
/// [build] is the event constructor's tear-off (e.g. `HomeRefreshRequested.new`)
/// — it receives the signal the handler completes. A closed bloc is a no-op
/// (the screen went away mid-pull), and a handler that never completes is
/// bounded by [timeout] rather than hanging the indicator.
Future<void> dispatchRefresh<E, S>(
  Bloc<E, S> bloc,
  E Function(RefreshSignal signal) build, {
  Duration timeout = kRefreshTimeout,
}) async {
  if (bloc.isClosed) return;
  final signal = RefreshSignal();
  bloc.add(build(signal));
  await signal.future.timeout(timeout, onTimeout: () {});
}
