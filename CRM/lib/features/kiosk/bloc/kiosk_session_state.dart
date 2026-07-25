import 'package:equatable/equatable.dart';

/// Where a kiosk session sits on its 12-hour runway.
///
/// - [restoring] — the SYNCHRONOUS initial state, before the async flag read
///   resolves. The gate renders a neutral loader here, never the admin
///   workspace, so a boot / reload can't flash an admin screen (and fire its
///   backend fetch) before the flag is known.
/// - [inactive] — not in kiosk; the admin workspace mounts normally.
/// - [active] — in kiosk, within the runway; member flows may start.
/// - [locked] — past the lockout mark while a flow is mid-progress: no new
///   flows may start, but the in-progress one rides out its grace.
/// - [ended] — the runway is spent (or the tab reopened past the deadline). The
///   fail-closed terminal state: a sign-out is in flight and the locked screen
///   shows instead of the admin workspace, even if that sign-out fails.
enum KioskStatus { restoring, inactive, active, locked, ended }

/// Immutable state of the app-root kiosk session. The [deadline] is the
/// absolute end of the runway — set once at entry and never extended by member
/// interaction, which is the whole security point. Null while restoring or
/// inactive.
class KioskSessionState extends Equatable {
  final KioskStatus status;
  final DateTime? deadline;

  const KioskSessionState({required this.status, this.deadline});

  const KioskSessionState.restoring()
      : status = KioskStatus.restoring,
        deadline = null;

  const KioskSessionState.inactive()
      : status = KioskStatus.inactive,
        deadline = null;

  /// The flag has not been read yet — hold on a neutral loader, never admin.
  bool get isRestoring => status == KioskStatus.restoring;

  /// The kiosk surface is mounted, intercepting the admin workspace — true
  /// while [KioskStatus.active] or [KioskStatus.locked].
  bool get isKioskVisible =>
      status == KioskStatus.active || status == KioskStatus.locked;

  /// The runway is spent: show the fail-closed locked screen, never admin.
  bool get isEnded => status == KioskStatus.ended;

  /// Past the lockout mark — the kiosk shows but no new flow may start.
  bool get isLocked => status == KioskStatus.locked;

  /// A new check-in / signup flow may start — only while active, blocked once
  /// locked or ended. The kiosk flows gate on this.
  bool get canStartFlow => status == KioskStatus.active;

  @override
  List<Object?> get props => [status, deadline];
}
