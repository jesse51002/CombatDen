import 'package:equatable/equatable.dart';

/// Where one of the flow's reads currently stands.
enum MembershipWizardLoadStatus { idle, loading, ready, failed }

/// The state of ONE read the flow depends on — the catalogue, the gym's
/// discounts, the payer's own billing detail, the charge preview, a waiver
/// body.
///
/// It is a four-state value rather than a nullable payload because the failure
/// has to be REPRESENTABLE. A read whose only failure signal is "the payload is
/// still null" renders as a spinner that never resolves, which is exactly what
/// the old wizard's swallowed payer-detail exception did: staff sat on a
/// members step that would never enable, with no error and no retry. Every
/// read here fails to [failed] and every failure carries a retry path.
class MembershipWizardLoad extends Equatable {
  final MembershipWizardLoadStatus status;

  /// What went wrong, for the surface to print. Null unless [failed].
  final String? message;

  const MembershipWizardLoad._(this.status, [this.message]);

  /// Not asked for yet.
  const MembershipWizardLoad.idle()
      : this._(MembershipWizardLoadStatus.idle);

  /// In flight.
  const MembershipWizardLoad.loading()
      : this._(MembershipWizardLoadStatus.loading);

  /// Landed.
  const MembershipWizardLoad.ready()
      : this._(MembershipWizardLoadStatus.ready);

  /// Did not land, and says so. [message] is what the retry surface prints.
  const MembershipWizardLoad.failed(String message)
      : this._(MembershipWizardLoadStatus.failed, message);

  bool get isIdle => status == MembershipWizardLoadStatus.idle;
  bool get isLoading => status == MembershipWizardLoadStatus.loading;
  bool get isReady => status == MembershipWizardLoadStatus.ready;
  bool get isFailed => status == MembershipWizardLoadStatus.failed;

  @override
  List<Object?> get props => [status, message];
}
