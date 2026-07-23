import 'package:equatable/equatable.dart';

/// Where a kiosk session sits on its 12-hour runway.
///
/// - [inactive] — not in kiosk; the admin workspace mounts normally.
/// - [active] — in kiosk, within the runway; member self-serve flows may start.
/// - [locked] — past the lockout mark (runway − grace, i.e. T+11h45) while a
///   flow is mid-signup: **no new flows may start**, but the in-progress one
///   rides out its grace until the hard revoke.
/// - [ended] — the runway is spent (or the tab reopened past the deadline). The
///   fail-closed terminal state: a sign-out is in flight and the locked screen
///   shows instead of the admin workspace, even if that sign-out is slow or
///   fails.
enum KioskStatus { inactive, active, locked, ended }

/// Immutable state of the app-root kiosk session.
///
/// The [deadline] is the absolute end of the runway (set once at entry, never
/// extended by member interaction — that immovability is the whole security
/// point). It is carried for reference across [active]/[locked]/[ended]; it is
/// null only when [inactive].
class KioskSessionState extends Equatable {
  final KioskStatus status;
  final DateTime? deadline;

  const KioskSessionState({required this.status, this.deadline});

  const KioskSessionState.inactive()
      : status = KioskStatus.inactive,
        deadline = null;

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
