import 'package:equatable/equatable.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/data/models/authorized_payer_waiver.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_preview.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/membership_flow/domain/money_readouts.dart'
    as money;
import 'package:crm/features/membership_flow/domain/plan_rules.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';

/// The signup lane's step spine, in flow order.
///
/// Solo: [entry] → [details] → [extraDetails] *(the member is created here)*
/// → [people] → [plans] → [waivers] → [card] → [review] → [paying] →
/// [results] → [welcome]; an existing member takes [entry] → [identify] →
/// [payerMatch] and lands on [people]. Group adds [personDetails] / [match].
///
/// [plans] precedes [waivers] because waivers come from the picked plan.
/// [declined] retries PAY only (members, signatures and links stay committed
/// and are never re-executed); [stop] is a terminal front-desk handoff.
enum KioskSignupStep {
  /// The first fork: brand new here, or already a member. An existing member
  /// starts their own signup here rather than being sent to the desk.
  entry,

  /// "Find your name" — the existing member identifies themselves against the
  /// gym's records instead of typing a second account into being.
  identify,

  /// D1 — first / last / email (required) / phone.
  details,

  /// D1a — date of birth, address, emergency contact. Always shown. Continue
  /// or Skip fires the single `createMember` call.
  extraDetails,

  /// E1 — the roster: "It's just me" or add someone.
  people,

  /// E1a — one added person's own details.
  personDetails,

  /// E2 — find an EXISTING member to add to the cart.
  match,

  /// The person at the iPad already has an account, so it is adopted rather
  /// than duplicated: one confirm card, their name and masked email, two
  /// answers. Reached from [identify] or from a duplicate 409 on their create.
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
  /// Covers all-created AND partial: on a partial money HAS moved for the group
  /// that cleared, so the decline popup's "you haven't been charged" would be
  /// false. Only an ALL-failed start goes to [declined], where that copy is
  /// true.
  results,

  /// D8 — every membership in the cart was refused. Retries PAY only.
  declined,

  /// The signup succeeded.
  welcome,

  /// A terminal front-desk handoff ([KioskSignupState.stopReason] says which).
  stop,
}

/// Why a plan on the grid is closed to the person currently picking. The two
/// scopes drive the copy: [trialUsed] is per MEMBER (any prior trial closes
/// EVERY trial plan) so its words never name a plan, [alreadyOnPlan] is per
/// PLAN so its words do. Copy lives in `kiosk_plan_block_copy.dart`, switched
/// exhaustively so a new reason cannot ship without words.
enum KioskPlanBlockReason {
  /// A trial plan, for somebody who has already had a trial here. A kiosk-only
  /// rule — staff may still grant a repeat trial from the CRM.
  trialUsed,

  /// A RECURRING plan this member already holds `active` or `frozen`. The
  /// backend refuses it on the preview AND the start, so an unblocked card
  /// dead-ends the signup on a retryable stop that can never succeed.
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

/// Why the signup stopped dead and handed off to the front desk. Every reason
/// is TERMINAL: the screen's single action returns home. Copy lives in
/// `presentation/kiosk_signup_stop_copy.dart`, switched exhaustively so a new
/// reason cannot ship without words. The two [isRetryable] reasons offer a
/// "Try again" instead, and the session's flow count is deliberately NOT
/// released while the member is still standing there.
enum KioskSignupStopReason {
  /// `POST /members/` came back 409 `duplicate_member` and the member said the
  /// matched account is NOT theirs — or the 409 named nobody. The 409's
  /// `matches` are never rendered as a LIST: telling whoever is at a shared
  /// iPad that a given account exists is an account-existence leak.
  duplicateMember,

  /// Trials are one to a member and this one has had theirs. Reached only when
  /// they CHOOSE the desk from the trial-block popup; its own primary sends
  /// them back to the plan grid.
  trialAlreadyUsed,

  /// This member already holds the RECURRING plan they tapped. Reached only
  /// when they CHOOSE the desk from the plan-block popup; its primary sends
  /// them back to the grid, where a DIFFERENT recurring plan is still a sale.
  alreadyOnPlan,

  /// `POST /members/` came back 400 — the gym has no Stripe Connect account,
  /// so no member (and no customer) can be created. A gym-setup problem.
  paymentsUnavailable,

  /// The create call failed for any other reason (a 5xx, a dropped network,
  /// an unrecognised 4xx). Nothing was written.
  signupFailed,

  /// No plan is public with an active price. A gym-setup fact, not a failure,
  /// so it gets its own words rather than the generic apology.
  noPlansOffered,

  /// The plan catalogue could not be read. Retryable — nothing is wrong with
  /// the signup, one read just failed.
  plansUnavailable,

  /// The charge preview failed. Retryable: it stages rows and calls Stripe on
  /// the 30s timeout, so a slow moment must not strand the member.
  previewFailed,

  /// The start call failed outright (a 5xx or a dropped connection). Nothing
  /// was charged, and the copy says so — the only question the member has.
  paymentFailed,

  /// A start attempt was already sent for this idempotency key and its
  /// outcome is unknown, so the kiosk will NOT send it again — an auto-retry
  /// is the one thing that could double-charge. The desk resolves it.
  paymentUnconfirmed,

  /// The member ASKED for help after a decline — never forced, since a refused
  /// card stays retryable. Everything committed stays committed: a handoff,
  /// not an abandon.
  cardDeclined;

  /// Whether the stop screen offers a "Try again" that returns to the step.
  /// Only the two pure-read failures qualify: a money path never auto-retries
  /// and a duplicate never resolves itself.
  bool get isRetryable =>
      this == plansUnavailable || this == previewFailed;
}

/// One waiver signed during THIS signup: who it was signed for, which waiver,
/// and the legal name typed (the review renders both back).
///
/// [memberId] is what makes the group run correct — two children on the same
/// plan each sign that plan's liability waiver, so keying "already signed" on
/// the waiver id alone would skip the second child and hand the backend an
/// unsigned member at the start call.
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

/// One EXISTING member offered as a match — a payee being added (E2), or the
/// person who started the signup and already has an account. One shape behind
/// every route into that offer (either 409's `matches`, a name-search row), so
/// one confirm card renders all of them. It carries only what a lobby iPad may
/// print: a full name and an email the card masks. Never a phone, a photo, or
/// a membership status.
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

/// One person in the signup's roster; the payer is always index 0. [memberId]
/// is null until a create (or a match) supplies one — that null is the
/// "nothing has been written yet" signal the abandon story rests on.
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
  /// waivers, and a line in the cart). The same control on EVERY roster row,
  /// defaulting ON. At least one person must keep it ticked — an empty cart
  /// takes a 400; see [anyoneTraining].
  final bool training;

  /// True when this person was matched to an EXISTING member rather than
  /// created here — the "the kiosk does not own this record" marker: no stored
  /// details on a shared screen, no Edit affordance on the roster, and no
  /// per-person details step.
  final bool wasExisting;

  /// True once `PUT /members/{id}/link` has authorized the payer to pay for
  /// this person — the group flow's commit marker. There is no unlink call, so
  /// a linked person can no longer be removed, and every payee needs it before
  /// a start request is assembled.
  final bool linked;

  /// True when this member has ALREADY had a trial here, so no trial plan is
  /// selectable. Read once at plan-pick, only for a person whose account
  /// predates this signup, and fails OPEN (see
  /// `KioskSignupCubit._loadPlanEligibility`) — false when it cannot answer.
  final bool hadTrial;

  /// The RECURRING plans this member already holds `active` or `frozen` — the
  /// plans the backend would refuse to start again for them.
  ///
  /// It lives on the PERSON, never the state root: the plan step is walked once
  /// per training person, so a state-root map would be one stale read from
  /// printing a parent's membership on a child's turn. Read from the same
  /// `getMemberDetail` response as [hadTrial] and fails OPEN — failing closed
  /// on a read error would block every plan and turn a paying customer away.
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
/// current [step], the roster, and everything each step renders. [copyWith]'s
/// `_keep` sentinel preserves a nullable field unless an explicit `null` is
/// passed, which is how a fresh failure drops a stale value.
///
/// Nothing here survives the flow — the shared-iPad privacy contract made
/// structural: `KioskSignupScreen` provides the cubit, so leaving the view
/// disposes every field on this object.
class KioskSignupState extends Equatable {
  final KioskSignupStep step;

  /// The roster. Index 0 is always the payer and always exists.
  final List<KioskSignupPerson> persons;

  /// Which person the per-person steps ([personDetails], [plans], [waivers])
  /// are currently acting on.
  final int activePersonIndex;

  /// The steps whose work has been COMMITTED to the backend. Back into
  /// [KioskSignupStep.details] / [KioskSignupStep.extraDetails] stays allowed,
  /// but Continue from a committed step fires `updateMember`, never a second
  /// `createMember` — that would dead-end them on the duplicate stop.
  final Set<KioskSignupStep> committedSteps;

  /// A network call for the current step is in flight — the primary is
  /// disabled and shows its busy state.
  final bool submitting;

  // ── Group: the roster (E1) ──
  /// The payee being added, held OFF the roster until the backend has made
  /// them. A create that 409s leaves this set (the "You typed" half of the
  /// match card) and the roster untouched, so backing out of the offer drops a
  /// draft rather than stranding an id-less member.
  final KioskSignupPerson? pendingPayee;

  /// The optional-details PUT for a payee failed. An INLINE retry, never a
  /// stop — the person already exists, and ending a family signup over an
  /// optional address would orphan everyone on the roster.
  final bool personDetailsFailed;

  // ── Group: find an existing member (E2) ──
  /// The ONE existing member being offered as a match — a payee's, or the
  /// person at the iPad confirming their own account. Deliberately SINGULAR: a
  /// shared screen offers one identity to confirm, never a list to browse.
  final KioskSignupMatch? matchCandidate;

  /// The match on screen came from [KioskSignupStep.identify] rather than a
  /// duplicate 409. It decides where "No, that's not me" goes: back to the
  /// search (nothing committed) versus the terminal stop (create refused).
  final bool payerMatchFromIdentify;

  /// The match step is showing the name search rather than the confirm card.
  final bool matchSearchOpen;

  /// What is typed in that search.
  final String matchQuery;
  final bool matchSearching;
  final bool matchSearchFailed;

  /// Name-search matches for the "add someone who's already a member" step AND
  /// the payer picker — ONE search, since the two are never open at once. Not a
  /// 409's duplicate `matches`, which are never rendered as a list anywhere.
  final List<MemberRow> matches;

  // ── The payer picker ──
  /// Which roster person the remove confirmation is asking about, or null when
  /// it is not up. Removal has no undo, so the trash asks before it acts.
  final int? removeConfirmIndex;

  /// The last CRM search row picked on the payer picker is already ON this
  /// roster — a REDIRECT (they are pickable above), not a rejection. The CRM
  /// path must refuse to INSERT a second entry for one member: two cart items
  /// for one person is a double charge.
  final bool payerAlreadyInSignup;

  // ── Plans (D3) ──
  /// The gym's kiosk-eligible plans — `isPublic && activePrice != null` —
  /// warmed once at entry so the step opens with no network wait.
  final List<MembershipPlanResponse> plans;
  final bool plansLoading;
  final bool plansFailed;

  // ── Waivers (D4 / E3) ──
  /// The waivers this step walks, in order — the plan's `waiverIds` plus
  /// anything a server gate named, MINUS the ones already covered by a
  /// compliant signature (see `KioskSignupCubit._enterLiability`). It is the
  /// "waiver 1 of N" numbering: one signed DURING this signup stays in the
  /// queue and [waiverIndex] moves past it, so the count cannot shrink mid-run.
  final List<String> waiverQueue;

  /// Which entry of [waiverQueue] is on screen.
  final int waiverIndex;

  /// The loaded waiver, body included. Null while it loads.
  final WaiverResponse? waiver;
  final bool waiverLoading;

  /// The last waiver read or sign failed. An INLINE retry, never a terminal
  /// stop — the member already exists, and the gutter escape is still there.
  final bool waiverFailed;

  /// The gym republished this waiver between the read and the sign (409). The
  /// body is reloaded and the member must read and sign the NEW version.
  final bool waiverStale;

  /// Waivers signed during THIS signup. A signed waiver stays signed across
  /// Back navigation — it is committed, and nothing un-signs it.
  final List<KioskSignedWaiver> signedWaivers;

  // ── Group: the per-person waiver run (E3, ruling 9) ──
  /// The roster indexes the waiver phase walks, in order: every payee first
  /// (their payer-auth link, then their liability waivers), the payer's own
  /// LAST — a family passes the tablet once per person, not once per document.
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

  /// Exactly the (member, waiver) pairs a server waiver gate (422) named. The
  /// server is authoritative, so these fold INTO the person's liability queue
  /// next time round, rather than looping a run that never satisfies the gate.
  final List<WaiverGateItem> waiverGate;

  // ── Card (D5) ──
  /// Which card-entry ATTEMPT the field is on — a nonce bumped after a decline.
  /// It keys the Stripe `CardField` (`ValueKey`), whose web platform view is
  /// cached across mounts: without a changing key the retry reuses the iframe
  /// still holding the declined number and no new card can be typed at all.
  final int cardAttempt;

  /// The freshly-entered card's Stripe payment-method id — only ever a card
  /// typed in this signup, for this signup's payer (the fresh-card law).
  final String? paymentMethodId;

  /// The card's brand and last four off the tokenized PaymentMethod — the only
  /// card facts the kiosk ever holds. Shown on review, paying and declined.
  final String? cardBrand;
  final String? cardLast4;

  // ── Review / pay (D6–D8) ──
  final MemberMembershipsStartPreview? preview;
  final bool previewLoading;

  /// The idempotency key for the current start attempt. A deliberate retry
  /// after a decline mints a NEW key; a double-tap reuses this one.
  final String? idempotencyKey;

  /// The landed start response — the ONE source both the receipt and the retry
  /// set read ([failedItems] and [retryMemberIds] are getters over it).
  ///
  /// Its NULLNESS is load-bearing: null means no start has landed for the
  /// request being assembled, which tells [isBeingCharged] to carry the whole
  /// cart; `KioskSignupCubit.pay` clears it as it emits `paying`. A partial
  /// retry MERGES its response into this one, so the receipt keeps listing what
  /// an earlier attempt created.
  final MemberMembershipsStartResponse? startResult;

  /// Seconds left on the welcome screen's auto-return. 0 off the welcome.
  final int welcomeCountdown;

  /// The welcome screen was reached from a PARTIAL receipt. It exists so the
  /// last screen cannot read as "you're all set" when it isn't: it turns on the
  /// front-desk line under the green check and changes nothing else. Set
  /// explicitly by `KioskSignupCubit._enterWelcome`, NOT derived from
  /// [startResult] — welcome clears that.
  final bool welcomeAfterPartial;

  // ── Blocking popups (the decline, the plan block) ──
  /// Which plan-block popup is up over the plan grid, or null when none is.
  /// One popup carries both reasons rather than forking the kiosk's single
  /// modal vocabulary.
  final KioskPlanBlockReason? planBlockActive;

  /// Seconds left on whichever blocking popup is up — the decline, the results
  /// receipt or the plan block; 0 when none is. Every blocking overlay carries
  /// a visible countdown: on a shared iPad no screen may hold it forever.
  /// Expiry runs the ordinary `abandon()`, so the flow count is released once.
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
    this.welcomeAfterPartial = false,
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

  /// The items a start refused — what "declined" and "partial" both mean; a
  /// decline arrives as a RESULT in a 2xx body, never as an HTTP error. The
  /// DISPLAY set, never the retry set: [retryMemberIds] is a SUPERSET, since an
  /// `unknown` row is confirmed nothing and refused nothing.
  List<MemberMembershipsStartResultItem> get failedItems =>
      startResult?.failed ?? const [];

  /// The member ids a RETRY may re-send: every item of the landed start the
  /// backend did NOT confirm as `created`.
  ///
  /// Null and empty must stay distinct — the double-charge defence. Null means
  /// "nothing landed, send the cart"; EMPTY means "send nothing". Collapse them
  /// and a retry re-posts existing memberships under a NEW idempotency key, so
  /// the backend's `ON CONFLICT (idempotency_key)` replay guard cannot dedupe
  /// it and the member is charged twice. Keying on "not created" rather than
  /// `failed` matters for the same reason: a `[created, unknown]` response has
  /// NO failed rows but still offers Retry.
  Set<String>? get retryMemberIds => startResult == null
      ? null
      : <String>{
          for (final item in startItems)
            if (!item.isCreated) item.memberId,
        };

  /// Whether a retry has anything left to send — the one gate on re-firing the
  /// charge. False on an all-created receipt, so retrying a fully-started
  /// signup is unrepresentable rather than a rule somebody must remember.
  bool get canRetryStart => retryMemberIds?.isNotEmpty ?? false;

  /// Whether [person] is in the request the kiosk would assemble right now — a
  /// training person with a member id, narrowed to [retryMemberIds] once a
  /// start has landed. ONE predicate for three readers: the cart items, the
  /// payee links the start demands ([everyPayeeLinked] and the waiver run that
  /// collects them), and a preview line's by-person attribution — so what is
  /// charged, what must be authorized and who is NAMED cannot disagree.
  bool isBeingCharged(KioskSignupPerson person) {
    final memberId = person.memberId;
    if (!person.training || memberId == null) return false;
    return retryMemberIds?.contains(memberId) ?? true;
  }

  /// Whether [person]'s membership ALREADY STARTED on an earlier attempt — the
  /// review's marker after a partial failure. It MARKS rather than filters: the
  /// review still lists everybody, so a person whose membership exists needs a
  /// mark saying the next card will not charge for them. Only a CREATED row
  /// qualifies — an `unknown` row is in [retryMemberIds], so it stays in the
  /// cart and unmarked rather than claiming what the server would not confirm.
  bool alreadyStarted(KioskSignupPerson person) {
    if (startResult == null) return false;
    if (!person.training || person.memberId == null) return false;
    return !isBeingCharged(person);
  }

  /// Whether every membership in the landed start was created. `unknown` is
  /// neither created nor failed and falls OUT: the member is never told
  /// "you're all set" about a row the backend would not confirm.
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

  /// Whether the signup currently has a payer. Deleting the payer clears the
  /// designation and nothing is auto-assigned; the no-payer state exists only
  /// on the People and payer-pick steps and can never reach Pay.
  bool get hasPayer => persons.isNotEmpty && persons.first.isPayer;

  /// The payer, or null once the designation has been cleared by deleting them
  /// (see [hasPayer]). Every money-path read goes through this so a no-payer
  /// signup can never assemble a charge.
  KioskSignupPerson? get payerOrNull => hasPayer ? persons.first : null;

  /// Whether the roster carries anyone besides the payer — what re-labels the
  /// step rail from the 6-step solo template to the 7-step group one.
  bool get isGroup => persons.length > 1;

  /// The ids of every waiver signed in this signup, across everyone.
  List<String> get signedWaiverIds => [
        for (final signed in signedWaivers) signed.waiverId,
      ];

  /// The ids [memberId] has signed — the skip list that keeps a waiver from
  /// being shown to the SAME person twice while still showing it to the next.
  List<String> signedWaiverIdsFor(String? memberId) => [
        for (final signed in signedWaivers)
          if (memberId != null && signed.memberId == memberId) signed.waiverId,
      ];

  /// Every roster index that needs a plan. The payer is in it only while their
  /// own membership check is ticked — a parent paying for their kids is
  /// `payer_member_id` and nothing else.
  List<int> get trainingPersonIndexes => [
        for (var i = 0; i < persons.length; i++)
          if (persons[i].training) i,
      ];

  /// Whether anybody on the roster is getting a membership — the empty-cart
  /// guard. An empty cart sends `memberships: []` and takes a 400, so the
  /// People step disables Continue and says somebody needs a membership.
  bool get anyoneTraining => persons.any((p) => p.training);

  /// Whether the payer may still be handed to an EXISTING member. Freely
  /// repeatable until something commits, then gone — see [canAssignPayer]. The
  /// demoted former payer (an adopted outsider included) becomes an ordinary
  /// roster payee who keeps their training choice and stays removable.
  bool get canSwitchPayer => hasPayer && canAssignPayer;

  /// Whether a payer may be seated right now — switching an existing one
  /// ([canSwitchPayer]) or choosing a first after the payer was deleted.
  ///
  /// The single gate is that nothing has committed the payer: no payee linked,
  /// no signature recorded. There is no unlink call and a signature pins the
  /// payer server-side, so a change after either would assemble the start
  /// against a payer the backend never authorized.
  bool get canAssignPayer =>
      signedWaivers.isEmpty &&
      !persons.any((p) => p.linked);

  /// The roster indexes the payer picker offers. A sitting payer is excluded
  /// (picking them is a no-op dressed as a choice); once deleted there is
  /// nobody to exclude. Anybody without a `memberId` cannot pay yet.
  List<int> get payerCandidateIndexes => [
        for (var i = 0; i < persons.length; i++)
          if (persons[i].memberId != null && !(hasPayer && i == 0)) i,
      ];

  /// Whether every payee the request will CARRY has authorized the payer; the
  /// start call NEVER links. The scope is [isBeingCharged], not the whole
  /// roster, mirroring the backend's `_check_links`
  /// (`memberships_start_validation.py`) — demanding a link for someone not
  /// being charged means taking consent for a membership nobody is buying.
  bool get everyPayeeLinked {
    for (var i = 1; i < persons.length; i++) {
      if (isBeingCharged(persons[i]) && !persons[i].linked) return false;
    }
    return true;
  }

  /// Whether [index] may still be taken off the roster.
  ///
  /// The trash disappears once that person's link or signature has committed —
  /// there is no unlink call, so removal is only offered while it is free; a
  /// created-but-unlinked person just drops out of the cart and their member
  /// shell surfaces in the staff "Incomplete" list. The payer is removable too
  /// (founder ruling: nobody on the roster is special), but only in a group and
  /// only while nothing has committed against them.
  bool canRemovePerson(int index) {
    if (index < 0 || index >= persons.length) return false;
    // Removing the only person is abandoning the signup; that's "Start over".
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
  /// late eligibility answer can re-test a pick already made.
  ///
  /// Neither rule may be widened, and neither is stated here: both come from
  /// the shared rulebook (`membership_flow/domain/plan_rules.dart`), which the
  /// desk reads too. [KioskPlanBlockReason.trialUsed] is the kiosk's own
  /// consequence of [TrialOnceGate] — any prior trial blocks EVERY trial plan,
  /// though staff may still grant a repeat from the CRM.
  /// [KioskPlanBlockReason.alreadyOnPlan] is [RecurringHeldGate], which mirrors
  /// the backend's conflict guard (`member_memberships_check_existing.sql`)
  /// keyed on `plan_id`, so one recurring plan never blocks a DIFFERENT one.
  ///
  /// The switch is exhaustive over the sealed gate hierarchy: a new gate cannot
  /// ship without the kiosk saying what it means.
  KioskPlanBlockReason? planBlockReasonFor(
    KioskSignupPerson person,
    MembershipPlanResponse plan,
  ) {
    final gate = firstBlockingGate(_planGatesFor(person), plan);
    return switch (gate) {
      TrialOnceGate() => KioskPlanBlockReason.trialUsed,
      RecurringHeldGate() => KioskPlanBlockReason.alreadyOnPlan,
      null => null,
    };
  }

  /// The gates closing plans to [person], in the order their explanations take
  /// precedence: the per-MEMBER trial rule before the per-PLAN one, which is
  /// the order the kiosk has always answered a doubly-blocked card in.
  List<PlanGate> _planGatesFor(KioskSignupPerson person) => [
        TrialOnceGate(hadTrial: person.hadTrial),
        RecurringHeldGate(person.heldRecurringPlanIds.toSet()),
      ];

  /// The catalogue names of the recurring plans the ACTIVE person holds — what
  /// the plan notice and the already-on-plan popup state. A held plan the gym
  /// no longer offers resolves to nothing and is omitted: it cannot be picked.
  List<String> get heldPlanNames {
    final held = activePerson.heldRecurringPlanIds;
    if (held.isEmpty) return const [];
    return [
      for (final plan in plans)
        if (held.contains(plan.planId)) plan.planName,
    ];
  }

  /// Whether EVERY training person's pick is a trial — the discriminator
  /// behind the review's "Sign Trial" / "Sign Membership" verb. A mixed or
  /// still-incomplete cart falls to "Membership".
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

  /// Whether anything in the cart bills again after today — it decides the one
  /// CONDITIONAL card fact ("Cancel any time at the front desk"). It must NOT
  /// decide `set_default`: the kiosk always saves the entered card as the
  /// payer's default, whatever the cart holds.
  bool get cartHasRecurring {
    for (final person in persons) {
      if (!person.training) continue;
      if (planById(person.selectedPlanId)?.planType == PlanType.recurring) {
        return true;
      }
    }
    return false;
  }

  /// The proration every readout below is taken at. The kiosk PINS it: an
  /// unattended iPad never offers "no charge now", so the due-now half of the
  /// preview is always the one that will actually be charged.
  static const _proration = ProrationBehavior.prorateToAnchor;

  /// The ONLY arithmetic the kiosk does on money: the one-time invoice plus the
  /// recurring amount due now, straight off the preview (a price is never
  /// derived from a plan row). The sum itself lives in the shared readouts,
  /// which the desk reads too.
  int get dueTodayMinorUnits =>
      money.dueTodayMinorUnits(preview, _proration);

  /// True when the payer's statement will show TWO charges today — a non-zero
  /// one-time invoice AND a non-zero recurring amount due now.
  bool get chargedTwiceToday =>
      money.chargedTwiceToday(preview, _proration);

  /// True when today's charge is a PART period — the kiosk pins
  /// `prorate_to_anchor`, so a mid-cycle join pays the rest of the period.
  bool get chargedProrated => money.chargedProrated(preview, _proration);

  /// The billing-period end a part-period charge runs up to, and the day the
  /// full amount first bills — the preview's own `next_payment_date`.
  DateTime? get prorationUntil => money.prorationUntil(preview, _proration);

  /// The currency every figure on the review is rendered in — whichever half
  /// of the preview exists, in the CRM's own order of preference.
  String get currency => money.previewCurrency(preview, _proration);

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
    bool? welcomeAfterPartial,
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
      welcomeAfterPartial: welcomeAfterPartial ?? this.welcomeAfterPartial,
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
        welcomeAfterPartial,
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
