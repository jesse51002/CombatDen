import 'package:equatable/equatable.dart';

/// Where a kiosk session sits on its 12-hour runway.
///
/// - [restoring] — the persisted kiosk flag has NOT been read yet. This is the
///   **synchronous initial state** every cubit starts in (before the async
///   [KioskSessionStore.read] in `_restore` resolves). The gate renders a
///   neutral loader here — **never** the admin workspace — so a boot / reload /
///   refresh can't flash an admin screen (and fire its backend fetch) before
///   the flag is known. Once read, `_restore` resolves this to a real status.
/// - [inactive] — not in kiosk; the admin workspace mounts normally.
/// - [active] — in kiosk, within the runway; member self-serve flows may start.
/// - [locked] — past the lockout mark (runway − grace, i.e. T+11h45) while a
///   flow is mid-signup: **no new flows may start**, but the in-progress one
///   rides out its grace until the hard revoke.
/// - [ended] — the runway is spent (or the tab reopened past the deadline). The
///   fail-closed terminal state: a sign-out is in flight and the locked screen
///   shows instead of the admin workspace, even if that sign-out is slow or
///   fails.
enum KioskStatus { restoring, inactive, active, locked, ended }

/// Immutable state of the app-root kiosk session.
///
/// The [deadline] is the absolute end of the runway (set once at entry, never
/// extended by member interaction — that immovability is the whole security
/// point). It is carried for reference across [active]/[locked]/[ended]; it is
/// null while [restoring] or [inactive].
class KioskSessionState extends Equatable {
  final KioskStatus status;
  final DateTime? deadline;

  const KioskSessionState({required this.status, this.deadline});

  /// The synchronous initial state: the persisted flag has not been read yet.
  /// The gate shows a neutral loader for this, never the admin workspace.
  const KioskSessionState.restoring()
      : status = KioskStatus.restoring,
        deadline = null;

  const KioskSessionState.inactive()
      : status = KioskStatus.inactive,
        deadline = null;

  /// The persisted kiosk flag has not been read yet — hold on a neutral loader
  /// (never the admin workspace) until `_restore` resolves to a real status.
  bool get isRestoring => status == KioskStatus.restoring;

  /// The kiosk surface (placeholder / real member screens) is mounted — the
  /// admin workspace is intercepted. True while [active] or [locked].
  bool get isKioskVisible =>
      status == KioskStatus.active || status == KioskStatus.locked;

  /// The runway is spent: show the fail-closed locked screen, never admin.
  bool get isEnded => status == KioskStatus.ended;

  /// Past the lockout mark — the kiosk shows but no new flow may start.
  bool get isLocked => status == KioskStatus.locked;

  /// A new check-in / signup flow is allowed to start (only while [active] —
  /// blocked once [locked] or [ended]). Phase C/D flows gate on this.
  bool get canStartFlow => status == KioskStatus.active;

  @override
  List<Object?> get props => [status, deadline];
}
