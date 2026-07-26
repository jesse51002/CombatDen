import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_request.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_results.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_roster.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_plan.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_task.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/membership_flow/config/membership_flow_config.dart';
import 'package:crm/features/membership_flow/domain/membership_history.dart';
import 'package:crm/features/membership_flow/domain/money_readouts.dart';
import 'package:crm/features/membership_flow/domain/plan_rules.dart';

/// Everything the staff flow KNOWS rather than stores.
///
/// It is an extension rather than fields because every one of these has
/// exactly one right answer given the state, and a stored copy is a second
/// answer waiting to disagree with it — which is how the old wizard ended up
/// stepping to a member index that no longer existed.
///
/// Nothing here re-derives what the shared module already computes: the gates
/// come from `MembershipFlowConfig.admin`, the money from
/// `domain/money_readouts.dart`, the waiver queue from
/// `domain/waiver_queue.dart`.
extension MembershipWizardDerived on MembershipWizardState {
  // ── The surface's capability set ──────────────────────────────────────────

  /// The desk's config — the ONE place its capabilities are named. Built from
  /// the loaded discounts, so a gym with no presets still gets the custom
  /// form rather than a wizard that cannot price a family.
  MembershipFlowConfig get config =>
      MembershipFlowConfig.admin(discounts: discounts);

  // ── The roster ────────────────────────────────────────────────────────────

  /// Everybody this payer may cover, payer first.
  List<MembershipWizardPerson> get people => rosterFor(
        payer: payer,
        payerDetail: payerDetail,
        trainingMemberIds: trainingMemberIds,
        memberDetails: memberDetails,
      );

  /// The people actually getting a membership — N, and the order the plans
  /// step walks.
  List<MembershipWizardPerson> get trainingPeople =>
      [for (final person in people) if (person.training) person];

  /// The person whose plans step is open, clamped into the training roster.
  MembershipWizardPerson? get currentPerson {
    final list = trainingPeople;
    if (list.isEmpty) return null;
    if (personIndex < 0) return list.first;
    return list[personIndex >= list.length ? list.length - 1 : personIndex];
  }

  /// The lineup on screen.
  List<MembershipWizardDraft> get currentDrafts =>
      draftsFor(currentPerson?.memberId);

  List<MembershipWizardDraft> draftsFor(String? memberId) =>
      memberId == null
          ? const []
          : (drafts[memberId] ?? const <MembershipWizardDraft>[]);

  /// Whether anything at all is configured — the review's own floor, since
  /// removing memberships there can empty the run entirely.
  bool get hasAnyMembership => trainingPeople
      .any((person) => draftsFor(person.memberId).isNotEmpty);

  /// Whether the cart holds a plan that bills every cycle. It decides the
  /// proration control's existence and blocks the one-off card.
  bool get hasRecurring => _anyDraft(
        (draft) => draft.plan.planType == PlanType.recurring,
      );

  /// Whether the cart holds anything that bills once.
  bool get hasOneTime => _anyDraft(
        (draft) => draft.plan.planType != PlanType.recurring,
      );

  bool _anyDraft(bool Function(MembershipWizardDraft) test) =>
      trainingPeople.any(
        (person) => draftsFor(person.memberId).any(test),
      );

  // ── Plan rules, per person ────────────────────────────────────────────────

  /// One person's own membership rows — the input every gate is built from.
  /// Empty when their detail read never landed, which leaves them ungated on
  /// the client; the backend's duplicate guard still refuses the sale.
  List<MembershipInfo> membershipsOf(String memberId) {
    final detail = memberDetails[memberId];
    if (detail == null) return const [];
    return membershipsForParticipant(detail.memberships, memberId);
  }

  /// What one person currently holds, for the plans step's "Already has"
  /// block.
  List<MembershipInfo> currentMembershipsOf(String memberId) {
    final detail = memberDetails[memberId];
    if (detail == null) return const [];
    return currentMembershipsForParticipant(detail.memberships, memberId);
  }

  /// The gate that CLOSES [plan] to [memberId], or null when it is open. The
  /// desk carries one gate — the backend's own duplicate-recurring guard,
  /// which staff cannot talk their way past either.
  PlanGate? gateFor(String memberId, MembershipPlanResponse plan) =>
      firstBlockingGate(config.gatesFor(membershipsOf(memberId)), plan);

  /// The advisories on [plan] for [memberId]. A note never closes a card — a
  /// repeat trial is exactly what staff grant at a desk.
  List<PlanNote> notesFor(String memberId, MembershipPlanResponse plan) => [
        for (final note in config.notesFor(membershipsOf(memberId)))
          if (note.applies(plan)) note,
      ];

  // ── The waiver run ────────────────────────────────────────────────────────

  /// Every signature still owed, derived from the picked plans — so the step
  /// exists BEFORE the money rather than after a 422.
  List<MembershipWizardWaiverTask> get waiverQueue => deriveWaiverQueue(
        people: people,
        drafts: drafts,
        satisfiedWaiverIds: satisfiedWaiverIds,
        serverGate: serverGate,
      );

  /// Whether this run walks a waivers step at all.
  bool get hasWaivers => waiverQueue.isNotEmpty;

  /// The signature on screen, or null once the run is done.
  MembershipWizardWaiverTask? get currentWaiverTask =>
      firstUnsignedTask(waiverQueue, signedWaiverKeys);

  bool get allWaiversSigned => currentWaiverTask == null;

  // ── The spine ─────────────────────────────────────────────────────────────

  List<MembershipWizardStep> get steps => membershipWizardSteps(
        trainingPeople: trainingPeople.length,
        hasWaivers: hasWaivers,
      );

  /// Where the flow stands in its own spine — `5 + N` entries, or `4 + N` when
  /// nothing needs signing.
  int get stepIndex => membershipWizardStepIndex(
        step: step,
        personIndex: personIndex,
        trainingPeople: trainingPeople.length,
        hasWaivers: hasWaivers,
      );

  int get stepCount => steps.length;

  // ── Money ─────────────────────────────────────────────────────────────────

  /// The payer's saved card — the only card a recurring membership can bill.
  CardOnFile? get savedCard => payerDetail?.cardOnFile;

  /// Why the one-off card cannot pay, or null when it can.
  OneOffCardBlock? get oneOffCardBlock => oneOffCardBlockFor(
        paidWithCash: paidWithCash,
        hasOneTime: hasOneTime,
        hasRecurring: hasRecurring,
      );

  /// Whether a captured one-off card is what actually pays today.
  bool get oneOffCardPays => oneOffCardBlock == null && customCard != null;

  /// The due-now invoice as the proration CHOICE dictates.
  PreviewInvoice? get effectiveDueNowInvoice =>
      effectiveDueNow(preview, prorationBehavior);

  int get dueTodayMinor => dueTodayMinorUnits(preview, prorationBehavior);

  bool get chargedTwice => chargedTwiceToday(preview, prorationBehavior);

  bool get prorated => chargedProrated(preview, prorationBehavior);

  DateTime? get prorationEnds => prorationUntil(preview, prorationBehavior);

  String get currency => previewCurrency(preview, prorationBehavior);

  // ── The commit ────────────────────────────────────────────────────────────

  List<MemberMembershipsStartResultItem> get startItems =>
      startResult?.results ?? const [];

  /// The (member, plan) pairs a retry may re-send. Null when nothing landed.
  Set<String>? get retryScope => retryScopeFor(startResult);

  /// Whether a retry has anything left to send — the ONE gate on re-firing.
  bool get canRetry => retryScope?.isNotEmpty ?? false;

  /// The three-way split of a landed start.
  MembershipWizardOutcome? get outcome => outcomeOf(startResult);

  /// The items the NEXT attempt carries: the whole cart on a first attempt,
  /// only the un-created ones after a start has landed.
  List<MemberMembershipsStartItem> get pendingItems => startItemsFor(
        people: people,
        drafts: drafts,
        retryScope: retryScope,
      );

  /// Whether one membership already went through on an earlier attempt, so the
  /// next charge does not cover it. It MARKS a row; it never removes one.
  bool alreadyStarted(String memberId, String planId) =>
      startResult != null &&
      !isBeingCharged(
        memberId: memberId,
        planId: planId,
        retryScope: retryScope,
      );

  // ── The footer ────────────────────────────────────────────────────────────

  /// Whether the step on screen may be left forwards.
  bool get canAdvance => switch (step) {
        // The payer's detail decides who may even be listed, so the roster is
        // not answerable until it lands — and it now FAILS rather than
        // spinning, so this being false always has something on screen.
        MembershipWizardStep.who =>
          payerLoad.isReady && trainingPeople.isNotEmpty,
        MembershipWizardStep.plans => currentDrafts.isNotEmpty,
        MembershipWizardStep.waivers => allWaiversSigned,
        MembershipWizardStep.reviewCharges =>
          hasAnyMembership && previewLoad.isReady,
        // Cash, the payer's saved card, or — for a cart with no blocker — the
        // one-off card alone.
        MembershipWizardStep.payment =>
          paidWithCash || savedCard != null || oneOffCardPays,
        MembershipWizardStep.results => !starting,
      };
}
