import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

String _defaultUuid() => const Uuid().v4();

/// What every concern of the staff flow shares: its two repositories, its key
/// source, and the two moves that touch the spine.
///
/// The cubit is assembled from concern MIXINS on this base (roster, plans,
/// waivers, money, commit) rather than written as one file, so the money path
/// — the part that can charge a card twice — is readable on its own instead of
/// buried nine hundred lines into somebody else's screen logic.
///
/// It calls `MemberRepository` DIRECTLY rather than dispatching through
/// `MemberDetailBloc`, exactly as the kiosk does: a purchase is a
/// self-contained transaction with its own idempotency key, its own retry
/// scope and its own latch, and routing it through the page's bloc puts all
/// three somewhere a second screen can reach them. The host dispatches a
/// refresh once the run lands.
abstract class MembershipWizardBase extends Cubit<MembershipWizardState> {
  MembershipWizardBase({
    required this.memberRepo,
    required this.membershipsRepo,
    required MembershipWizardState initial,

    /// Injected so a test can assert "a NEW key" rather than read one off a
    /// constant stub.
    String Function()? uuid,
  })  : _uuid = uuid ?? _defaultUuid,
        super(initial);

  final MemberRepository memberRepo;
  final MembershipsRepository membershipsRepo;
  final String Function() _uuid;

  /// A fresh idempotency key. Minted deliberately — on entering the payment
  /// step, and again for each retry — never per render.
  String newIdempotencyKey() => _uuid();

  /// Move to [step]. [personIndex] is clamped into the training roster, so a
  /// roster that shrank while staff were elsewhere can never leave the plans
  /// step pointing at somebody who is no longer in the run.
  void goTo(MembershipWizardStep step, {int? personIndex}) {
    emit(
      state.copyWith(
        step: step,
        personIndex: clampPersonIndex(personIndex ?? state.personIndex),
      ),
    );
  }

  /// [candidate] brought inside the training roster.
  int clampPersonIndex(int candidate) {
    final count = state.trainingPeople.length;
    if (count == 0) return 0;
    if (candidate < 0) return 0;
    return candidate >= count ? count - 1 : candidate;
  }

  /// Re-stage the review's preview. Declared here because the step machine
  /// enters the review from three directions (forward off the last plans step,
  /// forward out of the waiver run, and back off payment) and the money
  /// concern owns what that means.
  Future<void> enterReviewCharges();

  /// Enter the payment step, minting this attempt's idempotency key.
  void enterPayment();

  /// Read the body of the waiver on screen.
  Future<void> loadCurrentWaiver();
}
