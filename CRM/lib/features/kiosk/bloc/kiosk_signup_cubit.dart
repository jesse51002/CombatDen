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
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/membership_flow/domain/catalogue_policy.dart';
import 'package:crm/features/membership_flow/domain/plan_rules.dart';
import 'package:crm/features/membership_flow/domain/start_request_builder.dart'
    as flow;
import 'package:crm/features/membership_flow/domain/waiver_queue.dart';
import 'package:crm/features/memberships/data/models/member_waiver_status.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

/// How long a terminal front-desk stop stays up before it returns home on its
/// own, so a member who walks off doesn't leave the kiosk on a dead end.
const Duration kKioskSignupStopHold = Duration(seconds: 15);

/// How long a BLOCKING signup surface (the decline popup, the plan block, the
/// results receipt) holds before returning home. Every blocking overlay draws
/// this countdown INSIDE the popup — a timer hidden behind one takes a shared
/// iPad away without the member seeing it go. Longer than
/// [kKioskSignupStopHold]: somebody is standing at these, reading.
const Duration kKioskSignupPopupHold = Duration(seconds: 60);

/// How long the welcome screen holds before returning home, so a member who
/// walks off with their phone doesn't leave their name up for the next person.
const Duration kKioskSignupWelcomeHold = Duration(seconds: 60);

/// The response wait for the ONE start call: a Connect charge takes 10–60s, so
/// the shared 30s default would false-fail a charge that actually went through
/// — the worst outcome on this screen. Only the *receive* wait moves.
const Duration kKioskSignupStartTimeout = Duration(seconds: 90);

/// One member's answer from the plan-history read, carried per member so a
/// concurrent gather can never mix two rosters' answers up. A FAILED read is
/// the fail-OPEN answer itself (no trial, nothing held), not an absence — the
/// plan gates block on a positive fact. The waiver twin below inverts this.
typedef _KioskPlanHistory = ({
  String memberId,
  bool hadTrial,
  List<String> heldRecurring,
});

/// One member's answer from the prior-signature read. `satisfied == null` is
/// the fail-CLOSED signal and differs from an empty set: null means the read
/// did not land, so NOTHING may be skipped for that member; empty means the
/// server answered and named nothing compliant. Carrying that distinction in
/// the TYPE is what stops a caller collapsing the two.
typedef _KioskWaiverHistory = ({String memberId, Set<String>? satisfied});

/// The kiosk SELF-SERVE SIGNUP lane — a sibling of [KioskFlowCubit], not more
/// fields on it. Provided by `KioskSignupScreen`, so its lifetime IS the
/// flow's: leaving the view runs [close] and disposes the typed PII
/// structurally.
///
/// Flow-count discipline: [KioskSessionCubit.beginFlow] fires once, in the
/// constructor, behind the [_flowStarted] latch; [_endFlowIfStarted] fires on
/// welcome, a stop, an ALL-CREATED results, [abandon] and [close], and the
/// latch makes the pair exactly-once. Declined, a PARTIAL results (Retry is
/// live there, and a live charge must never run with no flow held) and paying
/// deliberately do NOT release — an unbalanced count means the kiosk never
/// signs itself out at its lockout.
///
/// It cannot navigate: every exit raises [KioskSignupState.abandoned] and the
/// screen routes it to the ONE `KioskFlowCubit.goHome()`. Never add a second.
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
    // Reaching this constructor IS the flow starting; the caller has already
    // checked `canStartFlow`.
    _startFlow();
    _syncIdleTimer();
    // The catalogue is gym-wide and the plans step must open with no network
    // wait. A failure is non-fatal: the step retries.
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
  /// never asks twice. A FAILED read counts as asked: re-asking a flaky
  /// endpoint on every roster change buys nothing.
  final Set<String> _planChecked = <String>{};

  /// Members whose PRIOR waiver signatures have already been read, so the
  /// waiver run never asks twice. A FAILED read counts as asked: its cost is
  /// one needless re-signature (the read fails CLOSED).
  final Set<String> _waiverStatusChecked = <String>{};

  /// Per member, the waivers the gym ALREADY holds a compliant signature for
  /// (signed at or above that waiver's re-sign floor). A private cache,
  /// deliberately not state: it has no render path, so a read landing late can
  /// never re-shape a waiver queue the member is already looking at.
  final Map<String, Set<String>> _priorSatisfiedWaiverIds =
      <String, Set<String>>{};

  /// Which name-search response is still wanted. Every fetch takes the next
  /// number and a landing response that no longer holds it is DISCARDED, so a
  /// slow reply for "el" can never overwrite the results for "ella".
  int _searchSeq = 0;

  /// Every idempotency key a start POST has already gone out for — the "sent"
  /// latch, and the load-bearing double-charge defence. Once a request has left
  /// the device its outcome may be unknown, and re-posting the same key is the
  /// ONE action that could take a member's money twice, so an ambiguous attempt
  /// routes to the front desk and NEVER auto-retries.
  final Set<String> _sentAttempts = <String>{};

  /// Whether this flow has told the session it started, so the end is balanced
  /// — exactly one [KioskSessionCubit.endFlow] per beginFlow.
  bool _flowStarted = false;

  /// Set while a step owns the clock itself (payment, which must not be
  /// interrupted mid-charge). [resumeIdle] re-arms a full fresh 5 minutes.
  bool _idleSuspended = false;

  /// Guards the create/update call against a double-tap on Continue.
  bool _committing = false;

  // ── D0 · new here, or already a member ──

  /// "I'm new here" — the ordinary create path.
  void startAsNewMember() {
    registerActivity();
    emit(state.copyWith(step: KioskSignupStep.details));
    _syncIdleTimer();
  }

  /// "Find my name" — the existing member identifies themselves instead of
  /// typing a second account into being. The search is cleared on the way in so
  /// the screen never opens on the previous person's query or results.
  void startAsExistingMember() {
    registerActivity();
    _clearSearch();
    emit(state.copyWith(step: KioskSignupStep.identify));
    _syncIdleTimer();
  }

  // ── D1 · details ──

  /// Record the details step's fields and advance to the extra-details step.
  /// Nothing is written here: the member is created at the END of the NEXT step
  /// so one request carries every field, and an abandoned signup leaves no
  /// written member holding PII.
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

  /// Continue (or Skip — the same call) from the extra-details step; Skip is
  /// not a discard, it carries whatever was typed forward. This is the flow's
  /// FIRST write, and it branches on whether the person is already committed
  /// (ruling 11): not committed → `POST /members/`; committed (they pressed
  /// Back, fixed a typo and came forward) → `PUT /members/{id}`, never a second
  /// create, which would 409 against their own just-created account.
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

  /// A 409 on the PAYER's own create — they already have an account here. They
  /// just typed this name and email, so confirming THEIR OWN account back to
  /// them leaks nothing and adopting it is right: the lane is self-serve for
  /// existing members too. A 409 that names nobody is not an offer anybody can
  /// answer, so it lands on the terminal stop; matches are never a LIST.
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

  /// "Yes, that's me" — adopt the existing account as the payer. Nothing is
  /// created or written: this only points the payer seat at their id and marks
  /// them [KioskSignupPerson.wasExisting], so the roster offers no Edit and the
  /// details step is skipped — the kiosk never prints or overwrites a record it
  /// does not own.
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

  /// "No, that's not me" — where it goes depends on how the match was reached.
  /// From the IDENTIFY search they mis-tapped a name and nothing has committed,
  /// so it returns to the search with their query intact; from a duplicate 409
  /// the create has already been refused, so it is the terminal stop.
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
  /// after the payer was deleted. It reuses the ONE name search, and is gated
  /// on [KioskSignupState.canAssignPayer], which is true both while a payer is
  /// still free to move and while there is none yet.
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

  /// The ONE path a payer is ever seated by — the roster and the CRM search
  /// both come through here with nothing special-cased. Gated on
  /// [KioskSignupState.canAssignPayer] (nothing linked, nothing signed), which
  /// covers both a switch and a first choice after a delete.
  ///
  /// There is NO card check (the fresh-card law): an existing member with a
  /// card on file still types a fresh one, and it replaces theirs. What the
  /// kiosk never does is CHARGE a card it did not just take.
  void _seatPayer(void Function() seat) {
    if (_committing || !state.canAssignPayer) return;
    seat();
  }

  /// A CRM search row becomes the payer — somebody not on the roster yet. On
  /// the IDENTIFY step the same row means the person is naming THEMSELVES, so
  /// it routes to the confirm card instead. A hit already on the roster is a
  /// redirect, not a rejection: a second entry for one member would put two
  /// cart items on one person. The one silent no-op is whoever is ALREADY
  /// paying, tested on `hasPayer && index == 0` like [pickPayerFromRoster] —
  /// once the payer is DELETED, index 0 must still be seatable.
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

  /// A row tapped on the identify step — "that's me". It still CONFIRMS before
  /// adopting: two members can share a name, and a mis-tap on a shared iPad
  /// would otherwise seat a stranger's account as the payer.
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

  /// A person ALREADY on the roster becomes the payer, through the same one
  /// seat path as a CRM pick. Picking whoever ALREADY pays (index 0 while a
  /// payer exists) is a no-op; with the payer deleted, index 0 is a real
  /// candidate like any other.
  Future<void> pickPayerFromRoster(int index) async {
    registerActivity();
    if (index < 0 || index >= state.persons.length) return;
    if (state.hasPayer && index == 0) return;
    if (state.persons[index].memberId == null) return;
    _seatPayer(() => _promoteRosterPayer(index));
  }

  /// Seat a member who was NOT on the roster, inserting them at its head.
  ///
  /// Only the PAYER role moves: the person who started this signup keeps their
  /// seat and becomes a payee, so they now need the payer-authorization waiver
  /// like every other payee — [KioskSignupState.everyPayeeLinked] covers them
  /// for free, and no request can assemble until the new payer authorizes them.
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
  /// the seat they vacate. A straight SWAP of positions 0 and [index], so every
  /// other index — and every signature, link and plan keyed on them — is
  /// untouched. Only the payer role moves; the promoted person keeps their own
  /// "getting a membership" choice and their plan.
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

  /// Turn "getting a membership" on or off for ONE person — whether they are
  /// in the CART at all. `payer_member_id` is identity-only server-side, so a
  /// parent can pay for their kids without buying anything themselves, and
  /// everybody can be unchecked (a registration-only signup, not an error — see
  /// [continueToPlans]). Turning it off drops their plan with it, so a stale
  /// pick can't return the moment the row is re-checked by accident.
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

  /// Open one person's optional-details screen from their roster row's Edit —
  /// the payer's is D1a, everyone else's E1a.
  ///
  /// Only for a person this signup CREATED: an existing member's stored details
  /// are never shown on a shared screen, so the roster offers them no Edit and
  /// this refuses the call too, in case a future caller routes one in.
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

  /// Ask before taking somebody off the roster: there is no undo and the rows
  /// sit close together at kiosk scale. The confirmation names the person.
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

  /// Take a person off the roster, only through the confirmation and only while
  /// it is still free ([KioskSignupState.canRemovePerson]). Their member shell
  /// is deliberately left alone: harmless, nothing to unlink, and it surfaces
  /// in the staff "Incomplete" list.
  ///
  /// Removing the PAYER always asks who pays next (founder ruling: nobody is
  /// auto-assigned) — the signup is left with NO payer and routed into the
  /// picker, and the People step blocks Continue until one is set, so a
  /// no-payer state can never reach Pay.
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
      // A duplicate is an OFFER, never a list: reusing an existing account is
      // the right answer, and naming one person back to whoever just typed
      // their details leaks nothing. The terminal stop is for a 409 that names
      // NOBODY — see [_offerPayerMatch], which draws the same line.
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
        // step opens on the search rather than an empty card.
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
  /// A person this signup CREATED goes on to their own details screen; an
  /// EXISTING member skips it entirely — the kiosk cannot show their stored
  /// details on a shared screen and will not overwrite a record it does not
  /// own, so a blank-field pass could only ask for what the gym already has.
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

  /// Continue from a payee's optional block. It sends only the optional fields,
  /// and only when something was typed — never the name or email: for a matched
  /// EXISTING member this screen opened blank on purpose, and a write built
  /// from fields that never showed a value must not be able to wipe it.
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

  /// Skip a payee's optional block. It fires nothing and records nothing, so
  /// the roster chip stays honest about what is actually on file.
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

  /// Step BACK one screen. Nothing it lands on is un-done by arriving there (a
  /// created member stays created, a signed waiver stays signed);
  /// [KioskSignupState.committedSteps] is what keeps the forward call correct
  /// when the member continues again.
  void back() {
    registerActivity();
    // The plan step is walked once PER TRAINING PERSON, so its Back is a move
    // within the step before it is a move out of it.
    if (state.step == KioskSignupStep.plans && _backToPreviousPlanPerson()) {
      return;
    }
    final previous = switch (state.step) {
      // The first fork is a safe destination — nothing has been typed on
      // either side of it.
      KioskSignupStep.details => KioskSignupStep.entry,
      KioskSignupStep.identify => KioskSignupStep.entry,
      KioskSignupStep.extraDetails => KioskSignupStep.details,
      // Back out of the roster lands on the payer's own optional block — the
      // only route by which a member returns to a COMMITTED step to fix a
      // typo'd email (ruling 11). An ADOPTED existing payer has no such block
      // (the kiosk must never PUT its guess over the gym's record), so Back is
      // not offered to them at all.
      KioskSignupStep.people =>
        state.payer.wasExisting ? null : KioskSignupStep.extraDetails,
      KioskSignupStep.plans => KioskSignupStep.people,
      // Back out of a waiver lands on the plan pick, because the plan DECIDES
      // which waivers there are. Anything already signed stays signed.
      KioskSignupStep.waivers => KioskSignupStep.plans,
      // Back out of the card lands on the PLAN, not the waiver behind it: a
      // signature cannot be taken back, so a re-entered waiver step with
      // nothing left to sign would bounce straight forward again.
      KioskSignupStep.card => KioskSignupStep.plans,
      // Back out of the review lands on the card: a Stripe element cannot be
      // re-populated, so re-entering the step means re-entering the card — and
      // that is the point, the card never lives anywhere it could be re-read.
      KioskSignupStep.review => KioskSignupStep.card,
      // Both roster side-trips land back on the roster. A payee is already
      // CREATED by the time either screen opens, so neither un-does anything.
      KioskSignupStep.personDetails => KioskSignupStep.people,
      KioskSignupStep.match => KioskSignupStep.people,
      // The picker changes nothing until a pick is seated.
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
    // Backing out of the identify search drops what a stranger typed and the
    // rows it turned up — the shared-iPad rule.
    if (state.step == KioskSignupStep.identify) {
      _clearSearch();
      emit(state.copyWith(step: previous));
      _syncIdleTimer();
      return;
    }
    // Back into the card step must hand over a genuinely EMPTY field, so it
    // bumps `cardAttempt` exactly as [retryCard] does (see there for the cached
    // platform view). The card facts, key and preview go with it, so state
    // never claims a card the member cannot see.
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
    // Backing out of the match offer drops the draft it was about: nothing was
    // written, and a half-added person left on state would pre-fill the next
    // "Add someone new" with somebody else.
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

  /// The gym's offerable plans: public, and priced. A plan with no active
  /// price has nothing to charge, and a non-public plan is not part of the
  /// gym's offer. The filter itself is the shared catalogue policy
  /// (`membership_flow/domain/catalogue_policy.dart`), which the desk applies
  /// too — one catalogue, both surfaces.
  Future<void> _warmPlans() async {
    emit(state.copyWith(plansLoading: true, plansFailed: false));
    try {
      final all = await _membershipsRepo.listPlans(_gymId);
      if (isClosed) return;
      final offered = sellablePlans(all);
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
      // Non-fatal at ENTRY (the member is still typing their name and the step
      // retries); terminal-but-retryable once they are standing on it.
      if (state.step == KioskSignupStep.plans) {
        _stop(KioskSignupStopReason.plansUnavailable);
      }
    }
  }

  /// Enter the plan pick — the roster step's exit. It resolves the catalogue's
  /// three states rather than rendering an empty step: still warming → the
  /// step's spinner, answered when the warm lands; a failed warm → try once
  /// more; a warm with nothing to sell → the gym-setup stop.
  void continueToPlans() {
    registerActivity();
    // The no-payer guard: nothing is auto-assigned when the payer is deleted,
    // so a signup with no payer must not route into the money path.
    if (!state.hasPayer) return;
    // The empty-cart guard: a roster with nobody getting a membership would
    // send `memberships: []` and take a 400.
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
    // And which waivers each of them has already signed compliantly — fired
    // here because the waiver run is two taps away, so the answer is in hand
    // before the first waiver is drawn and no queue on screen is re-shaped.
    unawaited(_loadPriorWaiverStatus());
    if (state.plansLoading) return;
    if (state.plansFailed) {
      unawaited(_warmPlans());
      return;
    }
    if (state.plans.isEmpty) _stop(KioskSignupStopReason.noPlansOffered);
  }

  /// Read which plans are closed to whom on this roster — the trial history and
  /// the recurring plans they already hold, from ONE response each. Only for a
  /// person the kiosk did not create; anyone registered during this signup has
  /// no history by construction. Only the two facts below are kept: the rest of
  /// the heavy staff payload is dropped, never rendered, logged or persisted.
  ///
  /// Both gates FAIL OPEN, the deliberate inverse of the waiver read: blocking
  /// a legitimate first-timer sends a paying customer away, while a second
  /// trial costs one free week the desk can undo — and a failed read does not
  /// say WHICH plan somebody holds, so fail-closed would have to block the
  /// whole grid. The accepted cost is a member picking a plan they already hold
  /// and hitting a retryable stop at the review.
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
    final answers = await Future.wait(wanted.map(_readPlanHistory));
    if (isClosed) return;
    // Only an answer that actually CLOSES something is written back: a clean
    // history leaves the person untouched rather than emitting a no-op.
    final closing = <String, _KioskPlanHistory>{
      for (final answer in answers)
        if (answer.hadTrial || answer.heldRecurring.isNotEmpty)
          answer.memberId: answer,
    };
    if (closing.isEmpty) return;
    // ONE emit for the whole roster — a per-person emit would repaint the grid
    // once per member for no gain.
    final persons = <KioskSignupPerson>[];
    for (final person in state.persons) {
      final answer = closing[person.memberId];
      if (answer == null) {
        persons.add(person);
        continue;
      }
      persons.add(_clearBlockedPick(person.copyWith(
        hadTrial: answer.hadTrial,
        heldRecurringPlanIds: answer.heldRecurring,
      )));
    }
    emit(state.copyWith(persons: persons));
  }

  /// One member's plan history, reduced to the TWO facts the grid needs.
  ///
  /// It never throws, and that is what keeps [Future.wait] honest: it
  /// propagates the FIRST error, so a throwing read would discard every
  /// sibling's answer. Catching per member makes the gathered list total — one
  /// failure is one fail-OPEN answer (see [_loadPlanEligibility]).
  Future<_KioskPlanHistory> _readPlanHistory(String memberId) async {
    try {
      final detail = await _memberRepo.getMemberDetail(memberId);
      // Both facts are derived by the shared rulebook's own gate factories —
      // the trial rule over every membership row ever held (a trial finished a
      // year ago still counts), and the held set over the backend's conflict
      // guard (`member_memberships_check_existing.sql`) translated into the
      // client's wider display enum. Neither status list is restated here: the
      // desk reads the same two factories, so the two clients cannot drift.
      return (
        memberId: memberId,
        hadTrial: TrialOnceGate.fromMemberships(detail.memberships).hadTrial,
        heldRecurring:
            RecurringHeldGate.fromMemberships(detail.memberships)
                .heldPlanIds
                .toList(),
      );
    } catch (e, st) {
      log('Kiosk signup: membership history read failed (nothing blocked)',
          error: e, stackTrace: st);
      return (
        memberId: memberId,
        hadTrial: false,
        heldRecurring: const <String>[],
      );
    }
  }

  /// Read which waivers each EXISTING person on the roster has already signed
  /// compliantly, so the run never re-asks for a signature the gym holds. Only
  /// for a person the kiosk did not create. `meets_floor` is the SERVER's
  /// compliance verdict — the same rule the 422 purchase gate and the check-in
  /// gate apply — and the floor is never re-derived here.
  ///
  /// This read FAILS CLOSED, the exact inverse of [_loadPlanEligibility]: a
  /// needless signature costs the member twenty seconds, a MISSING one voids
  /// the gym's legal protection. A throw writes NO entry, so every waiver on
  /// the plan is asked for.
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
    final answers = await Future.wait(wanted.map(_readSatisfiedWaivers));
    if (isClosed) return;
    for (final answer in answers) {
      final satisfied = answer.satisfied;
      // Null is the fail-CLOSED answer and must NOT be written: no entry means
      // `_satisfiedWaiverIdsFor` hands back the empty set, so nothing is
      // skipped. An empty set written here would quietly become "we asked and
      // they owe nothing" the moment anything tells the two apart.
      if (satisfied == null) continue;
      _priorSatisfiedWaiverIds[answer.memberId] = satisfied;
    }
  }

  /// The waivers one member's own signatures already satisfy, or null when the
  /// read failed — the fail-CLOSED signal. It never throws, for the same reason
  /// [_readPlanHistory] does not: here, one failed read would make a whole
  /// family re-sign what the gym already holds.
  Future<_KioskWaiverHistory> _readSatisfiedWaivers(String memberId) async {
    List<MemberWaiverStatus> rows;
    try {
      rows = await _membershipsRepo.listMemberWaiverStatus(memberId, _gymId);
    } catch (e, st) {
      log('Kiosk signup: prior waiver status read failed '
          '(every waiver on the plan will be asked for)',
          error: e, stackTrace: st);
      // Fail CLOSED: no answer at all, so nothing is skipped for them.
      return (memberId: memberId, satisfied: null);
    }
    // `signed && meetsFloor` and nothing else: a row signed BELOW the floor is
    // exactly the re-sign case, and a missing `meets_floor` parses as false, so
    // both stay on the queue.
    return (
      memberId: memberId,
      satisfied: <String>{
        for (final row in rows)
          if (row.signed && row.meetsFloor) row.waiverId,
      },
    );
  }

  /// The waivers [memberId] has already satisfied, as of the read fired at the
  /// plans step. Absence means ASK at every level — never "no need to sign":
  /// the endpoint returns `required ∪ ever-signed` where `required` comes from
  /// CURRENT memberships, so a waiver on the plan they are about to BUY is
  /// absent entirely. Only a positive `signed && meets_floor` from the server
  /// ever takes a signature off the queue.
  Set<String> _satisfiedWaiverIdsFor(String? memberId) => memberId == null
      ? const <String>{}
      : (_priorSatisfiedWaiverIds[memberId] ?? const <String>{});

  /// Drop [person]'s pick when the answer that just landed closed it — the
  /// answer can arrive after the member has already tapped, and a blocked plan
  /// that survives reaches the review and fails at pay.
  KioskSignupPerson _clearBlockedPick(KioskSignupPerson person) {
    final plan = state.planById(person.selectedPlanId);
    if (plan == null) return person;
    if (state.planBlockReasonFor(person, plan) == null) return person;
    return person.copyWith(selectedPlanId: null);
  }

  /// Pick a plan for the active person — ONE plan each, always `quantity: 1`.
  ///
  /// A plan closed to this person is never selected, only explained: the card
  /// stays tappable (a greyed-out plan with no explanation is a worse dead end)
  /// but the tap opens the popup instead of setting the pick, so a blocked plan
  /// can never reach the review and fail at pay.
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

  /// "Pick a membership" — dismiss and carry on with the grid behind it. The
  /// blocked plan was never selected; the clear below keeps that true if the
  /// tap path is ever refactored.
  void dismissPlanBlock() {
    _popupTimer?.cancel();
    emit(state.copyWith(planBlockActive: null, popupCountdown: 0));
    _updateActivePerson(_clearBlockedPick);
    registerActivity();
  }

  /// "Get help at the desk" from the plan block — the handoff the member
  /// CHOOSES. Nothing routes here on their behalf.
  void planBlockHelp() {
    final reason = state.planBlockActive;
    _popupTimer?.cancel();
    emit(state.copyWith(planBlockActive: null, popupCountdown: 0));
    _stop(switch (reason) {
      KioskPlanBlockReason.alreadyOnPlan => KioskSignupStopReason.alreadyOnPlan,
      // A tap with no reason on state cannot happen; the trial handoff is the
      // safe fallback because its copy claims the least.
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
  /// Group only: skipping the sole person of a solo signup would empty the
  /// cart, so the control is not offered there.
  ///
  /// It reuses [KioskSignupPerson.training] rather than a parallel "skipped"
  /// concept, so the roster check, the cart, the waiver queue and the review
  /// all follow for free. Skipping EVERYBODY returns to the People step, which
  /// already refuses to leave with an empty cart and says why.
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
  /// Ruling 9 — grouped by PERSON, not by document: every payee first (their
  /// payer-auth link, then their own liability waivers), the payer last, so the
  /// iPad changes hands once per person. Only the people the request will CARRY
  /// are walked, plus anyone a server gate named: asking somebody who Skipped
  /// to authorize a payer is a signature taken for nothing. The queue and
  /// [KioskSignupState.everyPayeeLinked] read the same
  /// [KioskSignupState.isBeingCharged] predicate, so they cannot disagree.
  void _enterWaiverRun() {
    final gated = <int>{
      for (final item in state.waiverGate)
        for (var i = 0; i < state.persons.length; i++)
          if (state.persons[i].memberId == item.memberId) i,
    };
    final queue = <int>[
      for (var i = 1; i < state.persons.length; i++)
        if (state.isBeingCharged(state.persons[i]) || gated.contains(i)) i,
      // The payer signs last, and only when they have something to sign.
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
  /// The queue holds only what this person will actually be asked to sign: a
  /// waiver the gym already holds a compliant signature for is DROPPED rather
  /// than stepped over, so "waiver 2 of 3" counts the signatures they are about
  /// to give. Two kinds of entry are never dropped — anything the SERVER named
  /// at a 422 gate (the backstop that makes a client-side skip safe at all),
  /// and anything [_satisfiedWaiverIdsFor] did not positively clear. Signed
  /// stays signed: Back then forward never re-asks.
  void _enterLiability(int personIndex) {
    final person = state.persons[personIndex];
    final planIds = state.planById(person.selectedPlanId)?.waiverIds ??
        const <String>[];
    // Anything the SERVER named for this person: authoritative (a plan whose
    // waiver list drifted from the gate would otherwise loop the member), and
    // the ONE thing the prior-signature skip may not remove.
    final gated = <String>{
      for (final item in state.waiverGate)
        if (item.memberId == person.memberId) item.waiverId,
    };
    final queue = waiverQueueFor(
      planWaiverIds: planIds,
      serverGatedWaiverIds: gated,
      satisfiedWaiverIds: _satisfiedWaiverIdsFor(person.memberId),
    );
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
  int? _firstUnsigned(String? memberId, List<String> queue) =>
      firstUnsignedIndex(
        queue,
        state.signedWaiverIdsFor(memberId).toSet(),
      );

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

  /// Read the gym's authorized-payer agreement for the active payee. A failure
  /// is an inline retry, not a stop, for the same reason a liability read is:
  /// member rows and Stripe customers already exist for the whole roster.
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

  /// "Sign and continue" — sign and link in ONE call
  /// (`PUT /members/{payee}/link`), which commits immediately with no group
  /// rollback. The signer is the PAYER every time: this is "I am authorised to
  /// pay for this person", not the payee's own liability waiver. A 409 means
  /// the gym republished the agreement between the read and this call, so the
  /// body reloads and the payer signs the new one.
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

  /// Read the current waiver's body. A failure is an inline retry, never a
  /// terminal stop: a member row and a Stripe customer already exist, so ending
  /// the signup over one flaky read would orphan them for nothing.
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
  /// to the next unsigned one (or to the card). A 409 means the gym republished
  /// the waiver in between; the version is pinned server-side, so the signature
  /// is refused and the body reloads — nothing is recorded against text they
  /// never saw.
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

  /// Route a server waiver gate (422) back into the run, carrying exactly the
  /// (member, waiver) pairs the backend named. The server is authoritative, so
  /// anything it lists as unsigned is dropped from this signup's own signed set
  /// — otherwise the run would skip the very waiver the backend blocks on and
  /// the member would loop.
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
  /// Tokenization happens in the widget, against Stripe, and never touches a
  /// repository — the kiosk holds only the `pm_…` id plus the brand and last
  /// four it renders back. Entering the review also mints the attempt's
  /// idempotency key, so a double-tap on Pay reuses one key rather than two.
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
  /// never committed. A failure, and equally a request that cannot be
  /// ASSEMBLED, gets a retryable stop: the review renders its spinner off
  /// `preview == null`, so returning without emitting would leave the step
  /// spinning forever with no way on. That stop belongs to the review step ONLY
  /// — a preview reloaded by [retrySameCard] rides alongside a live charge, and
  /// stopping there would yank the member off a landed receipt mid-charge.
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

  /// The ONE place a start request is assembled, for the preview and the real
  /// charge alike, so there is a single place to audit what the kiosk can send.
  /// Nothing that reduces a price is ever sent — this builder never names those
  /// fields. `paidWithCash` is pinned false (an unattended iPad cannot take
  /// cash) and the proration to `prorateToAnchor`, which is what makes the
  /// review's due-today sum correct.
  MemberMembershipsStartRequest? _buildStartRequest({
    required String idempotencyKey,
    MemberMembershipsStartPayment? payment,
  }) {
    // This reads the DESIGNATED payer, not merely index 0, so a demoted payee
    // sitting at the head can never be billed as the payer.
    final payer = state.payerOrNull;
    if (payer == null) return null;
    final payerId = payer.memberId;
    if (payerId == null) return null;
    // Link before start, structurally: the start call never links, so no
    // request assembles until every payee is authorized.
    if (!state.everyPayeeLinked) return null;
    // The envelope is the shared builder's (`start_request_builder.dart`),
    // which also owns the "no items, no request" rule — an empty retry set
    // sends nothing rather than re-posting the cart.
    return flow.buildStartRequest(
      payerMemberId: payerId,
      gymId: _gymId,
      idempotencyKey: idempotencyKey,
      prorationBehavior: ProrationBehavior.prorateToAnchor,
      paidWithCash: false,
      payment: payment,
      memberships: _startItems(),
    );
  }

  /// One item per person the next request must carry — every training person
  /// with a picked, priced plan on a first attempt, and after a landed start
  /// exactly the people whose membership was NOT created. Quantity is always 1.
  ///
  /// A retry never re-sends a `created` item, and an empty retry set sends
  /// NOTHING — both live in [KioskSignupState.isBeingCharged] over
  /// [KioskSignupState.retryMemberIds], whose null-vs-empty distinction is the
  /// double-charge defence: null is "nothing landed, send the cart", empty is
  /// "nothing left to send". Collapsing them re-sends the WHOLE cart for a
  /// `[created, unknown]` partial under a fresh key the backend's replay guard
  /// cannot dedupe — a second real charge on a membership already started.
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

  /// Fire the start call — the money moment, where every line is a defence.
  ///
  /// Two independent guards: the `paying` check is SYNCHRONOUS and its emit
  /// happens before any `await`, so a double-tap is exactly one charge; and the
  /// [_sentAttempts] latch means a key that has already gone out is never
  /// posted again, whatever happened to the response. The idle guard is
  /// suspended for the duration (this screen has no buttons to answer a
  /// countdown with) and re-armed on every outcome, and the session's flow
  /// count is deliberately NOT released here — a live charge is exactly the
  /// case the grace window exists for.
  Future<void> pay() async {
    if (state.step == KioskSignupStep.paying) return;
    final paymentMethodId = state.paymentMethodId;
    // Nothing to charge with is a handoff, never a silent return:
    // [retrySameCard] has already cancelled the popup's return countdown, so a
    // bare `return` parks a shared iPad on a popup with no clock and no way
    // home. There is ALWAYS a countdown home, and nothing was sent, so
    // "nothing was charged" is exactly true.
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
        // Always true, whatever the cart holds: the fresh card becomes the
        // payer's default, replacing whatever was on the profile — which is
        // what lets an existing member self-serve here. The card step says so.
        setDefault: true,
      ),
    );
    // Nothing to send — an unassemblable request, or a retry set with nothing
    // left in it. Same rule as the null card: a countdown home, not a dead
    // screen. Nothing left the device, so "nothing was charged" holds.
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
      // HTTP error, so the split is read off the ITEMS — and it is THREE-way.
      // Nothing to itemise → welcome (a receipt with no rows is worse); every
      // item refused → the decline popup, whose "you haven't been charged" is
      // true exactly there; anything else (all created, or a PARTIAL) → the
      // results receipt, because on a partial money HAS moved for the group
      // that cleared.
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
      // 409 = an idempotent replay: the ORIGINAL start stands, charge included,
      // so it is a SUCCESS from the member's side — never a second charge.
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
  /// A retry re-sends only the items the previous start did not create, so
  /// without the fold a partial then retried successfully would print a one-row
  /// receipt headed "every membership below started today" while omitting the
  /// one that landed first. The newer outcome always REPLACES the older for the
  /// same (member, plan), so [KioskSignupState.retryMemberIds] over the fold
  /// equals the latest response's un-created set and cannot grow stale.
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
  /// The flow count is released only when every item was created. On a PARTIAL
  /// it deliberately does not: Retry is live there, and [pay] would run a live
  /// charge with no flow held — the 60-second expiry's [abandon] releases it
  /// instead, exactly as the decline popup relies on. [_enterWelcome] keeps its
  /// own release ([_flowStarted] is a latch) for every other route in.
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

  /// "Next" — from the receipt to the welcome screen and its app push. Offered
  /// on BOTH branches, partial included (founder ruling): the people whose
  /// memberships DID start were standing there for the app push. Deliberately
  /// NOT gated on [KioskSignupState.allCreated] — advancing to a terminal
  /// screen charges nothing, so the money-safety gate lives on the retry
  /// ([KioskSignupState.canRetryStart]) instead.
  void nextFromResults() {
    registerActivity();
    if (state.step != KioskSignupStep.results) return;
    _popupTimer?.cancel();
    _enterWelcome(afterPartial: !state.allCreated);
  }

  // ── D8 · declined ──

  /// EVERY membership in the cart was refused. The member row, the Stripe
  /// customer and every signature are already committed and are NEVER
  /// re-executed — only the charge is retried, from the decline popup.
  /// All-failed only: the popup's "nothing was charged" is true exactly here; a
  /// PARTIAL goes to [_enterResults] instead, because there money HAS moved.
  ///
  /// A decline never ends the signup and no attempt is gated by a wait — the
  /// member may retry the same card or a fresh one as often as they like;
  /// attempt-velocity throttling rides on the platform Stripe Radar rule, not a
  /// client cooldown (founder decision). The popup's RETURN countdown decides
  /// only how long a shared iPad may sit unanswered; Retry is live at once.
  void _onDeclined(MemberMembershipsStartResponse result) {
    emit(state.copyWith(
      startResult: result,
      step: KioskSignupStep.declined,
      submitting: false,
    ));
    _syncIdleTimer();
    _startPopupCountdown();
  }

  /// The blocking surfaces' shared clock — a per-second countdown that abandons
  /// at zero (the decline popup, the plan block, the results receipt). Expiry
  /// runs the ordinary [abandon], which matters most on the decline and on a
  /// PARTIAL receipt: neither releases the flow count on entry, so if nobody
  /// answers, this is what releases it.
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

  /// "Retry" — re-attempt the SAME card, the insufficient-funds case: the
  /// member moves money, then retries the card they already entered.
  ///
  /// It keeps the card facts and mints a NEW idempotency key before re-firing
  /// [pay]. A new key is mandatory — reusing the already-sent one would replay
  /// the decline through the [_sentAttempts] latch instead of making a genuine
  /// attempt. Nothing else re-runs. The step guard admits only the two screens
  /// that offer a retry; widening it would let a stray key be minted from a
  /// step with no landed response behind it.
  void retrySameCard() {
    registerActivity();
    // A retry exists only where a landed start left something un-created. This
    // is the gate, not the step list: an ALL-CREATED receipt is `results` too,
    // and re-firing [pay] from there re-posts the WHOLE cart under a fresh key
    // the backend's replay guard cannot dedupe — a second real charge on
    // memberships that already started.
    if (!state.canRetryStart) return;
    if (state.step != KioskSignupStep.declined &&
        state.step != KioskSignupStep.results) {
      return;
    }
    _popupTimer?.cancel();
    emit(state.copyWith(
      idempotencyKey: newIdempotencyKey(),
      popupCountdown: 0,
      // The preview on state prices the WHOLE cart and this retry does not, and
      // the paying screen states that figure as what is being taken — keeping
      // it would watch a member through "$200.00" while $100 is charged. It is
      // re-priced below against the same filtered items the charge carries.
      preview: null,
    ));
    // The order is load-bearing: both requests are narrowed by
    // `state.startResult`, which [pay] clears the instant it emits `paying`, so
    // a preview fired afterwards would re-price the whole cart. `_loadPreview`
    // builds its request before its first await, so calling it first is enough.
    // A preview failure is silent here — Retry must never be gated on a read.
    unawaited(_loadPreview());
    unawaited(pay());
  }

  /// "Try another card" — back to the card step with a genuinely FRESH field.
  ///
  /// Unlike [retrySameCard] this CLEARS the card, and the key is dropped rather
  /// than reused ([submitCard] mints a fresh one on the way into the review).
  /// [KioskSignupState.cardAttempt] is bumped so the Stripe `CardField` is
  /// re-keyed and mounts an EMPTY iframe — its web platform view is cached
  /// across mounts, so without that the member would see the declined number
  /// and be unable to type a new one.
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

  /// "Get help at the desk" — the handoff the member CHOOSES, deliberately NOT
  /// an abandon: everything committed stays committed and the desk picks the
  /// thread up from the incomplete-signups list, rather than dropping the
  /// member at a clean home screen with a half-built account. Nothing ever
  /// routes here on their behalf.
  void getHelpAtDesk() => _stop(KioskSignupStopReason.cardDeclined);

  // ── Welcome ──

  /// The signup's terminal celebration. Its [_endFlowIfStarted] is a no-op
  /// after an all-created results screen ([_flowStarted] is a latch) but is the
  /// ONLY release for every other route here — the 409 replay, a start with
  /// nothing to itemise, and Next off a PARTIAL receipt.
  ///
  /// [afterPartial] is carried rather than derived because this method CLEARS
  /// [KioskSignupState.startResult] (nothing terminal may keep narrowing a
  /// future request), so the branch that routed here is the only thing that
  /// still knows. It decides only whether the screen states the handoff.
  void _enterWelcome({bool afterPartial = false}) {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _popupTimer?.cancel();
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
      welcomeAfterPartial: afterPartial,
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

  /// The group step's "someone who's already a member" read — the plain read
  /// underneath [searchExistingPeople], which owns the debounce and the
  /// sequence guard.
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
  /// A TERMINAL reason releases the session flow here; a RETRYABLE one
  /// deliberately does not — the member may still tap "Try again", and a
  /// released count during a live flow is the same bookkeeping bug as a leaked
  /// one. If they walk off, the auto-return's [abandon] releases it.
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

  /// Ask before abandoning — the "Start over?" confirmation, used only from the
  /// steps where real work dies (card / review); every earlier step abandons on
  /// the first tap, since a confirm there is a second trap for a member who
  /// already mis-tapped. The 5-minute clock keeps running behind it, so an
  /// unanswered dialog never pins half-typed card details on a lobby iPad.
  void askAbandon() {
    emit(state.copyWith(abandonConfirmActive: true));
  }

  /// "Keep going" — dismiss the confirmation. It counts as interaction, so the
  /// idle clock resets.
  void dismissAbandon() {
    emit(state.copyWith(abandonConfirmActive: false));
    registerActivity();
  }

  /// End the flow and send the surface home — the ONE exit, for the escape, the
  /// confirmed "Yes, start over", the idle timeout and both stop-screen exits.
  /// It does not navigate: `KioskSignupScreen` watches
  /// [KioskSignupState.abandoned] and calls `KioskFlowCubit.goHome()`, and
  /// unmounting the subtree closes this cubit, so every typed field dies.
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

  /// Any member interaction: dismiss the idle warning and reset the 5-minute
  /// clock. Wired to a pointer listener over the signup surface AND called by
  /// every interactive method here.
  void registerActivity() {
    if (state.idleWarningActive) {
      emit(state.copyWith(idleWarningActive: false, idleCountdown: 0));
    }
    _syncIdleTimer();
  }

  /// Stop the idle guard while a step owns the clock itself. [pay] calls this
  /// before the start request and [resumeIdle] on every outcome: a charge in
  /// flight must never be interrupted by a countdown the screen cannot answer.
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
    // The terminals run their own clocks (or none): the stop screen's 15s
    // auto-return, the receipt's and welcome's 60s ones, and payment, which
    // must never be interrupted.
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

  /// The signup's clock — read by the later steps' dates, and injected to keep
  /// the cubit deterministic under `fakeAsync`.
  DateTime get now => _now();

  /// A fresh idempotency key for a deliberate start attempt. One is minted on
  /// the way into the review, so a double-tap on Pay reuses the key on
  /// [KioskSignupState.idempotencyKey]; a retry after a decline mints a new
  /// one.
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
    // incremented and the kiosk never signs itself out at its lockout. The
    // latch makes the pair exactly-once however this cubit was reached.
    _endFlowIfStarted();
    return super.close();
  }
}
