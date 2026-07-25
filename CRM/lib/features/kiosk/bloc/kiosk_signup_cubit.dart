import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_payment.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/models/member_waiver_status.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// How long a terminal front-desk stop stays up before it returns home on its
/// own, so a member who walks off doesn't leave the kiosk parked on a dead
/// end. Matches the mockup's `--dur:15s`.
const Duration kKioskSignupStopHold = Duration(seconds: 15);

/// How long a BLOCKING signup surface (the decline popup, the plan block, the
/// per-person results receipt) holds before it returns home on its own.
///
/// **Every blocking overlay carries a visible countdown, inside the popup.**
/// This is a shared community iPad: no screen may hold it forever, and a timer
/// drawn behind a popup sneaks the surface away without the member seeing it
/// go. It is deliberately longer than [kKioskSignupStopHold]: that 15 seconds
/// is for a TERMINAL stop that can be reached with nobody standing there,
/// while these are read-and-decide screens somebody is looking at — which is
/// also why the results screen shares this clock rather than naming a seventh
/// one for the identical duration.
const Duration kKioskSignupPopupHold = Duration(seconds: 60);

/// How long the welcome screen holds before returning home on its own, so a
/// member who walks off with their phone doesn't leave their name up for the
/// next person. Matches the mockup's `--dur:60s` and the "Get the app" modal's
/// own 60-second clock.
const Duration kKioskSignupWelcomeHold = Duration(seconds: 60);

/// The response wait for the ONE start call.
///
/// A real Stripe charge on a Connect account creates a customer's
/// subscription, converges it and takes the money inside a single request, so
/// 10–60s is normal and the shared 30s default would false-fail a charge that
/// actually went through — the worst possible outcome on this screen. Only the
/// *receive* wait moves (see `ApiClient.post`); an unreachable host still fails
/// fast.
const Duration kKioskSignupStartTimeout = Duration(seconds: 90);

/// The kiosk SELF-SERVE SIGNUP lane — a sibling of [KioskFlowCubit], not more
/// fields on it.
///
/// The two lanes are deliberately separate objects: the check-in cubit is
/// already ~800 lines / 24 state fields, and the two flows share nothing but
/// the session bookkeeping and the one way home. This cubit is provided by
/// `KioskSignupScreen`, so **its lifetime IS the flow's lifetime** — leaving
/// the view unmounts the subtree, [close] runs, and the typed PII (and, later,
/// the card) is disposed structurally rather than by remembering to clear it.
///
/// ## Flow-count discipline (load-bearing)
/// [KioskSessionCubit.beginFlow] fires exactly once, in the constructor,
/// behind the [_flowStarted] latch. [_endFlowIfStarted] fires on entering
/// [KioskSignupStep.welcome] or [KioskSignupStep.stop], on an ALL-CREATED
/// [KioskSignupStep.results], on [abandon], and in [close] — the latch makes
/// the pair exactly-once however many of those run.
/// [KioskSignupStep.declined] does **not** release (the member is still
/// standing there and can retry), a PARTIAL [KioskSignupStep.results] does not
/// either (Retry is live on it, and a live charge must never run with no flow
/// held), and [KioskSignupStep.paying] **never** does.
/// An unbalanced count means the kiosk never signs itself out at its T+11h45
/// lockout — the named failure mode in `CRM/CLAUDE.md`.
///
/// ## Going home
/// This cubit cannot navigate: `goHome()` lives on [KioskFlowCubit], the ONE
/// abandon path. So every exit raises [KioskSignupState.abandoned] and
/// `KioskSignupScreen` routes it to `goHome()`. Never add a second abandon
/// path here.
class KioskSignupCubit extends Cubit<KioskSignupState> {
  KioskSignupCubit({
    required MemberRepository memberRepository,
    required MembershipsRepository membershipsRepository,
    required MembersListRepository membersListRepository,
    required KioskSessionCubit session,
    required String gymId,
    DateTime Function() now = DateTime.now,
    String Function() uuid = _defaultUuid,
  })  : _memberRepo = memberRepository,
        _membershipsRepo = membershipsRepository,
        _membersListRepo = membersListRepository,
        _session = session,
        _gymId = gymId,
        _now = now,
        _uuid = uuid,
        super(const KioskSignupState()) {
    // The caller (`KioskFlowCubit.startSignup`) has already checked
    // `canStartFlow`; reaching this constructor IS the flow starting.
    _startFlow();
    _syncIdleTimer();
    // The plan catalogue is identical for every member and the plans step
    // must open with no network wait, so it is warmed here — the same
    // entry-time warm the check-in lane's four gym-wide catalogues use. A
    // failure is non-fatal: the step retries.
    unawaited(_warmPlans());
  }

  static String _defaultUuid() => const Uuid().v4();

  final MemberRepository _memberRepo;
  final MembershipsRepository _membershipsRepo;
  final MembersListRepository _membersListRepo;
  final KioskSessionCubit _session;
  final String _gymId;
  final DateTime Function() _now;
  final String Function() _uuid;

  /// `date_of_birth` goes over the wire as a bare `YYYY-MM-DD` date, never an
  /// instant — a birthday has no timezone.
  static final DateFormat _dobWire = DateFormat('yyyy-MM-dd');

  Timer? _idleTimer;
  Timer? _countdownTimer;
  Timer? _stopTimer;
  Timer? _welcomeTimer;
  Timer? _popupTimer;
  Timer? _searchDebounce;

  /// Members whose membership history has already been read, so the plan step
  /// never asks twice for the same person. A read that FAILED counts as asked:
  /// both gates fail open, and hammering a flaky endpoint on every roster
  /// change would buy nothing.
  final Set<String> _planChecked = <String>{};

  /// Members whose PRIOR waiver signatures have already been read, so the
  /// waiver run never asks twice for the same person. A read that FAILED counts
  /// as asked: its failure mode is a member re-signing something they already
  /// signed (see [_loadPriorWaiverStatus] — the read fails CLOSED), and
  /// hammering a flaky endpoint on every roster change would buy nothing.
  final Set<String> _waiverStatusChecked = <String>{};

  /// Per member, the waivers the gym ALREADY holds a compliant signature for —
  /// signed at a version at or above that waiver's re-sign floor.
  ///
  /// **A private cache keyed by member id, deliberately not state** (the shape
  /// [_planChecked] and [_sentAttempts] use). It has no render path at all, so
  /// the cross-person leak that [KioskSignupPerson.heldRecurringPlanIds] avoids
  /// by living on the person is unrepresentable here; and because it never
  /// emits, a read landing late can never re-shape a waiver queue the member is
  /// already looking at.
  final Map<String, Set<String>> _priorSatisfiedWaiverIds =
      <String, Set<String>>{};

  /// Which name-search response is still wanted. Every fetch takes the next
  /// number and a landing response that no longer holds it is DISCARDED, so a
  /// slow reply for "el" can never overwrite the results for "ella".
  int _searchSeq = 0;

  /// Every idempotency key a start POST has already gone out for — **the
  /// "sent" latch, and the load-bearing double-charge defence.**
  ///
  /// The synchronous `step == paying` guard in [pay] stops a double-tap; this
  /// stops everything else. Once a request has left the device its outcome may
  /// be unknown (a dropped connection, a timeout), and re-posting the same key
  /// is the ONE action that could take a member's money twice. The backend's
  /// `ON CONFLICT (idempotency_key)` replay guard is the second line, not the
  /// first: this latch has to stand on its own, so an ambiguous attempt routes
  /// to the front desk and NEVER auto-retries.
  final Set<String> _sentAttempts = <String>{};

  /// Whether this flow has told the session it started, so the end is
  /// balanced — exactly one [KioskSessionCubit.endFlow] per
  /// [KioskSessionCubit.beginFlow].
  bool _flowStarted = false;

  /// Set while a step owns the clock itself (the payment step, which must not
  /// be interrupted mid-charge). Suspending is not the same as cancelling:
  /// [resumeIdle] re-arms a full fresh 5 minutes.
  bool _idleSuspended = false;

  /// Guards the create/update call against a double-tap on Continue.
  bool _committing = false;

  // ── D0 · new here, or already a member ──

  /// "I'm new here" — the ordinary create path, unchanged in every respect.
  void startAsNewMember() {
    registerActivity();
    emit(state.copyWith(step: KioskSignupStep.details));
    _syncIdleTimer();
  }

  /// "Find my name" — the existing member identifies themselves instead of
  /// typing a second account into being.
  ///
  /// The search is cleared on the way in so the screen never opens on the
  /// previous person's query or results — the shared-iPad rule, applied to the
  /// one screen a stranger's name could survive on.
  void startAsExistingMember() {
    registerActivity();
    _clearSearch();
    emit(state.copyWith(step: KioskSignupStep.identify));
    _syncIdleTimer();
  }

  // ── D1 · details ──

  /// Record the details step's fields and advance to the extra-details step.
  ///
  /// **Nothing is written here.** The member is created at the END of the
  /// extra-details step so one request carries every field the member gave;
  /// creating on this step and PUTting the rest would cost a second round trip
  /// and leave a written-then-abandoned member holding PII.
  void submitDetails({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
  }) {
    registerActivity();
    _updateActivePerson((p) => p.copyWith(
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          email: email.trim(),
          phone: _opt(phone),
        ));
    emit(state.copyWith(step: KioskSignupStep.extraDetails));
    _syncIdleTimer();
  }

  // ── D1a · extra details ──

  /// Continue (or Skip — they are the same call) from the extra-details step.
  ///
  /// **Skip is not a discard.** It carries whatever was typed forward exactly
  /// as Continue does; it exists to tell the member who typed nothing that
  /// they may move on. Both paths land here with the values already on screen.
  ///
  /// This is the flow's FIRST write. Per ruling 11 it branches on whether the
  /// person is already committed:
  /// * not committed → `POST /members/` with both steps' fields;
  /// * already committed (the member pressed Back, fixed a typo, and came
  ///   forward again) → `PUT /members/{id}`, **never** a second create. A
  ///   second create would 409 against the member's own just-created account
  ///   and dead-end them on the duplicate stop.
  Future<void> submitExtraDetails({
    DateTime? dob,
    String? address,
    String? ecName,
    String? ecPhone,
    String? ecEmail,
  }) async {
    registerActivity();
    if (_committing) return;
    _updateActivePerson((p) => p.copyWith(
          dob: dob,
          address: _opt(address),
          ecName: _opt(ecName),
          ecPhone: _opt(ecPhone),
          ecEmail: _opt(ecEmail),
          detailsStatus: _statusOf(
            dob: dob,
            address: _opt(address),
            ecName: _opt(ecName),
            ecPhone: _opt(ecPhone),
            ecEmail: _opt(ecEmail),
          ),
        ));
    await _commitActivePerson();
  }

  /// Create (or update) the active person, then advance to the roster step.
  Future<void> _commitActivePerson() async {
    _committing = true;
    emit(state.copyWith(submitting: true));
    final person = state.activePerson;
    try {
      if (person.isCreated) {
        await _memberRepo.updateMember(
          person.memberId!,
          MembersManagementUpdateRequest(
            firstName: person.firstName,
            lastName: person.lastName,
            email: person.email,
            phone: person.phone,
            dateOfBirth: _wireDob(person.dob),
            address: person.address,
            emergencyContactName: person.ecName,
            emergencyContactPhone: person.ecPhone,
            emergencyContactEmail: person.ecEmail,
          ),
        );
        if (isClosed) return;
      } else {
        final memberId = await _memberRepo.createMember(
          MembersManagementCreateRequest(
            gymId: _gymId,
            firstName: person.firstName,
            lastName: person.lastName,
            email: person.email,
            phone: person.phone,
            dateOfBirth: _wireDob(person.dob),
            address: person.address,
            emergencyContactName: person.ecName,
            emergencyContactPhone: person.ecPhone,
            emergencyContactEmail: person.ecEmail,
          ),
        );
        if (isClosed) return;
        _updateActivePerson((p) => p.copyWith(memberId: memberId));
      }
      emit(state.copyWith(
        submitting: false,
        committedSteps: {
          ...state.committedSteps,
          KioskSignupStep.details,
          KioskSignupStep.extraDetails,
        },
        step: KioskSignupStep.people,
      ));
      _syncIdleTimer();
    } on DuplicateMemberException catch (e, st) {
      log('Kiosk signup: duplicate member on create (${e.matches.length} '
          'match(es))', stackTrace: st);
      if (isClosed) return;
      _offerPayerMatch(e);
    } on ServerException catch (e, st) {
      log('Kiosk signup: member write failed', error: e, stackTrace: st);
      if (isClosed) return;
      // A 400 on `POST /members/` is the gym having no Stripe Connect account
      // — a gym-setup problem, never the member's, and it gets its own words.
      _stop(e.statusCode == 400
          ? KioskSignupStopReason.paymentsUnavailable
          : KioskSignupStopReason.signupFailed);
    } catch (e, st) {
      log('Kiosk signup: member write failed', error: e, stackTrace: st);
      if (isClosed) return;
      _stop(KioskSignupStopReason.signupFailed);
    } finally {
      _committing = false;
    }
  }

  /// The wire form of a date of birth — a bare `YYYY-MM-DD`, or null.
  String? _wireDob(DateTime? dob) => dob == null ? null : _dobWire.format(dob);

  // ── Adopting an existing account ──

  /// A 409 on the PAYER's own create — they already have an account here.
  ///
  /// The person standing at the iPad just typed this name and this email, so
  /// confirming THEIR OWN account back to them leaks nothing, and adopting it
  /// is simply the right answer: the lane is self-serve for existing members
  /// too, and the card they type always replaces whatever is on that profile.
  ///
  /// A 409 that names nobody is not an offer anybody can answer, so it lands
  /// on the terminal stop. Matches are never rendered as a LIST either way.
  void _offerPayerMatch(DuplicateMemberException e) {
    final match = e.matches.isEmpty ? null : e.matches.first;
    if (match == null) {
      _stop(KioskSignupStopReason.duplicateMember);
      return;
    }
    emit(state.copyWith(
      step: KioskSignupStep.payerMatch,
      submitting: false,
      payerMatchFromIdentify: false,
      matchCandidate: KioskSignupMatch(
        memberId: match.memberId,
        firstName: match.firstName,
        lastName: match.lastName,
        email: match.email,
      ),
    ));
    _syncIdleTimer();
  }

  /// "Yes, that's me" — adopt the existing account as the payer.
  ///
  /// **Nothing is created and nothing is written.** The member already exists;
  /// this only points the roster's payer seat at their id, marks them
  /// [KioskSignupPerson.wasExisting] (so the roster offers no Edit and the
  /// details step is skipped — the kiosk never prints or overwrites a record
  /// it does not own), and carries on at the roster.
  void confirmPayerMatch() {
    registerActivity();
    final match = state.matchCandidate;
    if (match == null) return;
    final persons = [...state.persons];
    persons[0] = persons[0].copyWith(
      memberId: match.memberId,
      // The gym's record is authoritative over what was typed at the iPad.
      firstName: match.firstName,
      lastName: match.lastName,
      email: match.email ?? persons[0].email,
      wasExisting: true,
      detailsStatus: KioskSignupDetailsStatus.none,
    );
    emit(state.copyWith(
      persons: persons,
      matchCandidate: null,
      payerMatchFromIdentify: false,
      submitting: false,
      step: KioskSignupStep.people,
    ));
    _syncIdleTimer();
  }

  /// "No, that's not me" — and where it goes depends on how the match was
  /// reached.
  ///
  /// From the IDENTIFY search they simply mis-tapped a name and nothing has
  /// committed, so it returns to the search with their query intact. From a
  /// duplicate 409 the create has already been refused and there is nothing
  /// left the kiosk can do, so it is the terminal front-desk stop.
  void declinePayerMatch() {
    registerActivity();
    if (state.payerMatchFromIdentify) {
      emit(state.copyWith(
        step: KioskSignupStep.identify,
        matchCandidate: null,
        payerMatchFromIdentify: false,
      ));
      _syncIdleTimer();
      return;
    }
    _stop(KioskSignupStopReason.duplicateMember);
  }

  // ── "Someone else is paying" — the payer picker ──

  /// Open the picker — to CHANGE an existing payer, or to CHOOSE the first one
  /// after the payer was deleted.
  ///
  /// It reuses the ONE name search (debounce + sequence guard included). It is
  /// gated on [KioskSignupState.canAssignPayer], which is true both while a
  /// payer is still free to move and while there is none yet — so the People
  /// step's "Choose who's paying" affordance can open it in the no-payer state.
  void openPayerPick() {
    registerActivity();
    if (!state.canAssignPayer) return;
    _clearSearch();
    emit(state.copyWith(
      step: KioskSignupStep.payerPick,
      payerAlreadyInSignup: false,
      submitting: false,
    ));
    _syncIdleTimer();
  }

  /// **The ONE path a payer is ever seated by.**
  ///
  /// The roster and the CRM search both come through here and **nothing is
  /// special-cased**. One code path is the point: there is exactly one place
  /// the seat rules live and no branch a future change could route around.
  ///
  /// The precondition is [KioskSignupState.canAssignPayer] — nothing linked,
  /// nothing signed. It covers BOTH a switch and a first choice after a
  /// delete, so a payer chosen after the previous one was deleted is seated
  /// through exactly this path.
  ///
  /// **There is no card check.** An existing member with a card on file may
  /// pay here: they still type a fresh card, and it replaces the one on their
  /// profile (the card step says so in as many words). What the kiosk never
  /// does is CHARGE a card it did not just take.
  void _seatPayer(void Function() seat) {
    if (_committing || !state.canAssignPayer) return;
    seat();
  }

  /// A CRM search row becomes the payer — somebody not on the roster yet.
  ///
  /// On the IDENTIFY step the same row means something else: the person
  /// standing there is naming THEMSELVES, so it routes to the confirm card
  /// rather than inserting a second person at the head of an empty roster.
  ///
  /// A hit that is ALREADY on the roster is a redirect, not a rejection: they
  /// are listed above and directly pickable, and inserting a second entry for
  /// one member would put two cart items on one person.
  ///
  /// **The one silent no-op is whoever is ALREADY paying** — picking them
  /// changes nothing and there is nothing to redirect them to. It is tested the
  /// way [pickPayerFromRoster] tests it, on `hasPayer && index == 0` rather than
  /// on the index alone: once the payer has been DELETED, index 0 holds an
  /// ordinary candidate, and refusing them there dropped the tap on the floor —
  /// no seat, and not even the "they're on the roster above" notice.
  Future<void> pickPayerRow(MemberRow row) async {
    registerActivity();
    if (state.step == KioskSignupStep.identify) {
      _offerIdentifiedMatch(row);
      return;
    }
    final at = state.persons.indexWhere((p) => p.memberId == row.memberId);
    if (at >= 0) {
      if (state.hasPayer && at == 0) return;
      emit(state.copyWith(payerAlreadyInSignup: true));
      return;
    }
    _seatPayer(() => _seatNewPayer(row));
  }

  /// A row tapped on the identify step — "that's me".
  ///
  /// It still CONFIRMS before adopting: two members can share a name, and a
  /// mis-tap on a shared iPad would otherwise seat a stranger's account as the
  /// payer. The confirm card is the shipped one, so both routes into "is this
  /// you?" end in the same decision.
  void _offerIdentifiedMatch(MemberRow row) {
    final name = row.name.trim();
    final space = name.indexOf(' ');
    emit(state.copyWith(
      step: KioskSignupStep.payerMatch,
      payerMatchFromIdentify: true,
      submitting: false,
      matchCandidate: KioskSignupMatch(
        memberId: row.memberId,
        firstName: space < 0 ? name : name.substring(0, space),
        lastName: space < 0 ? '' : name.substring(space + 1).trim(),
        email: row is AllViewRow ? row.email : null,
      ),
    ));
    _syncIdleTimer();
  }

  /// A person ALREADY on the roster becomes the payer.
  ///
  /// It goes through the same one seat path as a CRM pick. Picking whoever
  /// ALREADY pays (index 0 while a payer exists) is refused as a no-op; but
  /// when the payer has been deleted, index 0 is a real candidate like any
  /// other, so it is refused only while there is still a payer sitting there.
  Future<void> pickPayerFromRoster(int index) async {
    registerActivity();
    if (index < 0 || index >= state.persons.length) return;
    if (state.hasPayer && index == 0) return;
    if (state.persons[index].memberId == null) return;
    _seatPayer(() => _promoteRosterPayer(index));
  }

  /// Seat a member who was NOT on the roster, inserting them at its head.
  ///
  /// **Only the PAYER role moves.** The person who started this signup keeps
  /// their seat — they are still signing up — and simply becomes a payee, so
  /// they now need the payer-authorization waiver exactly like every other
  /// payee. [KioskSignupState.everyPayeeLinked] therefore covers them for
  /// free: no request can assemble until the new payer has authorized them.
  void _seatNewPayer(MemberRow row) {
    final name = row.name.trim();
    final space = name.indexOf(' ');
    final persons = <KioskSignupPerson>[
      KioskSignupPerson(
        memberId: row.memberId,
        firstName: space < 0 ? name : name.substring(0, space),
        lastName: space < 0 ? '' : name.substring(space + 1).trim(),
        email: row is AllViewRow ? (row.email ?? '') : '',
        isPayer: true,
        wasExisting: true,
      ),
      state.persons.first.copyWith(isPayer: false),
      ...state.persons.skip(1),
    ];
    _clearSearch();
    emit(state.copyWith(
      persons: persons,
      // Every existing index shifted by the insert at the head.
      activePersonIndex: state.activePersonIndex + 1,
      step: KioskSignupStep.people,
      submitting: false,
      payerAlreadyInSignup: false,
    ));
    _syncIdleTimer();
  }

  /// Promote somebody already on the roster, demoting whoever was paying into
  /// the seat they vacate.
  ///
  /// It is a straight SWAP of positions 0 and [index], so every other index —
  /// and every signature, link and plan keyed on them — is untouched. The
  /// promoted person keeps their own "getting a membership" choice and their
  /// plan: they were signing up before and they still are, and only the payer
  /// role moved.
  void _promoteRosterPayer(int index) {
    final persons = [...state.persons];
    final promoted = persons[index].copyWith(isPayer: true);
    persons[index] = persons[0].copyWith(isPayer: false);
    persons[0] = promoted;
    _clearSearch();
    emit(state.copyWith(
      persons: persons,
      step: KioskSignupStep.people,
      submitting: false,
      payerAlreadyInSignup: false,
    ));
    _syncIdleTimer();
  }

  /// Drop whatever the shared name search is holding, and any answer still in
  /// flight for it.
  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchSeq++;
    emit(state.copyWith(
      matchQuery: '',
      matches: const [],
      matchSearching: false,
      matchSearchFailed: false,
    ));
  }

  // ── E1 · the roster ──

  /// Turn "getting a membership" on or off for ONE person.
  ///
  /// It is the same control on every roster row, defaulting ON. It decides
  /// whether that person is in the CART at all: `payer_member_id` is
  /// identity-only server-side, so a parent can pay for their kids without
  /// buying anything themselves — and everybody can be unchecked, which is a
  /// registration-only signup rather than an error (see [continueToPlans]).
  ///
  /// Turning it off drops their plan with it — carrying a stale pick would put
  /// a membership they cancelled back in the request the moment it was
  /// re-checked by accident.
  void setPersonTraining(int index, bool training) {
    registerActivity();
    if (index < 0 || index >= state.persons.length) return;
    final persons = [...state.persons];
    persons[index] = persons[index].copyWith(
      training: training,
      selectedPlanId: training ? persons[index].selectedPlanId : null,
    );
    emit(state.copyWith(persons: persons));
  }

  /// Open one person's optional-details screen from their roster row's Edit.
  /// The payer's is the step they already filled (D1a); everyone else's is
  /// E1a.
  ///
  /// **Only for a person this signup CREATED.** An existing member's stored
  /// details are never shown on a shared screen, so there is nothing here to
  /// edit — the roster offers them no Edit at all, and this refuses the call
  /// as well so no future caller can route one in.
  void editPersonDetails(int index) {
    registerActivity();
    if (index < 0 || index >= state.persons.length) return;
    if (state.persons[index].wasExisting) return;
    emit(state.copyWith(
      activePersonIndex: index,
      personDetailsFailed: false,
      step: index == 0
          ? KioskSignupStep.extraDetails
          : KioskSignupStep.personDetails,
    ));
    _syncIdleTimer();
  }

  /// Ask before taking somebody off the roster.
  ///
  /// There is no undo — the removal drops them from the cart and the roster in
  /// one tap — and the rows sit close together at kiosk scale, so the trash
  /// control asks first. The confirmation names the person.
  void askRemovePerson(int index) {
    registerActivity();
    if (!state.canRemovePerson(index)) return;
    emit(state.copyWith(removeConfirmIndex: index));
  }

  /// "Keep them" — dismiss the confirmation. It counts as interaction.
  void dismissRemovePerson() {
    emit(state.copyWith(removeConfirmIndex: null));
    registerActivity();
  }

  /// "Yes, remove" — the confirmed removal.
  void confirmRemovePerson() {
    final index = state.removeConfirmIndex;
    emit(state.copyWith(removeConfirmIndex: null));
    if (index != null) removePerson(index);
  }

  /// Take a person off the roster. Only ever reached through the confirmation,
  /// and only offered while it is still free — see
  /// [KioskSignupState.canRemovePerson]. Their member shell (if one was
  /// created) is deliberately left alone: it is harmless, there is nothing to
  /// unlink, and it surfaces in the staff "Incomplete" list.
  ///
  /// **Removing the PAYER always asks who pays next** (founder ruling: nobody
  /// is auto-assigned). The signup is left with NO payer — none of the
  /// remaining people is one — and routed straight into the picker to choose.
  /// If the member Backs out of the picker without choosing, the People step
  /// blocks Continue with a plain reason until a payer is set. A no-payer state
  /// lives only on those two steps and can never reach Pay.
  void removePerson(int index) {
    registerActivity();
    if (!state.canRemovePerson(index)) return;
    final removingPayer = state.persons[index].isPayer;
    final persons = [...state.persons]..removeAt(index);
    // Keep the active pointer valid across the shift the removal caused.
    var active = state.activePersonIndex;
    if (index < active) active -= 1;
    if (active >= persons.length) active = persons.length - 1;
    if (active < 0) active = 0;
    if (removingPayer) {
      _clearSearch();
      emit(state.copyWith(
        persons: persons,
        activePersonIndex: active,
        step: KioskSignupStep.payerPick,
        payerAlreadyInSignup: false,
        submitting: false,
      ));
      _syncIdleTimer();
      return;
    }
    emit(state.copyWith(persons: persons, activePersonIndex: active));
  }

  /// The adder's Next: create a brand-new payee, then open their own details.
  ///
  /// The draft is held OFF the roster until the backend has made them, so a
  /// 409 (the match offer) or a failure leaves the roster exactly as it was.
  Future<void> addPerson({
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    registerActivity();
    if (_committing) return;
    emit(state.copyWith(
      pendingPayee: KioskSignupPerson(
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        email: email.trim(),
      ),
    ));
    await _createPendingPayee(allowDuplicate: false);
  }

  /// "No — different person": the same payee, created anyway.
  Future<void> rejectMatch() async {
    registerActivity();
    if (state.pendingPayee == null) {
      // Reached from the search route, where there is no draft to re-create.
      // The roster is where a new person is added.
      back();
      return;
    }
    await _createPendingPayee(allowDuplicate: true);
  }

  Future<void> _createPendingPayee({required bool allowDuplicate}) async {
    final draft = state.pendingPayee;
    if (draft == null) return;
    _committing = true;
    emit(state.copyWith(submitting: true));
    try {
      final memberId = await _memberRepo.createMember(
        MembersManagementCreateRequest(
          gymId: _gymId,
          firstName: draft.firstName,
          lastName: draft.lastName,
          email: draft.email,
          allowDuplicate: allowDuplicate,
        ),
      );
      if (isClosed) return;
      _admitPayee(draft.copyWith(memberId: memberId));
    } on DuplicateMemberException catch (e, st) {
      // **THE ASYMMETRY.** A duplicate PAYER is a terminal front-desk stop
      // (they would be paying on an account the kiosk did not create); a
      // duplicate PAYEE is an OFFER, because a payee pays nothing and reusing
      // their existing account is the right answer.
      log('Kiosk signup: duplicate payee on create '
          '(${e.matches.length} match(es))', stackTrace: st);
      if (isClosed) return;
      final match = e.matches.isEmpty ? null : e.matches.first;
      emit(state.copyWith(
        step: KioskSignupStep.match,
        submitting: false,
        matchCandidate: match == null
            ? null
            : KioskSignupMatch(
                memberId: match.memberId,
                firstName: match.firstName,
                lastName: match.lastName,
                email: match.email,
              ),
        // A 409 that names nobody is not an offer anyone can answer, so the
        // step opens on the search instead of an empty card.
        matchSearchOpen: match == null,
        matches: const [],
        matchQuery: '',
      ));
      _syncIdleTimer();
    } on ServerException catch (e, st) {
      log('Kiosk signup: payee create failed', error: e, stackTrace: st);
      if (isClosed) return;
      _stop(e.statusCode == 400
          ? KioskSignupStopReason.paymentsUnavailable
          : KioskSignupStopReason.signupFailed);
    } catch (e, st) {
      log('Kiosk signup: payee create failed', error: e, stackTrace: st);
      if (isClosed) return;
      _stop(KioskSignupStopReason.signupFailed);
    } finally {
      _committing = false;
    }
  }

  /// Put a resolved payee on the roster.
  ///
  /// A person this signup CREATED goes on to their own details screen. An
  /// EXISTING member skips it entirely: the kiosk cannot show their stored
  /// details on a shared screen and will not overwrite a record it does not
  /// own, so a blank-field pass would be a form that can only ever ask for
  /// what the gym already has. They land straight back on the roster.
  void _admitPayee(KioskSignupPerson person) {
    final persons = [...state.persons, person];
    emit(state.copyWith(
      persons: persons,
      activePersonIndex: persons.length - 1,
      pendingPayee: null,
      matchCandidate: null,
      matchSearchOpen: false,
      matchQuery: '',
      matches: const [],
      submitting: false,
      personDetailsFailed: false,
      step: person.wasExisting
          ? KioskSignupStep.people
          : KioskSignupStep.personDetails,
    ));
    _syncIdleTimer();
  }

  // ── E2 · the existing-member match ──

  /// "Yes, that's her": adopt the existing member instead of making a second
  /// account, and open their details screen with every field BLANK (see
  /// [submitPersonDetails]).
  void confirmMatch() {
    registerActivity();
    final match = state.matchCandidate;
    if (match == null) return;
    // Someone already on this roster cannot be added twice — a second cart
    // item for the same member is a double charge waiting to happen.
    if (state.persons.any((p) => p.memberId == match.memberId)) {
      back();
      return;
    }
    final draft = state.pendingPayee ?? const KioskSignupPerson();
    _admitPayee(draft.copyWith(
      memberId: match.memberId,
      // The gym's record is authoritative over what was typed at the iPad.
      firstName: match.firstName,
      lastName: match.lastName,
      email: match.email ?? draft.email,
      wasExisting: true,
      detailsStatus: KioskSignupDetailsStatus.none,
    ));
  }

  /// "Search by name instead" — and the adder's own "find an existing member".
  void openMatchSearch() {
    registerActivity();
    emit(state.copyWith(
      step: KioskSignupStep.match,
      matchSearchOpen: true,
      matchCandidate: null,
      matchQuery: '',
      matches: const [],
      matchSearching: false,
      matchSearchFailed: false,
    ));
    _syncIdleTimer();
  }

  /// A picked search row becomes the ONE match card — the same confirmation
  /// the 409 route lands on, so both routes end in the same decision.
  void pickMatchRow(MemberRow row) {
    registerActivity();
    final name = row.name.trim();
    final space = name.indexOf(' ');
    emit(state.copyWith(
      matchSearchOpen: false,
      matchCandidate: KioskSignupMatch(
        memberId: row.memberId,
        firstName: space < 0 ? name : name.substring(0, space),
        lastName: space < 0 ? '' : name.substring(space + 1).trim(),
        email: row is AllViewRow ? row.email : null,
      ),
    ));
  }

  /// The match step's live name search — debounced, and sequence-guarded so a
  /// slow response for an older query can never overwrite a newer one.
  void searchExistingPeople(String query) {
    registerActivity();
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < kKioskSearchMinChars) {
      // Discard anything already in flight: its answer is no longer wanted.
      _searchSeq++;
      emit(state.copyWith(
        matchQuery: query,
        matches: const [],
        matchSearching: false,
        matchSearchFailed: false,
      ));
      return;
    }
    emit(state.copyWith(
      matchQuery: query,
      matchSearching: true,
      matchSearchFailed: false,
    ));
    _searchDebounce =
        Timer(kKioskSearchDebounce, () => unawaited(_runMatchSearch(trimmed)));
  }

  Future<void> _runMatchSearch(String query) async {
    final seq = ++_searchSeq;
    try {
      final rows = await findExistingPeople(query);
      if (isClosed || seq != _searchSeq) return;
      emit(state.copyWith(matches: rows, matchSearching: false));
    } catch (e, st) {
      log('Kiosk signup: member search failed', error: e, stackTrace: st);
      if (isClosed || seq != _searchSeq) return;
      emit(state.copyWith(
        matches: const [],
        matchSearching: false,
        matchSearchFailed: true,
      ));
    }
  }

  // ── E1a · one person's own optional details ──

  /// Continue from a payee's optional block.
  ///
  /// It sends **only the optional fields, and only when something was typed**.
  /// Never the name or email: for a matched EXISTING member this screen opened
  /// blank on purpose, and a write built from a form that never showed a value
  /// must not be able to wipe it.
  Future<void> submitPersonDetails({
    DateTime? dob,
    String? address,
    String? ecName,
    String? ecPhone,
    String? ecEmail,
  }) async {
    registerActivity();
    if (_committing) return;
    final status = _statusOf(
      dob: dob,
      address: _opt(address),
      ecName: _opt(ecName),
      ecPhone: _opt(ecPhone),
      ecEmail: _opt(ecEmail),
    );
    final memberId = state.activePerson.memberId;
    if (status == KioskSignupDetailsStatus.none || memberId == null) {
      _backToRoster();
      return;
    }
    _updateActivePerson((p) => p.copyWith(
          dob: dob,
          address: _opt(address),
          ecName: _opt(ecName),
          ecPhone: _opt(ecPhone),
          ecEmail: _opt(ecEmail),
          detailsStatus: status,
        ));
    _committing = true;
    emit(state.copyWith(submitting: true, personDetailsFailed: false));
    try {
      await _memberRepo.updateMember(
        memberId,
        MembersManagementUpdateRequest(
          dateOfBirth: _wireDob(dob),
          address: _opt(address),
          emergencyContactName: _opt(ecName),
          emergencyContactPhone: _opt(ecPhone),
          emergencyContactEmail: _opt(ecEmail),
        ),
      );
      if (isClosed) return;
      emit(state.copyWith(submitting: false));
      _backToRoster();
    } catch (e, st) {
      log('Kiosk signup: payee details update failed',
          error: e, stackTrace: st);
      if (isClosed) return;
      // An INLINE retry, never a stop: the person exists, and killing a family
      // signup over an optional address would orphan the whole roster.
      emit(state.copyWith(submitting: false, personDetailsFailed: true));
    } finally {
      _committing = false;
    }
  }

  /// Skip a payee's optional block. **It fires nothing and records nothing**,
  /// so the roster chip stays honest about what is actually on file.
  void skipPersonDetails() {
    registerActivity();
    _backToRoster();
  }

  void _backToRoster() {
    emit(state.copyWith(
      step: KioskSignupStep.people,
      personDetailsFailed: false,
    ));
    _syncIdleTimer();
  }

  // ── Back ──

  /// Step BACK one screen. Allowed everywhere it is offered; nothing it lands
  /// on is un-done by arriving there (a created member stays created, a signed
  /// waiver stays signed) — [KioskSignupState.committedSteps] is what keeps
  /// the forward call correct when the member continues again.
  void back() {
    registerActivity();
    // The plan step is walked once PER TRAINING PERSON, so its Back is a move
    // within the step before it is a move out of it.
    if (state.step == KioskSignupStep.plans && _backToPreviousPlanPerson()) {
      return;
    }
    final previous = switch (state.step) {
      // The first fork is a safe destination — nothing has been typed on
      // either side of it, so both branches may walk back to it.
      KioskSignupStep.details => KioskSignupStep.entry,
      KioskSignupStep.identify => KioskSignupStep.entry,
      KioskSignupStep.extraDetails => KioskSignupStep.details,
      // Back out of the roster lands on the payer's own optional block, which
      // is what makes ruling 11 reachable at all: it is the only route by
      // which a member returns to a COMMITTED step to fix a typo'd email.
      // An ADOPTED existing payer has no such block — the kiosk never typed
      // their details and must never PUT its own guess over the gym's record
      // — so the roster is their first screen and Back is not offered there.
      KioskSignupStep.people =>
        state.payer.wasExisting ? null : KioskSignupStep.extraDetails,
      KioskSignupStep.plans => KioskSignupStep.people,
      // Back out of a waiver lands on the plan pick, because the plan is what
      // DECIDES which waivers there are. Anything already signed stays signed:
      // coming forward again skips it (see [_enterWaivers]).
      KioskSignupStep.waivers => KioskSignupStep.plans,
      // Back out of the card lands on the PLAN, not on the waiver behind it: a
      // signature is committed and cannot be taken back, so a waiver step
      // re-entered with nothing left to sign would bounce straight forward
      // again. The plan is the real thing a member goes back to change, and
      // changing it re-derives the waivers on the way forward.
      KioskSignupStep.card => KioskSignupStep.plans,
      // Back out of the review lands on the card, which is the only way to
      // change it — a Stripe element cannot be re-populated, so re-entering
      // the step means re-entering the card. That is also the point: the card
      // never lives anywhere it could be re-read.
      KioskSignupStep.review => KioskSignupStep.card,
      // Both roster side-trips land back on the roster, which is where the
      // person they are about now lives. A payee is already CREATED by the
      // time either screen opens, so neither un-does anything by leaving.
      KioskSignupStep.personDetails => KioskSignupStep.people,
      KioskSignupStep.match => KioskSignupStep.people,
      // The payer picker changes nothing until a pick is seated, so leaving it
      // is free.
      KioskSignupStep.payerPick => KioskSignupStep.people,
      _ => null,
    };
    if (previous == null) return;
    if (state.step == KioskSignupStep.payerPick) {
      _clearSearch();
      emit(state.copyWith(step: previous, payerAlreadyInSignup: false));
      _syncIdleTimer();
      return;
    }
    // Backing out of the identify search drops what a stranger typed and any
    // rows it turned up — the shared-iPad rule, applied to the one screen
    // whose results are other members' names.
    if (state.step == KioskSignupStep.identify) {
      _clearSearch();
      emit(state.copyWith(step: previous));
      _syncIdleTimer();
      return;
    }
    // **Back into the card step must hand over a genuinely EMPTY field.** The
    // Stripe `CardField`'s web platform view is CACHED across mounts, so
    // re-entering the step re-shows the card already typed while the step's own
    // `_complete` flag resets to false — which makes "Review" permanently
    // unreachable and leaves the member unable to type anything at all.
    // Bumping `cardAttempt` re-keys the field into a brand-new empty iframe,
    // exactly as [retryCard] does after a decline, and the card facts, the key
    // and the preview go with it so state never claims a card the member cannot
    // see.
    if (previous == KioskSignupStep.card) {
      emit(state.copyWith(
        step: previous,
        cardAttempt: state.cardAttempt + 1,
        paymentMethodId: null,
        cardBrand: null,
        cardLast4: null,
        idempotencyKey: null,
        preview: null,
      ));
      _syncIdleTimer();
      return;
    }
    // Backing out of the match offer drops the draft it was about — nothing
    // was written for them, and leaving a half-added person on state would
    // make the next "Add someone new" open pre-filled with someone else.
    if (state.step == KioskSignupStep.match) {
      emit(state.copyWith(
        step: previous,
        pendingPayee: null,
        matchCandidate: null,
        matches: const [],
        matchQuery: '',
        matchSearchOpen: false,
      ));
      _syncIdleTimer();
      return;
    }
    emit(state.copyWith(step: previous, personDetailsFailed: false));
    _syncIdleTimer();
  }

  /// Step the plan pick back one PERSON. Returns false when the active person
  /// is already the first one picking, so the caller falls through to the
  /// roster.
  bool _backToPreviousPlanPerson() {
    final order = state.trainingPersonIndexes;
    final at = order.indexOf(state.activePersonIndex);
    if (at <= 0) return false;
    emit(state.copyWith(activePersonIndex: order[at - 1]));
    return true;
  }

  // ── Plans (warmed at entry) ──

  /// The gym's kiosk-eligible plans: public, and priced. A plan with no
  /// active price has nothing to charge, and a non-public plan is a staff-only
  /// arrangement — neither may appear on a self-serve iPad.
  Future<void> _warmPlans() async {
    emit(state.copyWith(plansLoading: true, plansFailed: false));
    try {
      final all = await _membershipsRepo.listPlans(_gymId);
      if (isClosed) return;
      final offered =
          all.where((p) => p.isPublic && p.activePrice != null).toList();
      emit(state.copyWith(plans: offered, plansLoading: false));
      // A warm that lands while the member is already ON the step has to
      // answer the step, not just fill a cache.
      if (state.step == KioskSignupStep.plans && offered.isEmpty) {
        _stop(KioskSignupStopReason.noPlansOffered);
      }
    } catch (e, st) {
      log('Kiosk signup: plan catalogue load failed',
          error: e, stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(plansLoading: false, plansFailed: true));
      // Non-fatal at ENTRY (the member is still typing their name and the
      // step will retry), terminal-but-retryable once they are standing on
      // the step with nothing to pick.
      if (state.step == KioskSignupStep.plans) {
        _stop(KioskSignupStopReason.plansUnavailable);
      }
    }
  }

  /// Enter the plan pick — the roster step's exit ("It's just me", or Continue
  /// with a roster).
  ///
  /// It resolves the catalogue's three possible states rather than rendering a
  /// step with nothing on it: still warming → the step's spinner and the warm
  /// answers when it lands; a failed warm → try once more; a successful warm
  /// with nothing to sell → the gym-setup stop.
  void continueToPlans() {
    registerActivity();
    // **The no-payer guard.** Deleting the payer clears the designation and
    // nothing is auto-assigned, so a signup with no payer cannot advance — the
    // People step blocks Continue and points at the picker; this is the
    // belt-and-suspenders guard so nothing routes past it into the money path.
    if (!state.hasPayer) return;
    // **The empty-cart guard.** A roster with nobody getting a membership
    // would send `memberships: []` and take a 400, so that state never leaves
    // this step at all — the step disables Continue and says why.
    final order = state.trainingPersonIndexes;
    if (order.isEmpty) return;
    emit(state.copyWith(
      step: KioskSignupStep.plans,
      activePersonIndex: order.first,
    ));
    _syncIdleTimer();
    // Which plans are closed to whom, read once per person before a card is
    // tapped, so a blocked card wears its mark on the first frame it can.
    unawaited(_loadPlanEligibility());
    // And which waivers each of them has already signed compliantly. It is
    // fired HERE, alongside the eligibility read, because the waiver run is two
    // taps away (pick a plan, Continue) — so the answer is in hand before the
    // first waiver is drawn and the step never briefly shows one it is about to
    // skip. Nothing re-shapes a queue already on screen.
    unawaited(_loadPriorWaiverStatus());
    if (state.plansLoading) return;
    if (state.plansFailed) {
      unawaited(_warmPlans());
      return;
    }
    if (state.plans.isEmpty) _stop(KioskSignupStopReason.noPlansOffered);
  }

  /// Read which plans are closed to whom on this roster — the trial history
  /// AND the recurring plans they already hold, from ONE response each.
  ///
  /// **Only for a person the kiosk did not create.** Somebody registered
  /// during this signup has no history by construction, so their answer is
  /// "no" with no call at all.
  ///
  /// **Both gates FAIL OPEN**, which is the exact opposite of the money-path
  /// reads and is deliberate: these are convenience gates, not money-safety
  /// ones. A second trial slipping through costs the gym one free week the desk
  /// can undo; blocking a legitimate first-timer because a read failed sends a
  /// paying customer away. And on a failed read the kiosk does not know WHICH
  /// plan somebody holds, so a fail-closed posture there would have to block
  /// every plan on the grid — the worst outcome available. So a throw leaves
  /// [KioskSignupPerson.hadTrial] false, leaves
  /// [KioskSignupPerson.heldRecurringPlanIds] empty, and every plan stays on
  /// offer. The cost is the dead end §2.1 of the results design describes: a
  /// member picking a plan they already hold reaches the review and gets a
  /// retryable stop that can never succeed. That is accepted, not airtight.
  ///
  /// **TWO facts are taken and the rest is dropped on the floor.** The billing
  /// detail is a heavy staff payload — rank, charges, redemptions, streak, an
  /// address — and a lobby iPad prints none of it. Nothing here renders, logs
  /// or persists any part of the response beyond the boolean and the plan ids
  /// below; never reuse it to prefill a form.
  Future<void> _loadPlanEligibility() async {
    final wanted = <String>{
      for (final person in state.persons)
        if (person.training &&
            person.wasExisting &&
            person.memberId != null &&
            !_planChecked.contains(person.memberId))
          person.memberId!,
    };
    if (wanted.isEmpty) return;
    _planChecked.addAll(wanted);
    for (final memberId in wanted) {
      bool hadTrial;
      List<String> heldRecurring;
      try {
        final detail = await _memberRepo.getMemberDetail(memberId);
        // Every membership row the member has ever held, whatever its
        // lifecycle state — a trial taken and finished a year ago still
        // counts, which is the whole question being asked.
        hadTrial = detail.memberships.any((m) => m.planType == 'trial');
        // The held-recurring set mirrors the backend's conflict SQL exactly:
        // `plan_type = 'recurring'` AND `status IN ('active','frozen')`. Any
        // wider status set would refuse a sale the backend would have taken.
        heldRecurring = <String>{
          for (final membership in detail.memberships)
            if (membership.planType == 'recurring' &&
                (membership.status == MembershipStatus.active ||
                    membership.status == MembershipStatus.frozen))
              membership.planId,
        }.toList();
      } catch (e, st) {
        log('Kiosk signup: membership history read failed (nothing blocked)',
            error: e, stackTrace: st);
        hadTrial = false;
        heldRecurring = const [];
      }
      if (isClosed) return;
      if (!hadTrial && heldRecurring.isEmpty) continue;
      final persons = [
        for (final person in state.persons)
          if (person.memberId == memberId)
            _clearBlockedPick(person.copyWith(
              hadTrial: hadTrial,
              heldRecurringPlanIds: heldRecurring,
            ))
          else
            person,
      ];
      emit(state.copyWith(persons: persons));
    }
  }

  /// Read which waivers each EXISTING person on the roster has already signed
  /// compliantly, so the waiver run never asks a member to re-sign something
  /// the gym already holds a valid signature for.
  ///
  /// `meets_floor` on each row is the SERVER's compliance verdict — that
  /// member's latest signature sits at a version at or above the waiver's
  /// re-sign floor — and it is the SAME rule the 422 purchase gate and the
  /// check-in gate apply. **The floor is never re-derived here**; one rule, one
  /// owner.
  ///
  /// **This read FAILS CLOSED, which is the exact opposite of
  /// [_loadPlanEligibility], and that inversion is the point.** The two plan
  /// gates fail OPEN because refusing a paying customer is worse than a rare
  /// free week. Waivers invert the cost: a needless signature costs the member
  /// twenty seconds, while a MISSING one voids the gym's legal protection. So a
  /// throw writes NO entry and every waiver on the plan is asked for — see
  /// [_satisfiedWaiverIdsFor], which is where every shade of "we don't know"
  /// collapses to "ask".
  ///
  /// **Only for a person the kiosk did not create.** Somebody registered during
  /// this signup has no signature history by construction, so their answer is
  /// "nothing signed" with no request spent at all.
  Future<void> _loadPriorWaiverStatus() async {
    final wanted = <String>{
      for (final person in state.persons)
        if (person.training &&
            person.wasExisting &&
            person.memberId != null &&
            !_waiverStatusChecked.contains(person.memberId))
          person.memberId!,
    };
    if (wanted.isEmpty) return;
    _waiverStatusChecked.addAll(wanted);
    for (final memberId in wanted) {
      List<MemberWaiverStatus> rows;
      try {
        rows = await _membershipsRepo.listMemberWaiverStatus(memberId, _gymId);
      } catch (e, st) {
        log('Kiosk signup: prior waiver status read failed '
            '(every waiver on the plan will be asked for)',
            error: e, stackTrace: st);
        // No entry written — the member keeps the empty answer, so nothing is
        // skipped for them. Fail CLOSED.
        continue;
      }
      if (isClosed) return;
      // `signed && meetsFloor` and nothing else. A row signed BELOW the floor
      // is exactly the re-sign case, so it stays on the queue; a missing
      // `meets_floor` parses as false (the model's `defaultValue`), so an
      // unrecognised payload also stays on the queue.
      _priorSatisfiedWaiverIds[memberId] = <String>{
        for (final row in rows)
          if (row.signed && row.meetsFloor) row.waiverId,
      };
    }
  }

  /// The waivers [memberId] has already satisfied, as of the read fired at the
  /// plans step.
  ///
  /// **Absence means ASK, at every level — never "no need to sign".** A member
  /// with no entry (never read, or the read threw) answers with the empty set; a
  /// waiver missing from their rows is not in the set; a signature below the
  /// floor is not in the set. The last case is not theoretical: the endpoint's
  /// result set is `required ∪ ever-signed`, where `required` comes from the
  /// member's CURRENT memberships' plans — so a waiver belonging to the plan
  /// they are about to BUY, and never signed, is absent from the response
  /// entirely. Only a positive `signed && meets_floor` from the server ever
  /// takes a signature off the queue.
  Set<String> _satisfiedWaiverIdsFor(String? memberId) => memberId == null
      ? const <String>{}
      : (_priorSatisfiedWaiverIds[memberId] ?? const <String>{});

  /// Drop [person]'s pick when the answer that just landed closed it.
  ///
  /// A blocked plan that survives reaches the review and fails at pay, which is
  /// the dead end the whole block exists to prevent — and the answer can land
  /// after the member has already tapped.
  KioskSignupPerson _clearBlockedPick(KioskSignupPerson person) {
    final plan = state.planById(person.selectedPlanId);
    if (plan == null) return person;
    if (state.planBlockReasonFor(person, plan) == null) return person;
    return person.copyWith(selectedPlanId: null);
  }

  /// Pick a plan for the active person. ONE plan per person, always
  /// `quantity: 1` — a self-serve iPad sells one membership to one person, so
  /// there is no stepper to mis-tap.
  ///
  /// **A plan that is closed to this person is never selected**, only
  /// explained. The card stays tappable so the answer is one tap away — a
  /// greyed-out plan with no explanation is a worse dead end than the one it
  /// is trying to avoid — but the tap opens the popup instead of setting the
  /// pick, so a blocked plan can never reach the review and fail at pay.
  void selectPlan(String planId) {
    registerActivity();
    final plan = state.planById(planId);
    final reason = plan == null ? null : state.planBlockReason(plan);
    if (reason != null) {
      _openPlanBlock(reason);
      return;
    }
    _updateActivePerson((p) => p.copyWith(selectedPlanId: planId));
  }

  /// The explanation behind a blocked card — one popup, whichever reason.
  void _openPlanBlock(KioskPlanBlockReason reason) {
    emit(state.copyWith(planBlockActive: reason));
    _startPopupCountdown();
  }

  /// "Pick a membership" — dismiss and carry on with the grid behind it.
  ///
  /// The blocked plan was never selected, so there is nothing to undo; the
  /// clear below is the belt-and-braces guard that keeps that true if the tap
  /// path is ever refactored.
  void dismissPlanBlock() {
    _popupTimer?.cancel();
    emit(state.copyWith(planBlockActive: null, popupCountdown: 0));
    _updateActivePerson(_clearBlockedPick);
    registerActivity();
  }

  /// "Get help at the desk" from the plan block — the handoff the member
  /// CHOOSES. Nothing routes here on their behalf; the popup's primary sends
  /// them back to the plans they CAN pick.
  void planBlockHelp() {
    final reason = state.planBlockActive;
    _popupTimer?.cancel();
    emit(state.copyWith(planBlockActive: null, popupCountdown: 0));
    _stop(switch (reason) {
      KioskPlanBlockReason.alreadyOnPlan => KioskSignupStopReason.alreadyOnPlan,
      // A tap with no reason on state cannot happen (the popup is only up
      // while one is set); the trial handoff is the safe fallback because it is
      // the reason whose copy claims the least.
      KioskPlanBlockReason.trialUsed ||
      null =>
        KioskSignupStopReason.trialAlreadyUsed,
    });
  }

  /// Continue from the plan pick — to the NEXT training person's plan, or, once
  /// everyone has one, into the waiver run.
  void continueFromPlans() {
    registerActivity();
    if (state.selectedPlan == null) return;
    _advancePlanPerson();
  }

  /// "Skip" — this person is NOT getting a membership after all (founder
  /// ruling: somebody may change their mind halfway through a family signup).
  ///
  /// **Group only.** Skipping the sole person of a solo signup would empty the
  /// cart, and at least one person must get a membership — so the control is
  /// not offered there at all.
  ///
  /// It reuses [KioskSignupPerson.training] rather than adding a parallel
  /// "skipped" concept: not getting a membership is exactly what that flag
  /// already means, so the roster check, the cart, the waiver queue and the
  /// review all follow for free. Their plan is dropped with it, like every
  /// other way that flag goes off.
  ///
  /// **Skipping EVERYBODY returns to the People step** rather than blocking
  /// here. The roster is where they can tick somebody back on or take a person
  /// off, and it already refuses to leave with an empty cart and says why — so
  /// the backend's empty-cart rejection stays unreachable by construction.
  void skipPlanForPerson() {
    registerActivity();
    if (!state.isGroup) return;
    final skipped = state.activePersonIndex;
    if (skipped < 0 || skipped >= state.persons.length) return;
    final persons = [...state.persons];
    persons[skipped] = persons[skipped].copyWith(
      training: false,
      selectedPlanId: null,
    );
    emit(state.copyWith(persons: persons));
    if (!state.anyoneTraining) {
      emit(state.copyWith(step: KioskSignupStep.people));
      _syncIdleTimer();
      return;
    }
    _advancePlanPerson(from: skipped);
  }

  /// Move the plan step on: to the next training person after [from] (the
  /// active person by default), or into the waiver run once nobody is left.
  void _advancePlanPerson({int? from}) {
    final at = from ?? state.activePersonIndex;
    for (final index in state.trainingPersonIndexes) {
      if (index > at) {
        emit(state.copyWith(activePersonIndex: index));
        return;
      }
    }
    _enterWaiverRun();
  }

  // ── D4 / E3 · the waiver run ──

  /// Open the waiver phase at the first person who still owes something.
  ///
  /// **Ruling 9 — grouped by PERSON, not by document.** Every payee first
  /// (their payer-auth link, then their own liability waivers), and the payer's
  /// own liability waiver last. The iPad changes hands once per person, which
  /// is how a family actually passes a tablet.
  ///
  /// **Only the people the request will CARRY are walked** — plus anyone a
  /// server gate named, which is authoritative either way. Somebody who Skipped
  /// (or was never ticked) is not in the cart, so the backend requires no
  /// payer authorization for them (`_check_links` reads the request's own member
  /// ids), and asking them to authorize a payer for a membership they are not
  /// buying is a signature taken for nothing — consent from the wrong person.
  /// The queue and [KioskSignupState.everyPayeeLinked] read the same
  /// [KioskSignupState.isBeingCharged] predicate, so the run collects exactly
  /// the links the start demands and the two can never disagree.
  void _enterWaiverRun() {
    final gated = <int>{
      for (final item in state.waiverGate)
        for (var i = 0; i < state.persons.length; i++)
          if (state.persons[i].memberId == item.memberId) i,
    };
    final queue = <int>[
      for (var i = 1; i < state.persons.length; i++)
        if (state.isBeingCharged(state.persons[i]) || gated.contains(i)) i,
      // The payer signs last, and only when they have something to sign: their
      // own plan's waivers, or one the server named at a gate.
      if (state.isBeingCharged(state.persons.first) || gated.contains(0)) 0,
    ];
    emit(state.copyWith(waiverPersonQueue: queue, waiverPersonIndex: 0));
    _openWaiverPerson(0);
  }

  /// Enter the run at position [at]: the payer-auth link if this payee is not
  /// yet authorized, otherwise their own liability waivers.
  void _openWaiverPerson(int at) {
    final queue = state.waiverPersonQueue;
    if (at >= queue.length) {
      _enterCard();
      return;
    }
    final personIndex = queue[at];
    emit(state.copyWith(waiverPersonIndex: at, activePersonIndex: personIndex));
    if (personIndex != 0 && !state.persons[personIndex].linked) {
      _enterPayerAuth();
      return;
    }
    _enterLiability(personIndex);
  }

  void _advanceWaiverPerson() => _openWaiverPerson(state.waiverPersonIndex + 1);

  /// Open one person's liability queue at the first entry THEY still owe,
  /// skipping the person entirely when there is nothing left.
  ///
  /// **The queue holds only what this person will actually be asked to sign.**
  /// A waiver the gym already holds a compliant signature for is DROPPED from
  /// it rather than merely stepped over, so the subtitle's "waiver 2 of 3"
  /// counts the signatures the member is about to give — telling somebody
  /// "waiver 1 of 3" and then showing them one is worse than an honest
  /// "1 of 1". Everything that reads the queue (the index maths,
  /// [_advanceWaiver], the per-person walk, Back-then-forward) therefore agrees
  /// by construction, because there is only ever the one filtered list.
  ///
  /// Two kinds of entry are never dropped:
  ///  * anything the SERVER named at a 422 purchase gate — it is authoritative,
  ///    and it is the backstop that makes a client-side skip safe at all, so a
  ///    gate item outranks any prior-signature read;
  ///  * anything [_satisfiedWaiverIdsFor] did not positively clear — that read
  ///    fails CLOSED.
  ///
  /// **Signed stays signed**: walking Back and forward again never re-asks, and
  /// nothing un-signs.
  void _enterLiability(int personIndex) {
    final person = state.persons[personIndex];
    final planIds = state.planById(person.selectedPlanId)?.waiverIds ??
        const <String>[];
    // Anything the SERVER named for this person: it is authoritative, and a
    // plan whose waiver list has drifted from the gate would otherwise loop the
    // member through a run that never satisfies it. It is also the ONE thing
    // the prior-signature skip may not remove — if the gate says unsigned, the
    // gate wins.
    final gated = <String>{
      for (final item in state.waiverGate)
        if (item.memberId == person.memberId) item.waiverId,
    };
    final satisfied = _satisfiedWaiverIdsFor(person.memberId);
    final queue = <String>[
      for (final id in planIds)
        if (id.trim().isNotEmpty &&
            (gated.contains(id) || !satisfied.contains(id)))
          id,
    ];
    for (final id in gated) {
      if (!queue.contains(id)) queue.add(id);
    }
    final next = _firstUnsigned(person.memberId, queue);
    if (next == null) {
      _advanceWaiverPerson();
      return;
    }
    emit(state.copyWith(
      step: KioskSignupStep.waivers,
      payerAuthPending: false,
      waiverQueue: queue,
      waiverIndex: next,
      waiver: null,
      waiverStale: false,
      waiverFailed: false,
    ));
    _syncIdleTimer();
    unawaited(_loadWaiver());
  }

  /// The index of the first entry in [queue] that [memberId] has not signed,
  /// or null when every one of them is done.
  int? _firstUnsigned(String? memberId, List<String> queue) {
    final signed = state.signedWaiverIdsFor(memberId);
    for (var i = 0; i < queue.length; i++) {
      if (!signed.contains(queue[i])) return i;
    }
    return null;
  }

  // ── E3 · the payer-auth link (sign + link, ONE call) ──

  void _enterPayerAuth() {
    emit(state.copyWith(
      step: KioskSignupStep.waivers,
      payerAuthPending: true,
      payerAuthWaiver: null,
      payerAuthStale: false,
      payerAuthFailed: false,
    ));
    _syncIdleTimer();
    unawaited(_loadPayerAuthWaiver());
  }

  /// Read the gym's authorized-payer agreement for the active payee.
  ///
  /// A failure is an inline retry for the same reason a liability read is: by
  /// this point member rows and Stripe customers exist for the whole roster.
  Future<void> _loadPayerAuthWaiver() async {
    final payeeId = state.activePerson.memberId;
    if (payeeId == null) return;
    emit(state.copyWith(payerAuthLoading: true, payerAuthFailed: false));
    try {
      final waiver = await _memberRepo.getAuthorizedPayerWaiver(payeeId);
      if (isClosed) return;
      emit(state.copyWith(payerAuthWaiver: waiver, payerAuthLoading: false));
    } catch (e, st) {
      log('Kiosk signup: payer-auth waiver load failed',
          error: e, stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(payerAuthLoading: false, payerAuthFailed: true));
    }
  }

  /// Re-read the payer-auth agreement after a failed load or link.
  void retryPayerAuth() {
    registerActivity();
    unawaited(_loadPayerAuthWaiver());
  }

  /// "Sign and continue" — **sign and link in ONE call**
  /// (`PUT /members/{payee}/link`), which commits immediately with no group
  /// rollback. The signer is the PAYER every time: this is the payer putting
  /// their name to "I am authorised to pay for this person", not the payee's
  /// own liability waiver.
  ///
  /// A 409 means the gym republished the agreement between the read and this
  /// call, so nothing is recorded against text nobody saw — the body reloads
  /// and the payer signs the new one.
  Future<void> signPayerAuth({required String signerName}) async {
    registerActivity();
    if (_committing) return;
    final waiver = state.payerAuthWaiver;
    final payeeId = state.activePerson.memberId;
    final payerId = state.payer.memberId;
    if (waiver == null || payeeId == null || payerId == null) return;
    final name = signerName.trim();
    if (name.isEmpty) return;
    final personIndex = state.activePersonIndex;
    _committing = true;
    emit(state.copyWith(
      submitting: true,
      payerAuthStale: false,
      payerAuthFailed: false,
    ));
    try {
      await _memberRepo.linkMemberAccount(
        payeeId,
        payerMemberId: payerId,
        waiverVersionId: waiver.versionId,
        signerName: name,
        consentAcknowledged: true,
      );
      if (isClosed) return;
      final persons = [...state.persons];
      persons[personIndex] = persons[personIndex].copyWith(linked: true);
      emit(state.copyWith(
        persons: persons,
        submitting: false,
        payerAuthPending: false,
      ));
      _enterLiability(personIndex);
    } on ServerException catch (e, st) {
      if (isClosed) return;
      if (e.statusCode == 409) {
        emit(state.copyWith(submitting: false, payerAuthStale: true));
        unawaited(_loadPayerAuthWaiver());
        return;
      }
      log('Kiosk signup: payer authorization failed',
          error: e, stackTrace: st);
      emit(state.copyWith(submitting: false, payerAuthFailed: true));
    } catch (e, st) {
      log('Kiosk signup: payer authorization failed',
          error: e, stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(submitting: false, payerAuthFailed: true));
    } finally {
      _committing = false;
    }
  }

  /// Read the current waiver's body.
  ///
  /// A failure here is an **inline retry, never a terminal stop**: by this
  /// point a member row and a Stripe customer already exist, so ending the
  /// signup over one flaky read would orphan them for nothing. The escape is
  /// still in the gutter if the member does want out.
  Future<void> _loadWaiver() async {
    final waiverId = state.currentWaiverId;
    if (waiverId == null) return;
    emit(state.copyWith(waiverLoading: true, waiverFailed: false));
    try {
      final waiver = await _membershipsRepo.getWaiver(waiverId, _gymId);
      if (isClosed) return;
      emit(state.copyWith(waiver: waiver, waiverLoading: false));
    } catch (e, st) {
      log('Kiosk signup: waiver load failed', error: e, stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(waiverLoading: false, waiverFailed: true));
    }
  }

  /// Re-read the current waiver after a failed load or a failed sign.
  void retryWaiver() {
    registerActivity();
    unawaited(_loadWaiver());
  }

  /// Record the active person's e-signature on the waiver on screen, then move
  /// to the next unsigned one (or to the card).
  ///
  /// A 409 means the gym republished the waiver between the read and this
  /// call. The version is pinned server-side, so the signature is refused and
  /// the body is reloaded — the member reads and signs the NEW text. Nothing
  /// is recorded against text they never saw.
  Future<void> signWaiver({required String signerName}) async {
    registerActivity();
    if (_committing) return;
    final waiver = state.waiver;
    final versionId = waiver?.currentVersionId;
    final memberId = state.activePerson.memberId;
    if (waiver == null || versionId == null || memberId == null) return;
    final name = signerName.trim();
    if (name.isEmpty) return;
    _committing = true;
    emit(state.copyWith(
      submitting: true,
      waiverStale: false,
      waiverFailed: false,
    ));
    try {
      await _membershipsRepo.recordWaiverSignature(
        waiverId: waiver.waiverId,
        gymId: _gymId,
        memberId: memberId,
        waiverVersionId: versionId,
        signerName: name,
      );
      if (isClosed) return;
      emit(state.copyWith(
        submitting: false,
        signedWaivers: [
          ...state.signedWaivers,
          KioskSignedWaiver(
            // Keyed on the MEMBER, so the same document is still presented to
            // the next child on the roster.
            memberId: memberId,
            waiverId: waiver.waiverId,
            name: waiver.name,
            signerName: name,
          ),
        ],
      ));
      _advanceWaiver();
    } on WaiverStaleVersionException {
      if (isClosed) return;
      emit(state.copyWith(submitting: false, waiverStale: true));
      unawaited(_loadWaiver());
    } catch (e, st) {
      log('Kiosk signup: waiver signature failed', error: e, stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(submitting: false, waiverFailed: true));
    } finally {
      _committing = false;
    }
  }

  void _advanceWaiver() {
    final next = _firstUnsigned(state.activePerson.memberId, state.waiverQueue);
    if (next == null) {
      _advanceWaiverPerson();
      return;
    }
    emit(state.copyWith(
      waiverIndex: next,
      waiver: null,
      waiverStale: false,
      waiverFailed: false,
    ));
    unawaited(_loadWaiver());
  }

  /// Route a server waiver gate (422) back into the waiver run, carrying
  /// exactly the (member, waiver) pairs the backend named.
  ///
  /// The server is authoritative, so anything it lists as unsigned is dropped
  /// from this signup's own signed set — otherwise the run would skip the very
  /// waiver the backend is blocking on and the member would loop. The pairs
  /// are kept on state so [_enterLiability] folds them into the right person's
  /// queue however that person's plan is configured.
  void _routeToWaiverGate(WaiverGateException gate) {
    if (gate.unsigned.isEmpty) {
      // A gate with nothing in it is not something a member can answer.
      _stop(KioskSignupStopReason.signupFailed);
      return;
    }
    bool named(KioskSignedWaiver signed) => gate.unsigned.any(
          (item) =>
              item.memberId == signed.memberId &&
              item.waiverId == signed.waiverId,
        );
    emit(state.copyWith(
      waiverGate: gate.unsigned,
      signedWaivers: [
        for (final signed in state.signedWaivers)
          if (!named(signed)) signed,
      ],
    ));
    _enterWaiverRun();
  }

  // ── D5 · card ──

  void _enterCard() {
    emit(state.copyWith(step: KioskSignupStep.card));
    _syncIdleTimer();
  }

  /// The tokenized card, handed over by the card step's footer primary.
  ///
  /// **Tokenization happens in the widget, against Stripe, and never touches a
  /// repository** — the kiosk only ever holds the resulting `pm_…` id plus the
  /// brand and last four it renders back to the member. Entering the review is
  /// also where the attempt's idempotency key is minted, so a double-tap on
  /// Pay reuses one key rather than racing two.
  void submitCard({
    required String paymentMethodId,
    String? brand,
    String? last4,
  }) {
    registerActivity();
    emit(state.copyWith(
      step: KioskSignupStep.review,
      paymentMethodId: paymentMethodId,
      cardBrand: brand,
      cardLast4: last4,
      idempotencyKey: newIdempotencyKey(),
      preview: null,
    ));
    _syncIdleTimer();
    unawaited(_loadPreview());
  }

  // ── D6 · review ──

  /// The server-side charge preview of the fully assembled request — staged,
  /// never committed. It runs on the default 30s timeout and it CAN fail, so
  /// a failure gets its own retryable stop rather than a blank screen.
  ///
  /// **A request that cannot be ASSEMBLED is the same outcome as one that
  /// failed, and gets the same stop.** The review renders its spinner off
  /// `preview == null`, so returning here without emitting anything left the
  /// step spinning forever with no countdown and no way on — the one thing a
  /// kiosk screen may never be.
  ///
  /// **The stop belongs to the review step only**, because that is the only
  /// step that renders the preview and the only place its "Try again" returns
  /// to. A preview reloaded for a retry ([retrySameCard]) rides alongside a
  /// live charge, and stopping from there would yank the member off a landed
  /// receipt mid-charge.
  Future<void> _loadPreview() async {
    final request = _buildStartRequest(idempotencyKey: newIdempotencyKey());
    if (request == null) {
      log('Kiosk signup: charge preview could not be assembled');
      _failPreview();
      return;
    }
    emit(state.copyWith(previewLoading: true));
    try {
      final preview = await _memberRepo.previewStartMemberships(request);
      if (isClosed) return;
      emit(state.copyWith(preview: preview, previewLoading: false));
    } on WaiverGateException catch (e, st) {
      log('Kiosk signup: preview waiver gate', error: e, stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(previewLoading: false));
      _routeToWaiverGate(e);
    } catch (e, st) {
      log('Kiosk signup: charge preview failed', error: e, stackTrace: st);
      if (isClosed) return;
      _failPreview();
    }
  }

  /// A preview that could not be produced: the review's retryable stop, and
  /// nothing at all anywhere else (see [_loadPreview]).
  void _failPreview() {
    emit(state.copyWith(previewLoading: false));
    if (state.step != KioskSignupStep.review) return;
    _stop(KioskSignupStopReason.previewFailed);
  }

  /// **The ONE place a start request is assembled**, for the preview and for
  /// the real charge alike, so there is a single place to audit what the kiosk
  /// can and cannot send.
  ///
  /// Nothing that reduces a price is ever sent: each item carries the model's
  /// empty defaults and this builder never names those fields. `paidWithCash`
  /// is pinned false — an unattended iPad cannot take cash. The proration is
  /// pinned to `prorateToAnchor`, which is what makes the review's
  /// due-today sum correct (see `KioskSignupState.dueTodayMinorUnits`).
  MemberMembershipsStartRequest? _buildStartRequest({
    required String idempotencyKey,
    MemberMembershipsStartPayment? payment,
  }) {
    // No payer (the previous one was deleted and none chosen) can NEVER
    // assemble a charge — this reads the designated payer, not merely index 0,
    // so a demoted payee sitting at the head can never be billed as the payer.
    final payer = state.payerOrNull;
    if (payer == null) return null;
    final payerId = payer.memberId;
    if (payerId == null) return null;
    // **Link before start, structurally.** The start call never links, so a
    // request is not assembled at all until every payee is authorized — the
    // one place that ordering can be guaranteed for the preview and the
    // charge alike.
    if (!state.everyPayeeLinked) return null;
    final items = _startItems();
    if (items.isEmpty) return null;
    return MemberMembershipsStartRequest(
      payerMemberId: payerId,
      gymId: _gymId,
      idempotencyKey: idempotencyKey,
      prorationBehavior: ProrationBehavior.prorateToAnchor,
      paidWithCash: false,
      payment: payment,
      memberships: items,
    );
  }

  /// One item per person the next request must carry — every training person
  /// with a picked, priced plan on a first attempt, and after a landed start
  /// exactly the people whose membership was **not created**. Quantity is
  /// always 1 — the kiosk sells one membership to one person.
  ///
  /// **A retry never re-sends a `created` item, and an empty retry set sends
  /// NOTHING.** Both halves live in [KioskSignupState.isBeingCharged] over
  /// [KioskSignupState.retryMemberIds], whose `null`-vs-empty distinction is
  /// the double-charge defence: `null` is "nothing has landed, send the cart",
  /// an empty set is "nothing left to send". The two must never collapse into
  /// one — a filter that only applied `whenever the failure set is non-empty`
  /// re-sent the WHOLE cart for a `[created, unknown]` partial (no row is
  /// `failed` there), under the fresh idempotency key a retry mints, which the
  /// backend's `ON CONFLICT (idempotency_key)` guard cannot dedupe. That is a
  /// second real charge on a membership that already started.
  ///
  /// Nothing else is ever re-executed by a retry: no member is created, no
  /// waiver re-signed, no payer re-linked.
  List<MemberMembershipsStartItem> _startItems() {
    final items = <MemberMembershipsStartItem>[];
    for (final person in state.persons) {
      final memberId = person.memberId;
      if (memberId == null || !state.isBeingCharged(person)) continue;
      final price = state.planById(person.selectedPlanId)?.activePrice;
      if (price == null) continue;
      items.add(
        MemberMembershipsStartItem(
          memberId: memberId,
          priceId: price.priceId,
          quantity: 1,
        ),
      );
    }
    return items;
  }

  // ── D7 · pay ──

  /// Fire the start call. **The money moment, and the one method in this file
  /// where every line is a defence.**
  ///
  /// Two independent guards, not one:
  /// 1. the `paying` check is SYNCHRONOUS and the `paying` emit happens before
  ///    any `await`, so a second tap in the same frame sees the new step and
  ///    returns — a double-tap is exactly one charge;
  /// 2. the [_sentAttempts] latch means a key that has already gone out is
  ///    never posted again, whatever happened to the response.
  ///
  /// The idle guard is suspended for the duration (the screen has no buttons
  /// to answer a countdown with) and re-armed on every outcome, and the
  /// session's flow count is deliberately NOT released here — a live charge is
  /// exactly the case the T+11h45 grace window exists for.
  Future<void> pay() async {
    if (state.step == KioskSignupStep.paying) return;
    final paymentMethodId = state.paymentMethodId;
    // **Nothing to charge with is a handoff, never a silent return.** By the
    // time Pay is live the review's primary has a real preview behind it, so
    // this is an anomaly — and a bare `return` is the worst outcome available:
    // [retrySameCard] has already cancelled the popup's return countdown before
    // it calls this, so returning quietly parks a shared iPad on a popup with
    // no clock, no escape (§2 — the decline screen deliberately has none) and
    // no way home. There is ALWAYS a countdown home. "Nothing was charged" is
    // exactly true here, because nothing was sent.
    if (paymentMethodId == null) {
      log('Kiosk signup: pay with no card on state');
      _stop(KioskSignupStopReason.paymentFailed);
      return;
    }
    final key = state.idempotencyKey ?? newIdempotencyKey();
    if (_sentAttempts.contains(key)) {
      _stop(KioskSignupStopReason.paymentUnconfirmed);
      return;
    }
    final request = _buildStartRequest(
      idempotencyKey: key,
      payment: MemberMembershipsStartPayment(
        paymentMethodId: paymentMethodId,
        // **Always true, whatever the cart holds.** The kiosk takes a fresh
        // card every time and that card becomes the payer's default, replacing
        // whatever was on the profile — which is what makes an existing member
        // able to self-serve here at all. The card step says so in as many
        // words, because it is a consequence the member has to register.
        setDefault: true,
      ),
    );
    // Nothing to send — an unassemblable request, or a retry set with nothing
    // left in it. Same rule as the null card above: a countdown home, not a
    // dead screen. Nothing left the device, so "nothing was charged" holds.
    if (request == null) {
      log('Kiosk signup: start request could not be assembled');
      _stop(KioskSignupStopReason.paymentFailed);
      return;
    }
    _sentAttempts.add(key);
    final previous = state.startResult;
    suspendIdle();
    emit(state.copyWith(
      step: KioskSignupStep.paying,
      idempotencyKey: key,
      startResult: null,
    ));
    try {
      final result = await _memberRepo.startMemberships(
        request,
        receiveTimeout: kKioskSignupStartTimeout,
      );
      if (isClosed) return;
      resumeIdle();
      // A 207 is a 2xx: a decline arrives as a RESULT in the body, never as an
      // HTTP error, so the split is read off the ITEMS rather than the status —
      // and it is a THREE-way split, not two:
      //
      // * nothing to itemise → straight to welcome, for the same reason a 409
      //   does: a receipt with no rows is worse than the warm welcome;
      // * every item refused → the decline popup, whose "you haven't been
      //   charged" is TRUE and whose retry ladder the founder settled;
      // * anything else (all created, or a PARTIAL) → the results receipt.
      //   On a partial money HAS moved for the group that cleared, so the
      //   decline popup's copy would be a false statement about it.
      final merged = _mergeStartResults(previous, result);
      if (merged.results.isEmpty) {
        _enterWelcome();
        return;
      }
      if (merged.results.every((item) => item.isFailed)) {
        _onDeclined(merged);
        return;
      }
      _enterResults(merged);
    } on WaiverGateException catch (e, st) {
      log('Kiosk signup: start waiver gate', error: e, stackTrace: st);
      if (isClosed) return;
      resumeIdle();
      _routeToWaiverGate(e);
    } on ServerException catch (e, st) {
      if (isClosed) return;
      resumeIdle();
      // 409 = the backend detected an idempotent replay: the ORIGINAL start
      // stands, rows, signatures and charge included. That is a SUCCESS from
      // the member's side, and charging again is the one thing it must never
      // become.
      if (e.statusCode == 409) {
        _enterWelcome();
        return;
      }
      log('Kiosk signup: start failed', error: e, stackTrace: st);
      _stop(KioskSignupStopReason.paymentFailed);
    } catch (e, st) {
      log('Kiosk signup: start failed', error: e, stackTrace: st);
      if (isClosed) return;
      resumeIdle();
      _stop(KioskSignupStopReason.paymentFailed);
    }
  }

  // ── D7a · the results receipt ──

  /// Fold a retry's response into the one it retried, so the receipt keeps
  /// every membership THIS SIGNUP produced rather than only the last attempt's.
  ///
  /// A retry re-sends **only** the items the previous start did not create (see
  /// [_startItems]), so its response names only those: without this fold, a
  /// partial that was then retried successfully would print a one-row receipt
  /// headed "every membership below started today" while silently omitting the
  /// one that landed on the first attempt. A receipt that lies by omission about
  /// money is the thing this screen exists to prevent.
  ///
  /// The newer outcome always REPLACES the older one for the same
  /// (member, plan), and a retry carries EVERY un-created item — so
  /// [KioskSignupState.retryMemberIds] over the fold is identical to the latest
  /// response's own un-created set. The retry set cannot grow stale, and
  /// nothing already created can re-enter it.
  ///
  /// `chargeCount` / `multipleCharges` are carried from the latest response and
  /// are deliberately unused by the kiosk: the two-charges note reads the
  /// preview's AMOUNTS (§11.4), never these flags.
  MemberMembershipsStartResponse _mergeStartResults(
    MemberMembershipsStartResponse? previous,
    MemberMembershipsStartResponse landed,
  ) {
    if (previous == null || previous.results.isEmpty) return landed;
    String keyOf(MemberMembershipsStartResultItem item) =>
        '${item.memberId}·${item.planId}';
    final replaced = {for (final item in landed.results) keyOf(item)};
    return MemberMembershipsStartResponse(
      chargeCount: landed.chargeCount,
      multipleCharges: landed.multipleCharges,
      results: [
        for (final item in previous.results)
          if (!replaced.contains(keyOf(item))) item,
        ...landed.results,
      ],
    );
  }

  /// The landed start, itemised per person.
  ///
  /// **The flow count is released only when every item was created.** Then the
  /// money has landed, every row exists and there is nothing left to do but
  /// read and tap Next — releasing here is EARLIER than the old welcome-only
  /// release, which is strictly better for the T+11h45 lockout. On a PARTIAL it
  /// deliberately does not: Retry is live on that screen and [pay] would run a
  /// live charge with no flow held, which is exactly what §11.3 forbids. The
  /// 60-second expiry's [abandon] releases it instead, exactly as the decline
  /// popup relies on.
  ///
  /// [_enterWelcome] keeps its own release: [_flowStarted] is a latch, so on the
  /// all-created path that call is a harmless no-op, and it is still the release
  /// for every other route into welcome (the 409 replay, an empty result).
  /// Deleting it is how the kiosk stops signing itself out at its lockout.
  void _enterResults(MemberMembershipsStartResponse result) {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    final allCreated = result.results.every((item) => item.isCreated);
    if (allCreated) _endFlowIfStarted();
    emit(state.copyWith(
      step: KioskSignupStep.results,
      startResult: result,
      submitting: false,
      idleWarningActive: false,
      idleCountdown: 0,
      planBlockActive: null,
    ));
    _syncIdleTimer();
    _startPopupCountdown();
  }

  /// "Next" — from the receipt to the welcome screen and its app push.
  ///
  /// Offered only on the all-created branch: a partial's decisions are Retry /
  /// another card / the desk, and "continue without them" is a decision about
  /// somebody's membership that belongs at the desk rather than on a lobby iPad.
  void nextFromResults() {
    registerActivity();
    if (state.step != KioskSignupStep.results) return;
    _popupTimer?.cancel();
    _enterWelcome();
  }

  // ── D8 · declined ──

  /// EVERY membership in the cart was refused. The member row, the Stripe
  /// customer and every signature are already committed and are NEVER
  /// re-executed — only the charge is retried, from the decline popup.
  ///
  /// **All-failed only.** The popup states plainly that nothing was charged,
  /// which is true exactly here; a PARTIAL goes to [_enterResults] instead,
  /// because there money HAS moved for the group that cleared.
  ///
  /// **A decline never ends the signup, and no attempt is ever gated by a
  /// wait.** Mistakes are ordinary: the member may retry immediately — the
  /// SAME card ([retrySameCard], the common insufficient-funds case) or a
  /// fresh one ([retryCard]) — as many times as they like. Attempt-velocity
  /// throttling (the card-testing defence on an unattended device) rides
  /// entirely on the platform Stripe Radar rule, not a client cooldown
  /// (founder decision). The desk is an option the member chooses, never a
  /// destination they are sent to.
  ///
  /// The popup still carries a RETURN countdown, which is a different thing
  /// from a cooldown: it decides how long a shared iPad may sit on this screen
  /// with nobody answering it, not how soon Retry may be tapped. Retry is live
  /// from the first frame.
  void _onDeclined(MemberMembershipsStartResponse result) {
    emit(state.copyWith(
      startResult: result,
      step: KioskSignupStep.declined,
      submitting: false,
    ));
    _syncIdleTimer();
    _startPopupCountdown();
  }

  /// The blocking surfaces' shared clock — a plain per-second countdown that
  /// abandons at zero. The decline popup, the plan block and the results
  /// receipt all ride it.
  ///
  /// Expiry runs the ordinary [abandon], so the session's flow count is
  /// released by the ONE latch every other exit uses. That matters most on the
  /// decline and on a PARTIAL receipt, neither of which releases on entry (the
  /// member is still standing there): if nobody answers, this is what releases
  /// it.
  void _startPopupCountdown() {
    _popupTimer?.cancel();
    emit(state.copyWith(popupCountdown: kKioskSignupPopupHold.inSeconds));
    _popupTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      final next = state.popupCountdown - 1;
      if (next <= 0) {
        _popupTimer?.cancel();
        abandon();
      } else {
        emit(state.copyWith(popupCountdown: next));
      }
    });
  }

  /// "Retry" — re-attempt the SAME card. The most common decline is
  /// insufficient funds: the member moves money, then retries the exact card
  /// they already entered, without re-typing it.
  ///
  /// It keeps [KioskSignupState.paymentMethodId] / `cardBrand` / `cardLast4`
  /// and mints a **NEW** idempotency key, then re-fires [pay]. A new key is
  /// mandatory — reusing the already-sent key would replay the decline through
  /// the [_sentAttempts] latch instead of making a genuine fresh attempt.
  /// Nothing else re-runs: [_startItems] re-sends only what the landed start did
  /// not create, and no member is created, no waiver re-signed, no payer
  /// re-linked.
  ///
  /// [pay]'s synchronous `paying` guard + the sent-key latch keep a double-tap
  /// to exactly one charge; the step guard here stops a second tap from minting
  /// a stray key over an in-flight charge. It admits BOTH screens that offer a
  /// retry — the all-failed decline popup and a PARTIAL's results receipt — and
  /// nothing else: widening it further would let a stray key be minted from a
  /// step with no landed response behind it.
  void retrySameCard() {
    registerActivity();
    // **A retry exists only where a landed start left something un-created.**
    // This is the gate, not the step list: an ALL-CREATED receipt is `results`
    // too, and re-firing [pay] from there re-posted the WHOLE cart under a
    // fresh idempotency key — a second real charge on memberships that had
    // already started, which the backend's replay guard cannot dedupe because
    // the key is new. Reading [KioskSignupState.canRetryStart] makes that state
    // unrepresentable rather than a screen somebody has to remember to exclude.
    if (!state.canRetryStart) return;
    if (state.step != KioskSignupStep.declined &&
        state.step != KioskSignupStep.results) {
      return;
    }
    _popupTimer?.cancel();
    emit(state.copyWith(
      idempotencyKey: newIdempotencyKey(),
      popupCountdown: 0,
      // **The preview on state prices the WHOLE cart, and this retry does
      // not.** The paying screen states that figure as what is being taken, so
      // keeping it would watch a member through "$200.00" while $100 is
      // charged. Cleared here (nothing states a stale amount) and re-priced
      // below against the same filtered items the charge carries — the sibling
      // [retryCard] gets this for free by passing through the card step.
      preview: null,
    ));
    // **The order is load-bearing.** Both requests are narrowed by
    // `state.startResult`, which [pay] clears the instant it emits `paying`, so
    // a preview fired afterwards would re-price the whole cart and put the
    // wrong number back on the screen. `_loadPreview` builds its request
    // synchronously, before its first await, so calling it first is enough.
    // A preview failure is silent here (see [_failPreview]): the charge is the
    // authoritative thing on this screen, and Retry must never be gated on a
    // read.
    unawaited(_loadPreview());
    unawaited(pay());
  }

  /// "Try another card" — back to the card step with a genuinely FRESH field.
  ///
  /// Unlike [retrySameCard], this CLEARS the card so the member enters a
  /// different one. The key is dropped rather than reused: [submitCard] mints a
  /// fresh one on the way into the review, so a deliberate retry is a genuinely
  /// new attempt with a new `pm_…`. Nothing else re-runs — no member is
  /// created, no waiver is re-signed, no plan is re-picked.
  ///
  /// **[KioskSignupState.cardAttempt] is bumped so the Stripe `CardField` is
  /// re-keyed and mounts an EMPTY iframe.** The web card field's platform view
  /// is cached across mounts, so without a changing key the retry would re-show
  /// the declined number and the member could not type a new one — the bug this
  /// bump fixes.
  void retryCard() {
    registerActivity();
    _popupTimer?.cancel();
    emit(state.copyWith(
      step: KioskSignupStep.card,
      cardAttempt: state.cardAttempt + 1,
      paymentMethodId: null,
      cardBrand: null,
      cardLast4: null,
      idempotencyKey: null,
      preview: null,
      popupCountdown: 0,
    ));
    _syncIdleTimer();
  }

  /// "Get help at the desk" — the handoff the member CHOOSES.
  ///
  /// It is deliberately NOT an abandon: everything already committed stays
  /// committed, and the desk picks the thread up from the incomplete-signups
  /// list. Dropping the member at a clean home screen with a half-built
  /// account is the outcome this button exists to avoid. Nothing ever routes
  /// here on the member's behalf.
  void getHelpAtDesk() => _stop(KioskSignupStopReason.cardDeclined);

  // ── Welcome ──

  /// The signup's terminal celebration.
  ///
  /// Its [_endFlowIfStarted] call stays even though the all-created results
  /// screen has already released: [_flowStarted] is a latch, so the second call
  /// is a no-op, and this is still the ONLY release for the other routes here
  /// (the 409 idempotent replay and a landed start with nothing to itemise).
  void _enterWelcome() {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _popupTimer?.cancel();
    // The flow is over: release the session's count here, exactly once.
    _endFlowIfStarted();
    emit(state.copyWith(
      step: KioskSignupStep.welcome,
      submitting: false,
      idleWarningActive: false,
      idleCountdown: 0,
      startResult: null,
      planBlockActive: null,
      popupCountdown: 0,
      welcomeCountdown: kKioskSignupWelcomeHold.inSeconds,
    ));
    _welcomeTimer?.cancel();
    _welcomeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      final next = state.welcomeCountdown - 1;
      if (next <= 0) {
        _welcomeTimer?.cancel();
        abandon();
      } else {
        emit(state.copyWith(welcomeCountdown: next));
      }
    });
  }

  /// The group step's "someone who's already a member" read.
  ///
  /// The debounce + sequence guard live in [searchExistingPeople], which is
  /// what the match step drives; this is the plain read underneath it.
  Future<List<MemberRow>> findExistingPeople(String query) async {
    final page = await _membersListRepo.getMembersList(
      CrmMembersListRequest(
        gymId: _gymId,
        view: MembersListView.all,
        filters: MembersListFilters(name: query.trim()),
        startIndex: 0,
        count: kKioskSearchResultCount,
      ),
    );
    return page.data;
  }

  // ── Terminal stop ──

  /// Enter a front-desk stop and start the 15-second auto-return.
  ///
  /// A TERMINAL reason releases the session flow here, exactly once. A
  /// **retryable** one deliberately does not: the member is still standing
  /// there and may tap "Try again", and a released count during a live flow is
  /// the same bookkeeping bug as a leaked one. If they walk off instead, the
  /// auto-return's `abandon()` releases it — the latch makes the pair
  /// exactly-once either way.
  void _stop(KioskSignupStopReason reason) {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _popupTimer?.cancel();
    if (!reason.isRetryable) _endFlowIfStarted();
    emit(state.copyWith(
      step: KioskSignupStep.stop,
      stopReason: reason,
      submitting: false,
      idleWarningActive: false,
      idleCountdown: 0,
      abandonConfirmActive: false,
      removeConfirmIndex: null,
      planBlockActive: null,
      popupCountdown: 0,
      stopCountdown: kKioskSignupStopHold.inSeconds,
    ));
    _startStopCountdown();
  }

  /// The stop screen's own clock — a plain per-second countdown that abandons
  /// at zero. Member interaction does NOT reset it: a dead end is not a draft,
  /// and leaving a stop screen up on a shared iPad helps nobody.
  void _startStopCountdown() {
    _stopTimer?.cancel();
    _stopTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      final next = state.stopCountdown - 1;
      if (next <= 0) {
        _stopTimer?.cancel();
        abandon();
      } else {
        emit(state.copyWith(stopCountdown: next));
      }
    });
  }

  /// "Try again" on a retryable stop — return to the step and re-run the read
  /// that failed. Only the two pure-read reasons offer it; a money path never
  /// auto-retries, and neither does a duplicate.
  void stopRetry() {
    final reason = state.stopReason;
    if (reason == null || !reason.isRetryable) return;
    _stopTimer?.cancel();
    if (reason == KioskSignupStopReason.plansUnavailable) {
      emit(state.copyWith(
        step: KioskSignupStep.plans,
        stopReason: null,
        stopCountdown: 0,
      ));
      registerActivity();
      unawaited(_warmPlans());
      return;
    }
    emit(state.copyWith(
      step: KioskSignupStep.review,
      stopReason: null,
      stopCountdown: 0,
    ));
    registerActivity();
    unawaited(_loadPreview());
  }

  // ── Abandon ──

  /// Ask before abandoning — the "Start over?" confirmation.
  ///
  /// Confirmation is proportional to what is lost, so this is used only from
  /// the steps where real work dies (card / review). Every earlier step
  /// abandons on the first tap: the most it costs is a minute of retyping, and
  /// a confirm dialog there is a second trap for a member who already
  /// mis-tapped. **The 5-minute clock keeps running behind it** — an
  /// unanswered dialog must never pin half-typed card details on a lobby iPad.
  void askAbandon() {
    emit(state.copyWith(abandonConfirmActive: true));
  }

  /// "Keep going" — dismiss the confirmation. It counts as member
  /// interaction, so the idle clock resets.
  void dismissAbandon() {
    emit(state.copyWith(abandonConfirmActive: false));
    registerActivity();
  }

  /// End the flow and send the surface home. The ONE exit: the escape's
  /// "Start over", the confirmed "Yes, start over", the idle timeout, and both
  /// stop-screen exits all come through here.
  ///
  /// It does not navigate — `KioskSignupScreen` watches
  /// [KioskSignupState.abandoned] and calls `KioskFlowCubit.goHome()`, which
  /// already IS the kiosk's whole abandon contract. Unmounting this subtree
  /// then closes the cubit, so every typed field dies with it.
  void abandon() {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _stopTimer?.cancel();
    _welcomeTimer?.cancel();
    _popupTimer?.cancel();
    _searchDebounce?.cancel();
    _endFlowIfStarted();
    emit(state.copyWith(
      abandoned: true,
      abandonConfirmActive: false,
      removeConfirmIndex: null,
      planBlockActive: null,
      popupCountdown: 0,
      idleWarningActive: false,
      idleCountdown: 0,
    ));
  }

  // ── Flow-idle guard (the signup lane's own clock) ──

  /// Any member interaction: dismiss the idle warning if showing and reset the
  /// 5-minute clock. Wired to a pointer listener over the signup surface AND
  /// called by every interactive method here.
  void registerActivity() {
    if (state.idleWarningActive) {
      emit(state.copyWith(idleWarningActive: false, idleCountdown: 0));
    }
    _syncIdleTimer();
  }

  /// Stop the idle guard while a step owns the clock itself.
  ///
  /// [pay] calls this before the start request and [resumeIdle] on every
  /// outcome: a charge in flight must never be interrupted by a 30-second
  /// countdown, and the Paying screen has no buttons to answer one with.
  void suspendIdle() {
    _idleSuspended = true;
    _syncIdleTimer();
  }

  /// Re-arm the idle guard with a full fresh 5 minutes.
  void resumeIdle() {
    _idleSuspended = false;
    _syncIdleTimer();
  }

  void _syncIdleTimer() {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    if (_idleSuspended) return;
    // The terminals run their own clocks (or none): the stop screen has its
    // 15s auto-return, the results receipt and the welcome their 60s ones, the
    // payment step must never be interrupted, and a landed flow has no draft
    // left to abandon.
    if (state.step == KioskSignupStep.paying ||
        state.step == KioskSignupStep.stop ||
        state.step == KioskSignupStep.results ||
        state.step == KioskSignupStep.welcome) {
      return;
    }
    if (state.abandoned) return;
    if (!state.idleWarningActive) {
      _idleTimer = Timer(kKioskIdleTimeout, _onIdle);
    }
  }

  void _onIdle() {
    if (isClosed) return;
    emit(state.copyWith(
      idleWarningActive: true,
      idleCountdown: kKioskIdleCountdown.inSeconds,
    ));
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      final next = state.idleCountdown - 1;
      if (next <= 0) {
        _countdownTimer?.cancel();
        abandon();
      } else {
        emit(state.copyWith(idleCountdown: next));
      }
    });
  }

  // ── Session flow accounting (grace-window bookkeeping) ──

  void _startFlow() {
    if (_flowStarted) return;
    _flowStarted = true;
    _session.beginFlow();
  }

  void _endFlowIfStarted() {
    if (!_flowStarted) return;
    _flowStarted = false;
    _session.endFlow();
  }

  // ── Roster helpers ──

  void _updateActivePerson(
    KioskSignupPerson Function(KioskSignupPerson) update,
  ) {
    final index = state.activePersonIndex;
    final persons = [...state.persons];
    final at = (index >= 0 && index < persons.length) ? index : 0;
    persons[at] = update(persons[at]);
    emit(state.copyWith(persons: persons));
  }

  /// The trimmed value, or null when empty — an omitted optional field.
  /// Mirrors `MemberCreateFormState._opt`.
  String? _opt(String? value) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  /// How much of the optional block this person filled in — the roster chip's
  /// readout. Partial is the NORMAL case and is never treated as a problem.
  KioskSignupDetailsStatus _statusOf({
    DateTime? dob,
    String? address,
    String? ecName,
    String? ecPhone,
    String? ecEmail,
  }) {
    final given = <Object?>[dob, address, ecName, ecPhone, ecEmail]
        .where((v) => v != null)
        .length;
    if (given == 0) return KioskSignupDetailsStatus.none;
    if (given == 5) return KioskSignupDetailsStatus.complete;
    return KioskSignupDetailsStatus.partial;
  }

  /// The signup's clock. Held for the later steps (the review's next-billing
  /// date and the welcome screen both read it) and to keep the cubit
  /// deterministic under `fakeAsync`.
  DateTime get now => _now();

  /// A fresh idempotency key for a deliberate start attempt.
  ///
  /// One is minted on the way into the review, so a double-tap on Pay reuses
  /// the key already on [KioskSignupState.idempotencyKey]; a deliberate retry
  /// after a decline goes back through the card step and mints a NEW one.
  String newIdempotencyKey() => _uuid();

  @override
  Future<void> close() {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _stopTimer?.cancel();
    _welcomeTimer?.cancel();
    _popupTimer?.cancel();
    _searchDebounce?.cancel();
    // Balance a mid-flow teardown: without this the session's flow count stays
    // incremented and the kiosk never signs itself out at its lockout.
    // `endFlow` is a pure in-memory decrement, safe post-close, and the latch
    // makes the pair exactly-once however this cubit was reached.
    _endFlowIfStarted();
    return super.close();
  }
}
