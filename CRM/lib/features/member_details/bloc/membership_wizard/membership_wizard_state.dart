import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_consequence.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_load.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_task.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';

/// Everything the staff start-memberships flow holds.
///
/// It replaces the local fields of a 950-line `StatefulWidget`, and the two
/// things it adds over them are the point: every READ that can fail carries a
/// [MembershipWizardLoad] rather than a nullable payload (a spinner that never
/// resolves is not an error state), and every control that destroys work
/// leaves a [MembershipWizardConsequence] behind (a silent drop is not an
/// undo).
///
/// The roster is DERIVED, not stored — see `membership_wizard_derived.dart`.
/// Storing it would give the flow two truths about who is in the run, and the
/// one that decided the cart would not always be the one on screen.
class MembershipWizardState extends Equatable {
  // ── Launch identity ───────────────────────────────────────────────────────

  final String gymId;

  /// The member whose page opened the flow. They are the default payer, the
  /// fallback participant after a payer switch (always valid — the payer
  /// choices ARE their authorized payers), and the anchor every payer-side
  /// authorization is written against.
  final String launchMemberId;

  // ── Position ──────────────────────────────────────────────────────────────

  final MembershipWizardStep step;

  /// Which training person the plans step is on — an index into the DERIVED
  /// training roster, clamped by every reader.
  final int personIndex;

  /// Editing one person's lineup FROM the review, so finishing their plans
  /// step returns straight to the review instead of walking to the next
  /// person.
  final bool editReturnsToReview;

  // ── Who pays ──────────────────────────────────────────────────────────────

  final MembershipWizardPerson payer;

  /// The payer's own billing detail — their card on file, and the people they
  /// are authorized to pay for (the roster below the payer).
  final MemberDetailResponse? payerDetail;
  final MembershipWizardLoad payerLoad;

  /// The launch member's authorized payers — who staff may switch TO.
  final List<LinkedAccount> payerCandidates;

  // ── The roster's answers ──────────────────────────────────────────────────

  /// Who is getting a membership. A person on the roster and NOT in here is a
  /// payer-only (or simply not-buying-today) row, which is an ordinary sale.
  final Set<String> trainingMemberIds;

  /// memberId → the memberships picked for them, in pick order.
  final Map<String, List<MembershipWizardDraft>> drafts;

  /// Best-effort full detail per roster member, for the plan gates and the
  /// "Already has" block. A member missing here simply has no client-side
  /// gates — the backend still refuses a duplicate.
  final Map<String, MemberDetailResponse> memberDetails;

  // ── Catalogue ─────────────────────────────────────────────────────────────

  /// The gym's SELLABLE plans (the shared catalogue policy already applied).
  final List<MembershipPlanResponse> plans;
  final MembershipWizardLoad plansLoad;

  /// The desk's ability to reduce a price. Never null here and never null-able
  /// as a capability: a desk config with no discounts would be a wizard that
  /// silently cannot price a family.
  final DiscountsCapability discounts;
  final MembershipWizardLoad discountsLoad;

  // ── Waivers ───────────────────────────────────────────────────────────────

  /// Per member, the waivers the gym already holds a compliant signature for
  /// (`signed && meets_floor`, the SERVER's own verdict). Absence means ASK —
  /// the skip fails CLOSED.
  final Map<String, Set<String>> satisfiedWaiverIds;

  /// What a 422 gate named — the backstop. Never dropped by the client-side
  /// skip, and re-derived into the queue.
  final List<MembershipWizardWaiverTask> serverGate;

  /// `memberId:waiverId` for every signature THIS run collected. Signed stays
  /// signed: Back then forward never re-asks.
  final Set<String> signedWaiverKeys;

  /// The waiver body on screen, and its read.
  final WaiverResponse? waiver;
  final MembershipWizardLoad waiverLoad;

  /// The gym republished the waiver between the read and the signature, so it
  /// was refused and the body is reloading.
  final bool waiverStale;

  /// A signature is in flight.
  final bool signing;

  // ── Money ─────────────────────────────────────────────────────────────────

  /// The staged request the preview was fetched for — always assembled at
  /// `prorate_to_anchor` so the response carries the full split.
  final MemberMembershipsStartRequest? previewRequest;
  final MemberMembershipsStartPreview? preview;
  final MembershipWizardLoad previewLoad;

  /// The proration CHOICE. It is chosen on the review step, where it visibly
  /// moves the total, and it re-derives the readouts LOCALLY — the preview is
  /// never re-fetched for it.
  final ProrationBehavior prorationBehavior;

  final bool paidWithCash;

  /// A card entered at checkout for a purely one-time cart. Kept across a cash
  /// toggle and across a cart turning recurring, so turning the blocker off
  /// restores it rather than making staff re-type a card.
  final CustomCardCapture? customCard;

  // ── Commit ────────────────────────────────────────────────────────────────

  /// The key this attempt would post under. Minted on entering the payment
  /// step, so a double-tap reuses ONE key; a retry mints a fresh one.
  final String? idempotencyKey;

  final bool starting;
  final MemberMembershipsStartResponse? startResult;
  final MembershipWizardCommitError? commitError;

  // ── Consequences ──────────────────────────────────────────────────────────

  /// What the last destructive control actually dropped, so the surface can
  /// state it after the fact. Cleared by [MembershipWizardCubit.clearConsequence].
  final MembershipWizardConsequence? lastConsequence;

  const MembershipWizardState({
    required this.gymId,
    required this.launchMemberId,
    required this.payer,
    this.step = MembershipWizardStep.who,
    this.personIndex = 0,
    this.editReturnsToReview = false,
    this.payerDetail,
    this.payerLoad = const MembershipWizardLoad.idle(),
    this.payerCandidates = const [],
    this.trainingMemberIds = const {},
    this.drafts = const {},
    this.memberDetails = const {},
    this.plans = const [],
    this.plansLoad = const MembershipWizardLoad.idle(),
    this.discounts = const DiscountsCapability(),
    this.discountsLoad = const MembershipWizardLoad.idle(),
    this.satisfiedWaiverIds = const {},
    this.serverGate = const [],
    this.signedWaiverKeys = const {},
    this.waiver,
    this.waiverLoad = const MembershipWizardLoad.idle(),
    this.waiverStale = false,
    this.signing = false,
    this.previewRequest,
    this.preview,
    this.previewLoad = const MembershipWizardLoad.idle(),
    this.prorationBehavior = ProrationBehavior.prorateToAnchor,
    this.paidWithCash = false,
    this.customCard,
    this.idempotencyKey,
    this.starting = false,
    this.startResult,
    this.commitError,
    this.lastConsequence,
  });

  /// The sentinel that tells [copyWith] "leave it alone", so every nullable
  /// field above can be CLEARED as well as set. A plain `?? this.x` can only
  /// ever set one.
  static const Object _keep = Object();

  MembershipWizardState copyWith({
    MembershipWizardStep? step,
    int? personIndex,
    bool? editReturnsToReview,
    MembershipWizardPerson? payer,
    Object? payerDetail = _keep,
    MembershipWizardLoad? payerLoad,
    List<LinkedAccount>? payerCandidates,
    Set<String>? trainingMemberIds,
    Map<String, List<MembershipWizardDraft>>? drafts,
    Map<String, MemberDetailResponse>? memberDetails,
    List<MembershipPlanResponse>? plans,
    MembershipWizardLoad? plansLoad,
    DiscountsCapability? discounts,
    MembershipWizardLoad? discountsLoad,
    Map<String, Set<String>>? satisfiedWaiverIds,
    List<MembershipWizardWaiverTask>? serverGate,
    Set<String>? signedWaiverKeys,
    Object? waiver = _keep,
    MembershipWizardLoad? waiverLoad,
    bool? waiverStale,
    bool? signing,
    Object? previewRequest = _keep,
    Object? preview = _keep,
    MembershipWizardLoad? previewLoad,
    ProrationBehavior? prorationBehavior,
    bool? paidWithCash,
    Object? customCard = _keep,
    Object? idempotencyKey = _keep,
    bool? starting,
    Object? startResult = _keep,
    Object? commitError = _keep,
    Object? lastConsequence = _keep,
  }) {
    return MembershipWizardState(
      gymId: gymId,
      launchMemberId: launchMemberId,
      step: step ?? this.step,
      personIndex: personIndex ?? this.personIndex,
      editReturnsToReview: editReturnsToReview ?? this.editReturnsToReview,
      payer: payer ?? this.payer,
      payerDetail: identical(payerDetail, _keep)
          ? this.payerDetail
          : payerDetail as MemberDetailResponse?,
      payerLoad: payerLoad ?? this.payerLoad,
      payerCandidates: payerCandidates ?? this.payerCandidates,
      trainingMemberIds: trainingMemberIds ?? this.trainingMemberIds,
      drafts: drafts ?? this.drafts,
      memberDetails: memberDetails ?? this.memberDetails,
      plans: plans ?? this.plans,
      plansLoad: plansLoad ?? this.plansLoad,
      discounts: discounts ?? this.discounts,
      discountsLoad: discountsLoad ?? this.discountsLoad,
      satisfiedWaiverIds: satisfiedWaiverIds ?? this.satisfiedWaiverIds,
      serverGate: serverGate ?? this.serverGate,
      signedWaiverKeys: signedWaiverKeys ?? this.signedWaiverKeys,
      waiver: identical(waiver, _keep)
          ? this.waiver
          : waiver as WaiverResponse?,
      waiverLoad: waiverLoad ?? this.waiverLoad,
      waiverStale: waiverStale ?? this.waiverStale,
      signing: signing ?? this.signing,
      previewRequest: identical(previewRequest, _keep)
          ? this.previewRequest
          : previewRequest as MemberMembershipsStartRequest?,
      preview: identical(preview, _keep)
          ? this.preview
          : preview as MemberMembershipsStartPreview?,
      previewLoad: previewLoad ?? this.previewLoad,
      prorationBehavior: prorationBehavior ?? this.prorationBehavior,
      paidWithCash: paidWithCash ?? this.paidWithCash,
      customCard: identical(customCard, _keep)
          ? this.customCard
          : customCard as CustomCardCapture?,
      idempotencyKey: identical(idempotencyKey, _keep)
          ? this.idempotencyKey
          : idempotencyKey as String?,
      starting: starting ?? this.starting,
      startResult: identical(startResult, _keep)
          ? this.startResult
          : startResult as MemberMembershipsStartResponse?,
      commitError: identical(commitError, _keep)
          ? this.commitError
          : commitError as MembershipWizardCommitError?,
      lastConsequence: identical(lastConsequence, _keep)
          ? this.lastConsequence
          : lastConsequence as MembershipWizardConsequence?,
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        launchMemberId,
        step,
        personIndex,
        editReturnsToReview,
        payer,
        payerDetail,
        payerLoad,
        payerCandidates,
        trainingMemberIds,
        drafts,
        memberDetails,
        plans,
        plansLoad,
        discounts,
        discountsLoad,
        satisfiedWaiverIds,
        serverGate,
        signedWaiverKeys,
        waiver,
        waiverLoad,
        waiverStale,
        signing,
        previewRequest,
        preview,
        previewLoad,
        prorationBehavior,
        paidWithCash,
        customCard,
        idempotencyKey,
        starting,
        startResult,
        commitError,
        lastConsequence,
      ];
}
