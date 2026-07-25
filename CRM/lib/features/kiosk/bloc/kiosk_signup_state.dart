import 'package:equatable/equatable.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';

/// The signup lane's step spine — the whole solo (D) + group (E) flow, in the
/// order the approved mockups walk it.
///
/// Solo: [entry] → [details] → [extraDetails] *(the member is created here)*
/// → [people] → [plans] → [waivers] → [card] → [review] → [paying] →
/// [results] → [welcome]. An existing member takes [entry] → [identify] →
/// [payerMatch] instead and lands straight on [people].
/// Group adds the roster loop ([personDetails], [match]) off [people].
///
/// [plans] comes BEFORE [waivers] deliberately: a plan's `waiverIds` is a
/// property of the plan, so there is nothing to sign until one is picked.
///
/// [declined] and [stop] are the two failure terminals and they are NOT the
/// same: [declined] is retryable (the card was refused; members, signatures
/// and links are all committed and are never re-executed), while [stop] is a
/// terminal front-desk handoff.
enum KioskSignupStep {
  /// The first fork: brand new here, or already a member. The lane is
  /// near-fully self-serve, so an existing member starts their own signup
  /// rather than being sent to the desk — they just say so first.
  entry,

  /// "Find your name" — the existing member identifies themselves against
  /// the gym's own records instead of typing a second account into being.
  identify,

  /// D1 — first / last / email (required) / phone.
  details,

  /// D1a — date of birth, address, emergency contact. Always shown.
  /// Continue **or** Skip fires the single `createMember` call.
  extraDetails,

  /// E1 — the roster: "It's just me" or add someone.
  people,

  /// E1a — one added person's own details.
  personDetails,

  /// E2 — find an EXISTING member to add to the cart.
  match,

  /// The person standing at the iPad already has an account here, so it is
  /// adopted rather than duplicated. One confirm card, their own name and
  /// masked email, and two answers. Reached from [identify] (they said so) or
  /// from a duplicate 409 on their own create (the gym's records said so).
  payerMatch,

  /// "Someone else is paying" — pick the EXISTING member who pays for this
  /// signup.
  payerPick,

  /// D3 — pick one plan per person.
  plans,

  /// D4 / E3 — sign the plan's waivers (and, per payee, the payer-auth link).
  waivers,

  /// D5 — the fresh card. Never a saved card, never a payer picker.
  card,

  /// D6 / E4 — what will be charged, then Pay.
  review,

  /// D7 — the start call is in flight. No buttons, no escape, no idle guard.
  paying,

  /// D7a — the start landed and the per-person receipt says what happened.
  ///
  /// It is entered with a response in hand, never while anything is in
  /// flight, and it covers TWO outcomes: every membership created (a receipt,
  /// with one Next into [welcome]) and a PARTIAL — some created, some not —
  /// where money HAS moved for the group that cleared, so the decline popup's
  /// "you haven't been charged" would be false. An ALL-failed start goes to
  /// [declined] instead, where that copy is true.
  results,

  /// D8 — every membership in the cart was refused. Retries PAY only.
  declined,

  /// The signup succeeded.
  welcome,

  /// A terminal front-desk handoff ([KioskSignupState.stopReason] says which).
  stop,
}

/// Why a plan on the grid is closed to the person currently picking.
///
/// The two reasons are different rules with different scopes, and the
/// difference is load-bearing for the words each one uses:
///
/// * [trialUsed] is per MEMBER — any trial in their history closes EVERY trial
///   plan — so its copy never names a plan, or it would describe a narrower
///   rule than the grid is enforcing.
/// * [alreadyOnPlan] is per PLAN — the backend conflicts on
///   `plan_id = ANY(:plan_ids)` — so its copy DOES name the plan, because
///   naming it describes the rule exactly.
///
/// The copy for each lives in `presentation/kiosk_plan_block_copy.dart`, whose
/// switches are exhaustive on purpose: a new reason cannot ship without words.
enum KioskPlanBlockReason {
  /// A trial plan, for somebody who has already had a trial here. A kiosk-only
  /// rule (§3) — staff may still grant a repeat trial from the CRM.
  trialUsed,

  /// A RECURRING plan this member already holds `active` or `frozen`. The
  /// backend refuses it on the preview AND the start, so an unblocked card
  /// dead-ends the whole signup on a retryable stop that can never succeed.
  alreadyOnPlan,
}

/// How complete one roster person's optional details are — the readout the
/// group roster chip renders ("Details on file" / "Some details").
enum KioskSignupDetailsStatus {
  /// Nothing optional was given.
  none,

  /// Some optional fields were given.
  partial,

  /// Every optional field was given.
  complete,
}

/// Why the signup stopped dead and handed off to the front desk.
///
/// Every one of these is TERMINAL: the screen's single action returns home.
/// The copy for each lives in `presentation/kiosk_signup_stop_copy.dart` —
/// the ONE place a reason becomes member-facing words, mirroring
/// `kiosk_blocked_copy.dart`.
///
/// Adding a reason means adding its line in
/// `presentation/kiosk_signup_stop_copy.dart` in the same change — the switch
/// there is exhaustive on purpose so a new reason can never ship without
/// words.
///
/// Two of them are **retryable** ([isRetryable]): the read behind them can
/// simply be attempted again, so the screen offers a "Try again" and the
/// session's flow count is deliberately NOT released while the member is still
/// standing there. Every other reason is a true dead end.
enum KioskSignupStopReason {
  /// `POST /members/` came back 409 `duplicate_member` and the member said
  /// the matched account is NOT theirs — or the 409 named nobody at all.
  ///
  /// A 409 that names somebody is offered as "is this you?" first, so this is
  /// only reached once that offer has been answered "no" (from the duplicate
  /// route, where nothing further can be typed) or was never answerable. The
  /// 409's `matches` are never rendered as a list either way: confirming to
  /// whoever is standing at a shared iPad that a given account exists is an
  /// account-existence leak, and the answer is the same either way.
  duplicateMember,

  /// This member has already had a trial at this gym, and trials are one to a
  /// member. Reached only when they CHOOSE the desk from the trial-block
  /// popup — the popup's own primary sends them back to the plan grid, which
  /// is the ordinary way out.
  trialAlreadyUsed,

  /// This member already holds the RECURRING plan they tapped, and one member
  /// holds one of a given recurring plan. Reached only when they CHOOSE the
  /// desk from the plan-block popup — the popup's own primary sends them back
  /// to the grid, where every other plan is still open (the rule is per plan,
  /// so a DIFFERENT recurring plan is a perfectly good sale).
  alreadyOnPlan,

  /// `POST /members/` came back 400 — the gym has no Stripe Connect account,
  /// so no member (and no customer) can be created at all. A gym-setup
  /// problem, never the member's.
  paymentsUnavailable,

  /// The create call failed for any other reason (a 5xx, a dropped network,
  /// an unrecognised 4xx). Nothing was written.
  signupFailed,

  /// The gym offers no plan a self-serve iPad may sell — none is public with
  /// an active price. A gym-setup fact, not a failure, so it gets its own
  /// words rather than the generic apology.
  noPlansOffered,

  /// The plan catalogue could not be read. Retryable — nothing is wrong with
  /// the signup, one read just failed.
  plansUnavailable,

  /// The charge preview failed. Retryable for the same reason: the preview
  /// stages rows and calls Stripe on the default 30s timeout, so a slow
  /// moment must never leave the member on a blank screen.
  previewFailed,

  /// The start call failed outright (a 5xx or a dropped connection).
  /// **Nothing was charged** — the copy says so, because that is the only
  /// question the member has.
  paymentFailed,

  /// A start attempt was already sent for this idempotency key and its
  /// outcome is unknown, so the kiosk will NOT send it again — an auto-retry
  /// is the one thing that could double-charge. The desk resolves it.
  paymentUnconfirmed,

  /// The member ASKED for help after a decline. It is never forced on them —
  /// a refused card is retryable for as long as they want to keep trying.
  /// Everything already committed stays committed: this is a handoff, never
  /// an abandon.
  cardDeclined;

  /// Whether the stop screen offers a "Try again" that returns to the step.
  ///
  /// Only the two pure-read failures qualify. A money path never auto-retries
  /// and a duplicate never resolves itself, so neither may offer a button that
  /// implies it might.
  bool get isRetryable =>
      this == plansUnavailable || this == previewFailed;
}

/// One waiver signed during THIS signup — WHO it was signed for, the id (so
/// it is never presented to that person twice), the waiver's name and the
/// legal name that was typed, both of which the review screen renders back.
///
/// **[memberId] is what makes the group run correct.** Two children on the
/// same plan must each sign that plan's liability waiver; keying the "already
/// signed" set on the waiver id alone would silently skip the second child's
/// signature and hand the backend an unsigned member at the start call.
///
/// A signature is COMMITTED the moment it is recorded, so this list only ever
/// grows: walking Back never un-signs anything.
class KioskSignedWaiver extends Equatable {
  /// The member the signature binds — never the signer, who may be a parent.
  final String memberId;

  final String waiverId;
  final String name;
  final String signerName;

  const KioskSignedWaiver({
    required this.memberId,
    required this.waiverId,
    required this.name,
    required this.signerName,
  });

  @override
  List<Object?> get props => [memberId, waiverId, name, signerName];
}

/// One EXISTING member offered as a match — for a payee being added (E2), or
/// for the person who started the signup and turns out to already have an
/// account here.
///
/// It is the single shape behind every route into that offer — the payee 409's
/// `matches`, the payer 409's, and a name-search row — so one confirm card
/// renders all of them.
///
/// **It carries only what a lobby iPad may print**: a full name (a first name
/// plus an initial collides silently) and an email the card masks before it
/// renders. Never a phone, never a photo, never a membership status.
class KioskSignupMatch extends Equatable {
  final String memberId;
  final String firstName;
  final String lastName;
  final String? email;

  const KioskSignupMatch({
    required this.memberId,
    required this.firstName,
    required this.lastName,
    this.email,
  });

  String get fullName => '$firstName $lastName'.trim();

  @override
  List<Object?> get props => [memberId, firstName, lastName, email];
}

/// One person in the signup's roster. The payer is always index 0; both the
/// payer and every payee may be new or existing.
///
/// [memberId] is null until `createMember` (or, for an existing payee, a
/// match) supplies one — that null is the "nothing has been written yet"
/// signal the whole abandon story rests on.
class KioskSignupPerson extends Equatable {
  /// Set once this person exists on the backend. Null before that.
  final String? memberId;

  final String firstName;
  final String lastName;

  /// REQUIRED for every person, payer and payee alike — it keeps the
  /// duplicate gate live for everyone and gives each person app sign-in.
  final String email;

  final String? phone;

  /// Date of birth, collected on the wheel (never free text). Sent as
  /// `YYYY-MM-DD`.
  final DateTime? dob;

  final String? address;
  final String? ecName;
  final String? ecPhone;
  final String? ecEmail;

  /// Whether this person pays for the whole cart. Exactly one person is the
  /// payer, and it is always the person who started the signup.
  final bool isPayer;

  /// Whether this person is getting a membership (and so needs a plan, its
  /// waivers, and a line in the cart).
  ///
  /// **It is the same control on EVERY roster row, and it defaults ON** —
  /// payer, payee, adopted or created here. A payer-only special case was one
  /// more thing to explain on a screen that has to explain itself.
  ///
  /// **At least one person must keep it ticked.** A signup with nothing in the
  /// cart would send `memberships: []` and take a 400, so the roster cannot
  /// leave until somebody is getting one — see [anyoneTraining].
  final bool training;

  /// True when this person was matched to an EXISTING member rather than
  /// created here.
  ///
  /// It is the "the kiosk does not own this record" marker: their stored
  /// details are never shown on a shared screen, so there is nothing here to
  /// edit — the roster offers them no Edit affordance and they skip the
  /// per-person details step entirely.
  final bool wasExisting;

  /// True once `PUT /members/{id}/link` has authorized the payer to pay for
  /// this person. **It is the group flow's commit marker**: there is no unlink
  /// call, so a linked person can no longer be removed from the roster, and
  /// the start request is not assembled at all until every payee carries it.
  final bool linked;

  /// True when this member has ALREADY had a trial at this gym, so no trial
  /// plan is selectable for them — trials are one to a member.
  ///
  /// It is read once, at plan-pick, and only for a person whose account
  /// predates this signup: somebody created here has no history by
  /// construction. The read **fails OPEN** (see
  /// `KioskSignupCubit._loadPlanEligibility`), so this stays false when the
  /// check cannot answer.
  final bool hadTrial;

  /// The RECURRING plans this member already holds `active` or `frozen` — the
  /// plans the backend would refuse to start again for them.
  ///
  /// **It lives on the PERSON, never on the state root, and that is the group
  /// privacy guard.** The plan step is walked once per training person under a
  /// fixed layout, so a state-root map would be one stale read away from
  /// printing a parent's membership on a child's turn. Per-person storage makes
  /// that leak unrepresentable, exactly as [hadTrial] does.
  ///
  /// Read from the SAME `getMemberDetail` response as [hadTrial] (no second
  /// request) and it **fails OPEN** for the same reason: on a read error the
  /// kiosk does not know WHICH plan they hold, so failing closed would block
  /// every plan and turn a paying customer away.
  final List<String> heldRecurringPlanIds;

  final KioskSignupDetailsStatus detailsStatus;

  /// The plan this person picked. Null until the plans step.
  final String? selectedPlanId;

  const KioskSignupPerson({
    this.memberId,
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone,
    this.dob,
    this.address,
    this.ecName,
    this.ecPhone,
    this.ecEmail,
    this.isPayer = false,
    this.training = true,
    this.wasExisting = false,
    this.linked = false,
    this.hadTrial = false,
    this.heldRecurringPlanIds = const [],
    this.detailsStatus = KioskSignupDetailsStatus.none,
    this.selectedPlanId,
  });

  /// True once this person exists on the backend — the marker that turns a
  /// second Continue from a committed step into a PUT instead of a create.
  bool get isCreated => memberId != null;

  static const Object _keep = Object();

  KioskSignupPerson copyWith({
    Object? memberId = _keep,
    String? firstName,
    String? lastName,
    String? email,
    Object? phone = _keep,
    Object? dob = _keep,
    Object? address = _keep,
    Object? ecName = _keep,
    Object? ecPhone = _keep,
    Object? ecEmail = _keep,
    bool? isPayer,
    bool? training,
    bool? wasExisting,
    bool? linked,
    bool? hadTrial,
    List<String>? heldRecurringPlanIds,
    KioskSignupDetailsStatus? detailsStatus,
    Object? selectedPlanId = _keep,
  }) {
    return KioskSignupPerson(
      memberId:
          identical(memberId, _keep) ? this.memberId : memberId as String?,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: identical(phone, _keep) ? this.phone : phone as String?,
      dob: identical(dob, _keep) ? this.dob : dob as DateTime?,
      address: identical(address, _keep) ? this.address : address as String?,
      ecName: identical(ecName, _keep) ? this.ecName : ecName as String?,
      ecPhone: identical(ecPhone, _keep) ? this.ecPhone : ecPhone as String?,
      ecEmail: identical(ecEmail, _keep) ? this.ecEmail : ecEmail as String?,
      isPayer: isPayer ?? this.isPayer,
      training: training ?? this.training,
      wasExisting: wasExisting ?? this.wasExisting,
      linked: linked ?? this.linked,
      hadTrial: hadTrial ?? this.hadTrial,
      heldRecurringPlanIds:
          heldRecurringPlanIds ?? this.heldRecurringPlanIds,
      detailsStatus: detailsStatus ?? this.detailsStatus,
      selectedPlanId: identical(selectedPlanId, _keep)
          ? this.selectedPlanId
          : selectedPlanId as String?,
    );
  }

  @override
  List<Object?> get props => [
        memberId,
        firstName,
        lastName,
        email,
        phone,
        dob,
        address,
        ecName,
        ecPhone,
        ecEmail,
        isPayer,
        training,
        wasExisting,
        linked,
        hadTrial,
        heldRecurringPlanIds,
        detailsStatus,
        selectedPlanId,
      ];
}

/// Immutable state of the `KioskSignupCubit` — one FLAT state carrying the
/// current [step], the roster, and everything each step renders. It mirrors
/// `KioskFlowState`'s shape deliberately, including the `_keep` sentinel in
/// [copyWith]: a nullable field is preserved unless an explicit `null` is
/// passed, which is how a fresh failure drops a stale value.
///
/// Nothing here survives the flow: the cubit is provided by
/// `KioskSignupScreen`, so leaving the view unmounts the subtree and disposes
/// every field on this object. That is the shared-iPad privacy contract made
/// structural rather than remembered.
class KioskSignupState extends Equatable {
  final KioskSignupStep step;

  /// The roster. Index 0 is always the payer and always exists.
  final List<KioskSignupPerson> persons;

  /// Which person the per-person steps ([personDetails], [plans], [waivers])
  /// are currently acting on.
  final int activePersonIndex;

  /// The steps whose work has been COMMITTED to the backend.
  ///
  /// This is ruling 11's marker. Back into [KioskSignupStep.details] /
  /// [KioskSignupStep.extraDetails] after the member exists is allowed (so a
  /// typo'd email is fixable), but Continue from a committed step fires
  /// `updateMember` (PUT), never a second `createMember` — a second create
  /// would dead-end the member on the duplicate stop for their own
  /// just-created account.
  final Set<KioskSignupStep> committedSteps;

  /// A network call for the current step is in flight — the primary is
  /// disabled and shows its busy state.
  final bool submitting;

  // ── Group: the roster (E1) ──
  /// The payee being added, held OFF the roster until the backend has made
  /// them. A create that 409s leaves this set (it is the "You typed" half of
  /// the match card) and the roster untouched, so backing out of the offer
  /// drops a draft rather than stranding a member with no id on the roster.
  final KioskSignupPerson? pendingPayee;

  /// The optional-details PUT for a payee failed. An INLINE retry, never a
  /// stop: the person already exists, and ending a family signup because an
  /// optional address didn't save would orphan everyone on the roster.
  final bool personDetailsFailed;

  // ── Group: find an existing member (E2) ──
  /// The ONE existing member being offered as a match — a payee's, or the
  /// person standing at the iPad confirming their own account.
  ///
  /// Reached three ways — a 409 on a create, a name search on the payee match
  /// step, or a name search on [KioskSignupStep.identify] — and it is
  /// deliberately singular: a shared screen offers one identity to confirm,
  /// not a list of the gym's members to browse.
  final KioskSignupMatch? matchCandidate;

  /// The match on screen came from [KioskSignupStep.identify] — the member
  /// tapped their own name — rather than from a duplicate 409.
  ///
  /// It decides where "No, that's not me" goes. On the identify path nothing
  /// has committed and they simply mis-tapped, so it returns to the search;
  /// on the 409 path the create has already been refused and the kiosk cannot
  /// proceed, so it is the terminal stop.
  final bool payerMatchFromIdentify;

  /// The match step is showing the name search rather than the confirm card.
  final bool matchSearchOpen;

  /// What is typed in that search.
  final String matchQuery;
  final bool matchSearching;
  final bool matchSearchFailed;

  /// Name-search matches for the "add someone who's already a member" step
  /// AND for the payer picker — ONE search, one debounce, one sequence guard,
  /// because the two pickers are never open at the same time.
  ///
  /// Never confused with a 409's duplicate `matches`, which are never
  /// rendered as a LIST anywhere on the kiosk.
  final List<MemberRow> matches;

  // ── The payer picker ──
  /// Which roster person the remove confirmation is asking about, or null
  /// when it is not up. Removal is destructive and there is no undo, so the
  /// trash control asks before it acts.
  final int? removeConfirmIndex;

  /// The last CRM search row picked on the payer picker is already ON this
  /// roster — a REDIRECT, not a rejection.
  ///
  /// They are listed above and directly pickable there, so the picker says so
  /// inline rather than refusing. It stays a state of its own because the CRM
  /// path must refuse to INSERT a second entry for one member: two cart items
  /// for the same person is a double charge waiting to happen.
  final bool payerAlreadyInSignup;

  // ── Plans (D3) ──
  /// The gym's kiosk-eligible plans — `isPublic && activePrice != null` —
  /// warmed once at entry so the step opens with no network wait.
  final List<MembershipPlanResponse> plans;
  final bool plansLoading;
  final bool plansFailed;

  // ── Waivers (D4 / E3) ──
  /// The waivers this step has to walk, in order — the selected plan's
  /// `waiverIds` (or, after a server waiver gate, exactly the ids it named).
  /// It is the numbering behind "waiver 1 of N", so it keeps entries that are
  /// already signed rather than shrinking as they are.
  final List<String> waiverQueue;

  /// Which entry of [waiverQueue] is on screen.
  final int waiverIndex;

  /// The loaded waiver, body included. Null while it loads.
  final WaiverResponse? waiver;
  final bool waiverLoading;

  /// The last waiver read or sign failed. It is an INLINE retry, never a
  /// terminal stop: a member has already been created by this point, and the
  /// escape is still in the gutter if they want out.
  final bool waiverFailed;

  /// The gym republished this waiver between the read and the sign (409). The
  /// body is reloaded and the member must read and sign the NEW version.
  final bool waiverStale;

  /// Waivers signed during THIS signup. A signed waiver stays signed across
  /// Back navigation — it is committed, and nothing un-signs it.
  final List<KioskSignedWaiver> signedWaivers;

  // ── Group: the per-person waiver run (E3, ruling 9) ──
  /// The roster indexes the waiver phase walks, in order: every payee first
  /// (each one's payer-auth link, then their own liability waivers), and the
  /// payer's own liability waiver LAST. That is how a family actually passes
  /// a tablet — once per person, not once per document.
  final List<int> waiverPersonQueue;

  /// Where in [waiverPersonQueue] the run is.
  final int waiverPersonIndex;

  /// The waiver on screen is the PAYER-AUTH agreement for the active payee,
  /// not that payee's liability waiver. The signer is the payer every time.
  final bool payerAuthPending;

  /// The loaded authorized-payer agreement. Null while it loads.
  final AuthorizedPayerWaiver? payerAuthWaiver;
  final bool payerAuthLoading;
  final bool payerAuthFailed;

  /// The gym republished the payer-auth waiver between the read and the link
  /// (409). The body is reloaded and the payer signs the NEW text.
  final bool payerAuthStale;

  /// Exactly the (member, waiver) pairs a server waiver gate (422) named.
  ///
  /// The server is authoritative, so these are folded INTO the person's own
  /// liability queue on the way round again — a plan whose `waiverIds` no
  /// longer matches what the backend demands would otherwise loop the member
  /// through a run that never satisfies the gate.
  final List<WaiverGateItem> waiverGate;

  // ── Card (D5) ──
  /// Which card-entry ATTEMPT the field is on — a nonce bumped by [retryCard]
  /// after a decline. It keys the Stripe `CardField` (`ValueKey`), so returning
  /// to the card step for a retry mounts a brand-new, empty Stripe iframe rather
  /// than reusing the one still holding the declined number — the field's web
  /// platform view is cached across mounts, so without a changing key a member
  /// literally cannot type a new card after a decline.
  final int cardAttempt;

  /// The freshly-entered card's Stripe payment-method id. Only ever a card
  /// typed in the current signup, for the payer created in the current
  /// signup — the fresh-card law.
  final String? paymentMethodId;

  /// The card's brand and last four, straight off the tokenized
  /// PaymentMethod — the only card facts the kiosk ever holds. Rendered on
  /// the review, paying and declined screens so the member can see which card
  /// is being charged.
  final String? cardBrand;
  final String? cardLast4;

  // ── Review / pay (D6–D8) ──
  final MemberMembershipsStartPreview? preview;
  final bool previewLoading;

  /// The idempotency key for the current start attempt. A deliberate retry
  /// after a decline mints a NEW key; a double-tap reuses this one.
  final String? idempotencyKey;

  /// The landed start response — the per-person outcome the results screen
  /// draws and the retry set is derived from.
  ///
  /// **One source, so the displayed set and the retry set cannot drift.** A
  /// second field holding the failures independently is exactly the drift
  /// hazard this repo's one-source rules exist to avoid, so [failedItems] is a
  /// getter over this rather than a field of its own.
  ///
  /// On a partial RETRY the response is MERGED into this one (see
  /// `KioskSignupCubit._enterResults`), so the receipt keeps listing the
  /// memberships an earlier attempt created — a screen headed "every
  /// membership below started today" that omitted one would lie by omission.
  final MemberMembershipsStartResponse? startResult;

  /// Seconds left on the welcome screen's auto-return. 0 off the welcome.
  final int welcomeCountdown;

  // ── Blocking popups (the decline, the plan block) ──
  /// Which plan-block popup is up over the plan grid, or null when none is.
  ///
  /// One popup, one reason enum — the alternative was a second modal for the
  /// second reason, which would fork the kiosk's one modal vocabulary.
  final KioskPlanBlockReason? planBlockActive;

  /// Seconds left on whichever blocking popup is up — the decline, the results
  /// receipt or the plan block. 0 when none is.
  ///
  /// **Every blocking overlay carries a visible countdown**: this is a shared
  /// community iPad and no screen may hold it forever. Expiry runs the
  /// ordinary `abandon()`, so the session's flow count is released exactly
  /// once by the one latch every other exit uses.
  final int popupCountdown;

  // ── Terminal stop ──
  final KioskSignupStopReason? stopReason;

  /// Seconds left on the stop screen's auto-return. 0 off the stop screen.
  final int stopCountdown;

  // ── Flow-idle guard (the signup lane's own 5-min / 30-s clock) ──
  final bool idleWarningActive;
  final int idleCountdown;

  // ── Abandon ──
  /// The "Start over?" confirmation is up. Shown only from the steps where
  /// real work would die (card / review); every earlier step abandons on the
  /// first tap. The 5-minute clock keeps running behind it.
  final bool abandonConfirmActive;

  /// The flow is over and the surface must return home. `KioskSignupScreen`
  /// watches this and calls `KioskFlowCubit.goHome()` — the ONE abandon path.
  /// The cubit cannot navigate itself, so it raises this instead.
  final bool abandoned;

  const KioskSignupState({
    this.step = KioskSignupStep.entry,
    this.persons = const [KioskSignupPerson(isPayer: true)],
    this.activePersonIndex = 0,
    this.committedSteps = const {},
    this.submitting = false,
    this.pendingPayee,
    this.personDetailsFailed = false,
    this.matchCandidate,
    this.payerMatchFromIdentify = false,
    this.matchSearchOpen = false,
    this.matchQuery = '',
    this.matchSearching = false,
    this.matchSearchFailed = false,
    this.matches = const [],
    this.payerAlreadyInSignup = false,
    this.removeConfirmIndex,
    this.plans = const [],
    this.plansLoading = false,
    this.plansFailed = false,
    this.waiverQueue = const [],
    this.waiverIndex = 0,
    this.waiver,
    this.waiverLoading = false,
    this.waiverFailed = false,
    this.waiverStale = false,
    this.signedWaivers = const [],
    this.waiverPersonQueue = const [],
    this.waiverPersonIndex = 0,
    this.payerAuthPending = false,
    this.payerAuthWaiver,
    this.payerAuthLoading = false,
    this.payerAuthFailed = false,
    this.payerAuthStale = false,
    this.waiverGate = const [],
    this.cardAttempt = 0,
    this.paymentMethodId,
    this.cardBrand,
    this.cardLast4,
    this.preview,
    this.previewLoading = false,
    this.idempotencyKey,
    this.startResult,
    this.welcomeCountdown = 0,
    this.planBlockActive,
    this.popupCountdown = 0,
    this.stopReason,
    this.stopCountdown = 0,
    this.idleWarningActive = false,
    this.idleCountdown = 0,
    this.abandonConfirmActive = false,
    this.abandoned = false,
  });

  /// The per-person outcomes the landed start reported, in the RESPONSE's own
  /// order. The results screen re-orders them by the roster.
  List<MemberMembershipsStartResultItem> get startItems =>
      startResult?.results ?? const [];

  /// The items a start refused — **what "declined" and "partial" both mean.**
  /// A decline arrives as a RESULT in a 2xx body, never as an HTTP error.
  ///
  /// Derived from [startResult] rather than stored, so the set the receipt
  /// draws and the set a retry re-sends are the same set by construction.
  List<MemberMembershipsStartResultItem> get failedItems =>
      startResult?.failed ?? const [];

  /// Whether every membership in the landed start was created — the results
  /// screen's own branch, and the gate on the two-charges note.
  ///
  /// An `unknown` status is neither created nor failed, so it falls OUT of
  /// this: the member is never told "you're all set" about a row the backend
  /// would not confirm.
  bool get allCreated =>
      startItems.isNotEmpty && startItems.every((r) => r.isCreated);

  /// The person the per-person steps are acting on. Index 0 (the payer) is
  /// the fallback, so this can never throw on a corrupt index.
  KioskSignupPerson get activePerson =>
      (activePersonIndex >= 0 && activePersonIndex < persons.length)
          ? persons[activePersonIndex]
          : persons.first;

  /// The payer — the first roster entry, which is the payer WHENEVER one
  /// exists. Only valid where [hasPayer] is guaranteed; prefer [payerOrNull]
  /// anywhere the payer may have been deleted.
  KioskSignupPerson get payer => persons.first;

  /// Whether the signup currently has a payer.
  ///
  /// The payer, when one exists, is always roster index 0. Deleting the payer
  /// (a group-only act) clears the designation and **nothing is auto-assigned**
  /// — [hasPayer] is false until the member chooses a new one through the
  /// picker. A no-payer state can exist ONLY on the People and payer-pick
  /// steps; it blocks Continue and can never reach Pay.
  bool get hasPayer => persons.isNotEmpty && persons.first.isPayer;

  /// The payer, or null once the designation has been cleared by deleting them
  /// (see [hasPayer]). Every money-path read goes through this so a no-payer
  /// signup can never assemble a charge.
  KioskSignupPerson? get payerOrNull => hasPayer ? persons.first : null;

  /// Whether the roster carries anyone besides the payer, which is what
  /// re-labels the step rail from the 6-step solo template to the 7-step
  /// group one (ruling 8).
  bool get isGroup => persons.length > 1;

  /// The ids of every waiver signed in this signup, across everyone.
  List<String> get signedWaiverIds => [
        for (final signed in signedWaivers) signed.waiverId,
      ];

  /// The ids [memberId] has signed — the skip list that keeps a waiver from
  /// being presented to the SAME person twice, while still presenting the same
  /// document to the next child on the roster.
  List<String> signedWaiverIdsFor(String? memberId) => [
        for (final signed in signedWaivers)
          if (memberId != null && signed.memberId == memberId) signed.waiverId,
      ];

  /// Every roster index that needs a plan, in roster order. The payer is in it
  /// only while their own membership check is ticked — a parent paying for
  /// their kids is `payer_member_id` and nothing else.
  List<int> get trainingPersonIndexes => [
        for (var i = 0; i < persons.length; i++)
          if (persons[i].training) i,
      ];

  /// Whether anybody on the roster is getting a membership — **the
  /// empty-cart guard.**
  ///
  /// Every person's membership check can be unticked individually, so a member
  /// can reach the all-unticked state by hand. It sends `memberships: []` and
  /// takes a 400, so the roster cannot leave while it holds: the People step
  /// disables Continue and says plainly that somebody needs a membership,
  /// rather than presenting a dead button.
  bool get anyoneTraining => persons.any((p) => p.training);

  /// Whether the payer may still be handed to an EXISTING member.
  ///
  /// **The moment anything commits, the payer is baked in.** A payer-auth link
  /// names the payer server-side and there is no unlink call, and a signature
  /// is committed the instant it is recorded — so swapping the payer after
  /// either would leave the roster authorized to somebody who is no longer
  /// paying, and the start call would then be assembled against a payer the
  /// backend never authorized. The offer therefore disappears rather than
  /// becoming a control that quietly corrupts the cart.
  ///
  /// While nothing has committed, changing who pays is **freely repeatable** —
  /// there is no cap on the number of swaps. The demoted former payer (an
  /// adopted outsider included) simply becomes a normal roster payee who keeps
  /// their membership/training choice and is removable via the trash while
  /// unlinked, so no swap strands anyone. A signature or a link is the ONE
  /// thing that pins the payer.
  bool get canSwitchPayer => hasPayer && canAssignPayer;

  /// Whether a payer may be seated right now — either switching an existing one
  /// ([canSwitchPayer]) or choosing a first one after the payer was deleted.
  ///
  /// The single gate is that nothing has committed the payer: no payee linked,
  /// no signature recorded. There is no unlink call, and a signature pins the
  /// payer server-side, so a change after either would corrupt the cart. Before
  /// either, seating a payer writes nothing a later change could strand — the
  /// person it displaces is left as an ordinary unlinked roster payee — so the
  /// seat stays freely re-assignable, whether or not a payer already exists and
  /// whether or not that payer was an adopted outsider.
  bool get canAssignPayer =>
      signedWaivers.isEmpty &&
      !persons.any((p) => p.linked);

  /// The roster indexes the payer picker offers, in roster order.
  ///
  /// While a payer exists it is NOT among them — picking whoever is already
  /// paying is a no-op dressed as a choice. Once the payer has been DELETED
  /// there is no one to exclude, so every created person (index 0 included) is
  /// a candidate. Anybody without a `memberId` does not exist to pay yet and is
  /// skipped either way.
  List<int> get payerCandidateIndexes => [
        for (var i = 0; i < persons.length; i++)
          if (persons[i].memberId != null && !(hasPayer && i == 0)) i,
      ];

  /// Whether every payee has been authorized. The start call NEVER links, so
  /// this has to be true before a request is even assembled.
  bool get everyPayeeLinked {
    for (var i = 1; i < persons.length; i++) {
      if (!persons[i].linked) return false;
    }
    return true;
  }

  /// Whether [index] may still be taken off the roster.
  ///
  /// The trash control disappears the moment that person's link (or a
  /// signature of theirs) has committed: **there is no unlink call**, so removal
  /// is only offered while it is still free. A person created but not yet linked
  /// simply drops out of the cart — their member shell is harmless and surfaces
  /// in the staff "Incomplete" list.
  ///
  /// **The payer is removable too** (founder ruling: nobody on the roster is
  /// special), but only in a group and only while nothing has committed against
  /// them — no payee linked, no signature recorded. Deleting a payer a payee has
  /// already authorized, or after any signature, would strand committed state,
  /// so the payer's trash disappears exactly when a payer SWITCH would be
  /// refused. Unlike a switch, removal takes them off the roster entirely, so
  /// the "don't strand an adopted outsider" rule does not apply — an adopted
  /// payer can be deleted, and the flow then asks who pays next.
  bool canRemovePerson(int index) {
    if (index < 0 || index >= persons.length) return false;
    // Never the sole person: removing the only person is abandoning the whole
    // signup, which is what "Start over" is for.
    if (persons.length <= 1) return false;
    final person = persons[index];
    if (person.isPayer) {
      return signedWaivers.isEmpty && !persons.any((p) => p.linked);
    }
    if (person.linked) return false;
    final id = person.memberId;
    if (id != null && signedWaivers.any((w) => w.memberId == id)) return false;
    return true;
  }

  /// The waiver on screen, or null when the queue is exhausted.
  String? get currentWaiverId =>
      (waiverIndex >= 0 && waiverIndex < waiverQueue.length)
          ? waiverQueue[waiverIndex]
          : null;

  /// The warmed plan carrying [planId], or null when it isn't offered.
  MembershipPlanResponse? planById(String? planId) {
    if (planId == null) return null;
    for (final plan in plans) {
      if (plan.planId == planId) return plan;
    }
    return null;
  }

  /// The plan the active person picked.
  MembershipPlanResponse? get selectedPlan =>
      planById(activePerson.selectedPlanId);

  /// Why [plan] is closed to the person currently picking, or null when it is
  /// open to them.
  KioskPlanBlockReason? planBlockReason(MembershipPlanResponse plan) =>
      planBlockReasonFor(activePerson, plan);

  /// Why [plan] is closed to [person] specifically — the per-person form, so a
  /// late eligibility answer can re-test a pick that has already been made.
  ///
  /// **Two rules, two scopes, and neither may be widened:**
  ///
  /// * [KioskPlanBlockReason.trialUsed] — **any prior trial blocks EVERY
  ///   trial**, not just the one they had: at the kiosk a trial is one to a
  ///   member. Staff can still grant a repeat trial from the CRM; this is a
  ///   kiosk-only rule, not a backend one.
  /// * [KioskPlanBlockReason.alreadyOnPlan] — a RECURRING plan they already
  ///   hold. This one mirrors the backend's own conflict SQL exactly
  ///   (`plan_type = 'recurring'` AND `status IN ('active','frozen')`, keyed on
  ///   `plan_id`), so a member on "Unlimited Monthly" may still buy a
  ///   DIFFERENT recurring plan. **It is deliberately NARROWER than the CRM's
  ///   own `disabledPlanReasons`** (which also blocks a held trial plan and an
  ///   `overdue` status): at a desk a false block is visible and staff reason
  ///   about it, while at a kiosk it silently turns away a paying customer with
  ///   no override. Do not "align" this to the CRM's looser set.
  KioskPlanBlockReason? planBlockReasonFor(
    KioskSignupPerson person,
    MembershipPlanResponse plan,
  ) {
    if (plan.planType == PlanType.trial && person.hadTrial) {
      return KioskPlanBlockReason.trialUsed;
    }
    if (plan.planType == PlanType.recurring &&
        person.heldRecurringPlanIds.contains(plan.planId)) {
      return KioskPlanBlockReason.alreadyOnPlan;
    }
    return null;
  }

  /// The catalogue names of the recurring plans the ACTIVE person already
  /// holds, in the catalogue's own order — what the plan step's notice and the
  /// already-on-plan popup both state.
  ///
  /// A held plan the gym no longer offers resolves to nothing and is silently
  /// omitted: it cannot be picked, so there is nothing to prevent, and storing
  /// its name would create a second source of truth for something the warmed
  /// catalogue owns.
  List<String> get heldPlanNames {
    final held = activePerson.heldRecurringPlanIds;
    if (held.isEmpty) return const [];
    return [
      for (final plan in plans)
        if (held.contains(plan.planId)) plan.planName,
    ];
  }

  /// Whether EVERY training person's pick is a trial — the discriminator
  /// behind the review's "Sign Trial" / "Sign Membership" verb.
  ///
  /// A mixed group cart falls to "Membership", which is true of the cart as a
  /// whole; an incomplete cart falls there too, because a plan nobody has
  /// picked yet cannot make the whole cart a trial.
  bool get cartAllTrial {
    var any = false;
    for (final person in persons) {
      if (!person.training) continue;
      final plan = planById(person.selectedPlanId);
      if (plan == null || plan.planType != PlanType.trial) return false;
      any = true;
    }
    return any;
  }

  /// Whether anything in the cart bills again after today.
  ///
  /// It decides the one CONDITIONAL card fact ("Cancel any time at the front
  /// desk"), which is only true of something that keeps billing. It no longer
  /// decides `set_default`: the kiosk always saves the entered card as the
  /// payer's default, whatever the cart holds (see
  /// `KioskSignupCubit._buildStartRequest`).
  bool get cartHasRecurring {
    for (final person in persons) {
      if (!person.training) continue;
      if (planById(person.selectedPlanId)?.planType == PlanType.recurring) {
        return true;
      }
    }
    return false;
  }

  /// **The ONLY arithmetic the kiosk does on money**: the one-time invoice
  /// plus the recurring amount due now, both straight off the preview.
  ///
  /// This mirrors the CRM's own `_totalDueToday`
  /// (`start_preview_step.dart:281-284`) and is safe here **only because the
  /// kiosk pins `prorate_to_anchor`**: the CRM reads `_effectiveDueNow`, which
  /// nulls the due-now half for a `no_charge` proration, and the kiosk never
  /// offers that choice. A price is never derived from a plan row.
  int get dueTodayMinorUnits =>
      (preview?.oneTime?.total ?? 0) + (preview?.dueNow?.total ?? 0);

  /// True when the payer's statement will show TWO charges today — a non-zero
  /// one-time invoice AND a non-zero recurring amount due now.
  ///
  /// It tests the AMOUNTS, exactly like the CRM's `_chargedTwiceToday`
  /// (`start_preview_step.dart:276-278`), never nullness and never
  /// `preview.recurring`: a $0 one-time line is a present invoice with nothing
  /// on it, and calling that "two charges" would be a lie about the member's
  /// own bank statement.
  bool get chargedTwiceToday =>
      (preview?.oneTime?.total ?? 0) > 0 && (preview?.dueNow?.total ?? 0) > 0;

  /// True when today's charge is a PART period — the kiosk pins
  /// `prorate_to_anchor`, so a member joining mid-cycle pays only the rest of
  /// it and then the full amount from the anchor.
  ///
  /// It is read off the preview lines' own `is_proration`, **never inferred
  /// from "the two figures differ"**: they can differ for other reasons, and
  /// telling a member their charge is prorated when it is not is a false
  /// statement about their money.
  bool get chargedProrated {
    for (final line in [
      ...?preview?.oneTime?.lines,
      ...?preview?.dueNow?.lines,
    ]) {
      if (line.isProration) return true;
    }
    return false;
  }

  /// The billing-period end a part-period charge runs up to, and the day the
  /// full amount first bills — the preview's own `next_payment_date`, never a
  /// date this client works out.
  DateTime? get prorationUntil =>
      preview?.dueNow?.nextPaymentAt ?? preview?.recurring?.nextPaymentAt;

  /// The currency every figure on the review is rendered in — whichever half
  /// of the preview exists, in the CRM's own order of preference.
  String get currency =>
      preview?.oneTime?.currency ??
      preview?.dueNow?.currency ??
      preview?.recurring?.currency ??
      'usd';

  static const Object _keep = Object();

  KioskSignupState copyWith({
    KioskSignupStep? step,
    List<KioskSignupPerson>? persons,
    int? activePersonIndex,
    Set<KioskSignupStep>? committedSteps,
    bool? submitting,
    Object? pendingPayee = _keep,
    bool? personDetailsFailed,
    Object? matchCandidate = _keep,
    bool? payerMatchFromIdentify,
    bool? matchSearchOpen,
    String? matchQuery,
    bool? matchSearching,
    bool? matchSearchFailed,
    List<MemberRow>? matches,
    bool? payerAlreadyInSignup,
    Object? removeConfirmIndex = _keep,
    List<MembershipPlanResponse>? plans,
    bool? plansLoading,
    bool? plansFailed,
    List<String>? waiverQueue,
    int? waiverIndex,
    Object? waiver = _keep,
    bool? waiverLoading,
    bool? waiverFailed,
    bool? waiverStale,
    List<KioskSignedWaiver>? signedWaivers,
    List<int>? waiverPersonQueue,
    int? waiverPersonIndex,
    bool? payerAuthPending,
    Object? payerAuthWaiver = _keep,
    bool? payerAuthLoading,
    bool? payerAuthFailed,
    bool? payerAuthStale,
    List<WaiverGateItem>? waiverGate,
    int? cardAttempt,
    Object? paymentMethodId = _keep,
    Object? cardBrand = _keep,
    Object? cardLast4 = _keep,
    Object? preview = _keep,
    bool? previewLoading,
    Object? idempotencyKey = _keep,
    Object? startResult = _keep,
    int? welcomeCountdown,
    Object? planBlockActive = _keep,
    int? popupCountdown,
    Object? stopReason = _keep,
    int? stopCountdown,
    bool? idleWarningActive,
    int? idleCountdown,
    bool? abandonConfirmActive,
    bool? abandoned,
  }) {
    return KioskSignupState(
      step: step ?? this.step,
      persons: persons ?? this.persons,
      activePersonIndex: activePersonIndex ?? this.activePersonIndex,
      committedSteps: committedSteps ?? this.committedSteps,
      submitting: submitting ?? this.submitting,
      pendingPayee: identical(pendingPayee, _keep)
          ? this.pendingPayee
          : pendingPayee as KioskSignupPerson?,
      personDetailsFailed: personDetailsFailed ?? this.personDetailsFailed,
      matchCandidate: identical(matchCandidate, _keep)
          ? this.matchCandidate
          : matchCandidate as KioskSignupMatch?,
      payerMatchFromIdentify:
          payerMatchFromIdentify ?? this.payerMatchFromIdentify,
      matchSearchOpen: matchSearchOpen ?? this.matchSearchOpen,
      matchQuery: matchQuery ?? this.matchQuery,
      matchSearching: matchSearching ?? this.matchSearching,
      matchSearchFailed: matchSearchFailed ?? this.matchSearchFailed,
      matches: matches ?? this.matches,
      payerAlreadyInSignup: payerAlreadyInSignup ?? this.payerAlreadyInSignup,
      removeConfirmIndex: identical(removeConfirmIndex, _keep)
          ? this.removeConfirmIndex
          : removeConfirmIndex as int?,
      plans: plans ?? this.plans,
      plansLoading: plansLoading ?? this.plansLoading,
      plansFailed: plansFailed ?? this.plansFailed,
      waiverQueue: waiverQueue ?? this.waiverQueue,
      waiverIndex: waiverIndex ?? this.waiverIndex,
      waiver: identical(waiver, _keep)
          ? this.waiver
          : waiver as WaiverResponse?,
      waiverLoading: waiverLoading ?? this.waiverLoading,
      waiverFailed: waiverFailed ?? this.waiverFailed,
      waiverStale: waiverStale ?? this.waiverStale,
      signedWaivers: signedWaivers ?? this.signedWaivers,
      waiverPersonQueue: waiverPersonQueue ?? this.waiverPersonQueue,
      waiverPersonIndex: waiverPersonIndex ?? this.waiverPersonIndex,
      payerAuthPending: payerAuthPending ?? this.payerAuthPending,
      payerAuthWaiver: identical(payerAuthWaiver, _keep)
          ? this.payerAuthWaiver
          : payerAuthWaiver as AuthorizedPayerWaiver?,
      payerAuthLoading: payerAuthLoading ?? this.payerAuthLoading,
      payerAuthFailed: payerAuthFailed ?? this.payerAuthFailed,
      payerAuthStale: payerAuthStale ?? this.payerAuthStale,
      waiverGate: waiverGate ?? this.waiverGate,
      cardAttempt: cardAttempt ?? this.cardAttempt,
      paymentMethodId: identical(paymentMethodId, _keep)
          ? this.paymentMethodId
          : paymentMethodId as String?,
      cardBrand:
          identical(cardBrand, _keep) ? this.cardBrand : cardBrand as String?,
      cardLast4:
          identical(cardLast4, _keep) ? this.cardLast4 : cardLast4 as String?,
      preview: identical(preview, _keep)
          ? this.preview
          : preview as MemberMembershipsStartPreview?,
      previewLoading: previewLoading ?? this.previewLoading,
      idempotencyKey: identical(idempotencyKey, _keep)
          ? this.idempotencyKey
          : idempotencyKey as String?,
      startResult: identical(startResult, _keep)
          ? this.startResult
          : startResult as MemberMembershipsStartResponse?,
      welcomeCountdown: welcomeCountdown ?? this.welcomeCountdown,
      planBlockActive: identical(planBlockActive, _keep)
          ? this.planBlockActive
          : planBlockActive as KioskPlanBlockReason?,
      popupCountdown: popupCountdown ?? this.popupCountdown,
      stopReason: identical(stopReason, _keep)
          ? this.stopReason
          : stopReason as KioskSignupStopReason?,
      stopCountdown: stopCountdown ?? this.stopCountdown,
      idleWarningActive: idleWarningActive ?? this.idleWarningActive,
      idleCountdown: idleCountdown ?? this.idleCountdown,
      abandonConfirmActive: abandonConfirmActive ?? this.abandonConfirmActive,
      abandoned: abandoned ?? this.abandoned,
    );
  }

  @override
  List<Object?> get props => [
        step,
        persons,
        activePersonIndex,
        committedSteps,
        submitting,
        pendingPayee,
        personDetailsFailed,
        matchCandidate,
        payerMatchFromIdentify,
        matchSearchOpen,
        matchQuery,
        matchSearching,
        matchSearchFailed,
        matches,
        payerAlreadyInSignup,
        removeConfirmIndex,
        plans,
        plansLoading,
        plansFailed,
        waiverQueue,
        waiverIndex,
        waiver,
        waiverLoading,
        waiverFailed,
        waiverStale,
        signedWaivers,
        waiverPersonQueue,
        waiverPersonIndex,
        payerAuthPending,
        payerAuthWaiver,
        payerAuthLoading,
        payerAuthFailed,
        payerAuthStale,
        waiverGate,
        cardAttempt,
        paymentMethodId,
        cardBrand,
        cardLast4,
        preview,
        previewLoading,
        idempotencyKey,
        startResult,
        welcomeCountdown,
        planBlockActive,
        popupCountdown,
        stopReason,
        stopCountdown,
        idleWarningActive,
        idleCountdown,
        abandonConfirmActive,
        abandoned,
      ];
}
