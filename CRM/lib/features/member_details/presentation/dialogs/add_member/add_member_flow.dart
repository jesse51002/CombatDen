import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/emails/data/models/invite_outcome.dart';
import 'package:crm/features/emails/data/repositories/emails_repository.dart';
import 'package:crm/features/member_details/bloc/member_create_bloc.dart';
import 'package:crm/features/member_details/bloc/member_create_event.dart';
import 'package:crm/features/member_details/bloc/member_create_state.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_chrome.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_failure_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_load_detail_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_outcome.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_roster_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/authorize_payer_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/choose_payer_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/duplicate_footer.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/duplicate_member_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/group_member.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/member_create_form.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_wizard.dart';
import 'package:crm/features/member_details/presentation/screens/member_detail_screen.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_dialog/create_invite_actions.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';

enum _Phase {
  create,
  duplicate,
  roster,
  failure,
  choosePayer,
  authorize,
  loadDetail,
  wizard,
}

/// The full add-member-and-membership flow, hosted in one dialog route. Create
/// one or more people (with duplicate handling); the roster is the create-phase
/// hub. A single person continues straight to the start-memberships wizard; a
/// group first chooses one payer, who signs an authorization for each of the
/// others, before the wizard runs for the whole group. A member with no
/// membership is a fine terminal state.
class AddMemberFlow extends StatefulWidget {
  /// The section (nested workspace) navigator that owns member-detail routes,
  /// captured at launch so "View member" pushes there (the dialog itself lives
  /// on the root navigator). Mirrors how the members table row navigates.
  final NavigatorState sectionNavigator;

  /// Pushed the running outcome on every group / navigation change, so
  /// [show] can return it even when the embedded wizard (not the flow) pops
  /// the dialog route.
  final ValueChanged<AddMemberOutcome> onOutcomeChanged;

  const AddMemberFlow({
    super.key,
    required this.sectionNavigator,
    required this.onOutcomeChanged,
  });

  static Future<AddMemberOutcome> show(BuildContext context) async {
    final sectionNavigator = Navigator.of(context);
    var outcome = AddMemberOutcome.empty;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddMemberFlow(
        sectionNavigator: sectionNavigator,
        onOutcomeChanged: (o) => outcome = o,
      ),
    );
    return outcome;
  }

  @override
  State<AddMemberFlow> createState() => _AddMemberFlowState();
}

class _AddMemberFlowState extends State<AddMemberFlow> {
  late final MemberCreateBloc _createBloc;
  final _formKey = GlobalKey<MemberCreateFormState>();
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  _Phase _phase = _Phase.create;

  // The group being assembled — append-only, no per-row removal.
  final List<GroupMember> _group = [];

  // Create step — whether the form currently holds an email, which decides
  // whether the footer asks the invite question at all.
  bool _hasEmail = false;

  // Duplicate step.
  List<DuplicateMemberMatch> _matches = const [];
  String? _selectedMatchId;

  // Create bookkeeping — whether the last resolution was an existing duplicate,
  // and the pending request (used to build the appended group member).
  bool _wasExisting = false;
  MembersManagementCreateRequest? _pendingRequest;

  // Failure step.
  String _failureMessage = '';
  bool _failureNeedsStripe = false;

  // Choose-payer step.
  String? _payerId;

  // Authorize step.
  List<GroupMember> _payees = const [];
  int _authorizeIndex = 0;
  Set<String> _committedPayeeIds = {};
  bool _payerLoaded = false;
  bool _payerLoadError = false;
  String _waiverBody = '';
  String? _waiverVersionId;
  bool _fetchingWaiver = false;
  String? _waiverError;
  String _signerName = '';
  bool _consent = false;
  bool _submitting = false;
  int _tokenBefore = 0;
  String? _commitError;

  // Load-detail step (single path + the group's frozen-payer block).
  MemberDetailBloc? _detailBloc;
  AddMemberLoadState _loadState = AddMemberLoadState.loading;
  MemberDetailResponse? _loadedMember;
  String? _loadDetailMemberId;

  // Wizard.
  Set<String>? _wizardInitialSelection;

  // Outcome.
  bool _navigatedToMember = false;

  String get _gymId => selectedGym.gymId ?? '';

  @override
  void initState() {
    super.initState();
    _createBloc = MemberCreateBloc(
      repository: MemberRepository(apiClient: ApiClient()),
    );
  }

  @override
  void dispose() {
    _createBloc.close();
    // Closing the detail bloc cancels its InvoicePoller (MemberDetailBloc
    // .close → _poller.cancel), so no timer outlives the dialog.
    _detailBloc?.close();
    super.dispose();
  }

  // ----- Outcome + close -----

  void _updateOutcome() {
    widget.onOutcomeChanged(AddMemberOutcome(
      createdCount: _group.length,
      navigatedToMember: _navigatedToMember,
    ));
  }

  void _close() {
    _updateOutcome();
    Navigator.of(context).pop();
  }

  // ----- Create step -----

  void _onCreate({required bool sendInvite}) {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final req = form.buildRequest(_gymId, sendInvite: sendInvite);
    _pendingRequest = req;
    _wasExisting = false;
    _createBloc.add(MemberCreateSubmitted(req));
  }

  void _onCreateAnyway() {
    _wasExisting = false;
    _createBloc.add(const MemberCreateAnywayRequested());
  }

  void _onUseExisting() {
    _wasExisting = true;
    final matchId = _selectedMatchId;
    if (matchId == null) return;
    _createBloc.add(MemberCreateUseExisting(matchId));
  }

  /// Back to edit from the duplicate / failure steps — preserves the entered
  /// values (the form stays mounted).
  void _onBackToEdit() {
    _createBloc.add(const MemberCreateReset());
    setState(() => _phase = _Phase.create);
  }

  /// "Add another person" from the roster — a fresh person, so the form is
  /// cleared (unlike "back to edit").
  void _onAddAnother() {
    _createBloc.add(const MemberCreateReset());
    _formKey.currentState?.clear();
    _wasExisting = false;
    _pendingRequest = null;
    _matches = const [];
    _selectedMatchId = null;
    setState(() => _phase = _Phase.create);
  }

  void _onCreateState(MemberCreateState state) {
    switch (state) {
      case MemberCreateDuplicate():
        setState(() {
          _matches = state.matches;
          _selectedMatchId = state.matches.isNotEmpty
              ? state.matches.first.memberId
              : null;
          _phase = _Phase.duplicate;
        });
      case MemberCreated():
        _resolveMember(state.memberId, state.invite);
      case MemberCreateFailure():
        setState(() {
          _failureMessage = state.message;
          _failureNeedsStripe = state.needsStripeSetup;
          _phase = _Phase.failure;
        });
      case MemberCreateIdle():
      case MemberCreateSubmitting():
        break;
    }
  }

  /// Append the resolved member to the group (skipping an exact duplicate id —
  /// a re-picked existing member) and return to the roster hub.
  void _resolveMember(String memberId, InviteOutcome invite) {
    if (!_group.any((g) => g.memberId == memberId)) {
      _group.add(_buildGroupMember(memberId, invite));
      _updateOutcome();
    }
    setState(() => _phase = _Phase.roster);
  }

  GroupMember _buildGroupMember(String memberId, InviteOutcome invite) {
    if (_wasExisting) {
      final m = _matches.firstWhere((e) => e.memberId == memberId);
      return GroupMember(
        memberId: memberId,
        fullName: m.fullName,
        email: m.email,
        photoUrl: m.photoUrl,
        wasExisting: true,
        invite: invite,
      );
    }
    final r = _pendingRequest;
    return GroupMember(
      memberId: memberId,
      fullName: r == null ? '' : '${r.firstName} ${r.lastName}',
      email: r?.email,
      photoUrl: r?.photoUrl,
      wasExisting: false,
      invite: invite,
    );
  }

  // ----- Roster footer actions -----

  Future<void> _onDoneNotLinked() async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Leave without linking?',
      message: 'You added ${_group.length} people but haven\'t chosen '
          "who pays. They'll be saved as members with no payer and no "
          'membership. You can link them from any member\'s profile later.',
      confirmLabel: 'Leave unlinked',
    );
    if (!mounted || !confirmed) return;
    _close();
  }

  // ----- Single-person path: continue → load detail -----

  void _onContinue() {
    final id = _group.isNotEmpty ? _group.first.memberId : null;
    if (id == null) return;
    _detailBloc?.close();
    _loadDetailMemberId = id;
    _wizardInitialSelection = null; // single path uses the wizard's default
    _detailBloc = _buildDetailBloc(id);
    setState(() {
      _loadState = AddMemberLoadState.loading;
      _phase = _Phase.loadDetail;
    });
  }

  MemberDetailBloc _buildDetailBloc(String memberId) {
    return MemberDetailBloc(
      repository: MemberRepository(apiClient: ApiClient()),
      scheduleRepository: ScheduleRepository(apiClient: ApiClient()),
      ranksRepository: RanksRepository(apiClient: ApiClient()),
      rewardsRepository: RewardsRepository(apiClient: ApiClient()),
      emailsRepository: EmailsRepository(apiClient: ApiClient()),
    )..add(MemberDetailRequested(memberId, gymId: _gymId));
  }

  void _retryLoad() {
    final id = _loadDetailMemberId;
    if (id == null) return;
    setState(() => _loadState = AddMemberLoadState.loading);
    _detailBloc?.add(MemberDetailRequested(id, gymId: _gymId));
  }

  void _onDetailState(MemberDetailState state) {
    if (_phase != _Phase.loadDetail) return;
    if (state is MemberDetailLoaded) {
      final frozen = state.member.memberships
          .any((m) => m.status == MembershipStatus.frozen);
      setState(() {
        _loadedMember = state.member;
        if (frozen) {
          _loadState = AddMemberLoadState.frozen;
        } else {
          _phase = _Phase.wizard;
        }
      });
    } else if (state is MemberDetailError) {
      setState(() => _loadState = AddMemberLoadState.error);
    }
  }

  // ----- Group path: choose payer → authorize -----

  String get _payerName {
    final id = _payerId;
    if (id == null) return '';
    final m = _group.where((g) => g.memberId == id);
    return m.isEmpty ? '' : m.first.fullName;
  }

  bool get _isLastPayee => _authorizeIndex + 1 >= _payees.length;

  bool get _canAuthorize =>
      _consent &&
      _signerName.isNotEmpty &&
      _waiverVersionId != null &&
      !_submitting;

  void _onAuthorizeStart() {
    final payerId = _payerId;
    if (payerId == null) return;
    _detailBloc?.close();
    _payees = _group.where((g) => g.memberId != payerId).toList();
    _authorizeIndex = 0;
    _committedPayeeIds = {};
    _payerLoaded = false;
    _payerLoadError = false;
    _submitting = false;
    _commitError = null;
    _fetchingWaiver = false;
    _waiverError = null;
    _waiverVersionId = null;
    _waiverBody = '';
    _signerName = '';
    _consent = false;
    _detailBloc = _buildDetailBloc(payerId);
    setState(() => _phase = _Phase.authorize);
  }

  void _onAuthorizeDetailState(MemberDetailState state) {
    if (_phase != _Phase.authorize) return;
    if (state is MemberDetailError) {
      if (!_payerLoaded) setState(() => _payerLoadError = true);
      return;
    }
    if (state is! MemberDetailLoaded) return;
    if (!_payerLoaded) {
      setState(() {
        _payerLoaded = true;
        _payerLoadError = false;
      });
      _fetchWaiverForCurrentPayee();
      return;
    }
    if (!_submitting) return;
    if (state.refreshToken > _tokenBefore && !state.isMutating) {
      _onCommitSuccess(state);
    } else if (state.actionError != null) {
      setState(() {
        _submitting = false;
        _commitError = state.actionError;
      });
    }
  }

  void _retryPayerLoad() {
    final payerId = _payerId;
    if (payerId == null) return;
    setState(() => _payerLoadError = false);
    _detailBloc?.add(MemberDetailRequested(payerId, gymId: _gymId));
  }

  Future<void> _fetchWaiverForCurrentPayee() async {
    final payee = _payees[_authorizeIndex];
    setState(() {
      _fetchingWaiver = true;
      _waiverError = null;
      _waiverVersionId = null;
      _waiverBody = '';
      _signerName = '';
      _consent = false;
      _commitError = null;
    });
    try {
      final waiver =
          await _repository.getAuthorizedPayerWaiver(payee.memberId);
      if (!mounted) return;
      setState(() {
        _fetchingWaiver = false;
        _waiverVersionId = waiver.versionId;
        _waiverBody = waiver.body;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetchingWaiver = false;
        _waiverError = "We couldn't load the waiver. Please try again.";
      });
    }
  }

  void _confirmAuthorize() {
    final bloc = _detailBloc;
    final payerId = _payerId;
    final versionId = _waiverVersionId;
    if (bloc == null || payerId == null || versionId == null) return;
    if (!_canAuthorize) return;
    final payee = _payees[_authorizeIndex];
    final s = bloc.state;
    if (s is MemberDetailLoaded) _tokenBefore = s.refreshToken;
    setState(() {
      _submitting = true;
      _commitError = null;
    });
    bloc.add(LinkParentRequested(
      memberId: payee.memberId,
      payerMemberId: payerId,
      waiverVersionId: versionId,
      signerName: _signerName,
      consentAcknowledged: true,
    ));
  }

  void _onCommitSuccess(MemberDetailLoaded state) {
    final payee = _payees[_authorizeIndex];
    _committedPayeeIds.add(payee.memberId);
    if (!_isLastPayee) {
      setState(() {
        _submitting = false;
        _authorizeIndex++;
      });
      _fetchWaiverForCurrentPayee();
      return;
    }
    // Last commit — the bloc already holds the payer's fresh detail (every
    // payee now authorized), so the wizard needs no extra load round-trip.
    final payerId = _payerId!;
    final frozen = state.member.memberships
        .any((m) => m.status == MembershipStatus.frozen);
    setState(() {
      _submitting = false;
      _loadedMember = state.member;
      if (frozen) {
        _loadDetailMemberId = payerId;
        _loadState = AddMemberLoadState.frozen;
        _phase = _Phase.loadDetail;
      } else {
        _wizardInitialSelection =
            _group.map((g) => g.memberId).toSet();
        _phase = _Phase.wizard;
      }
    });
  }

  // ----- View member -----

  void _pushMember(String memberId) {
    widget.sectionNavigator.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: AppRoutes.memberDetailPath(memberId),
        ),
        builder: (_) => MemberDetailScreen(
          memberId: memberId,
          gymId: _gymId,
        ),
      ),
    );
  }

  void _viewLoadedMember() {
    final id = _loadDetailMemberId;
    if (id == null) {
      _close();
      return;
    }
    _navigatedToMember = true;
    _close();
    _pushMember(id);
  }

  // ----- Build -----

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.wizard) {
      return BlocProvider.value(
        value: _detailBloc!,
        child: StartMembershipsWizard(
          member: _loadedMember!,
          initialSelectedMemberIds: _wizardInitialSelection,
          showAddMemberGroup: true,
          // The wizard pops the dialog itself before this fires.
          onViewMember: (id) {
            _navigatedToMember = true;
            _updateOutcome();
            _pushMember(id);
          },
        ),
      );
    }
    return BlocProvider.value(
      value: _createBloc,
      child: BlocListener<MemberCreateBloc, MemberCreateState>(
        listener: (_, state) => _onCreateState(state),
        child: BlocBuilder<MemberCreateBloc, MemberCreateState>(
          builder: (context, createState) {
            final creating = createState is MemberCreateSubmitting;
            return AddMemberChrome(
              stepName: _phaseStepName,
              body: _chromeBody(),
              footer: _chromeFooter(creating),
            );
          },
        ),
      ),
    );
  }

  String get _phaseStepName {
    switch (_phase) {
      case _Phase.create:
        return _group.isEmpty
            ? 'Add the first person'
            : 'Add another person';
      case _Phase.duplicate:
        return 'Possible duplicate';
      case _Phase.roster:
        return _group.length >= 2 ? 'Your group so far' : 'Member added';
      case _Phase.failure:
        return "Couldn't add this member";
      case _Phase.choosePayer:
        return 'Choose who pays';
      case _Phase.authorize:
        final payee = _payees.isNotEmpty && _authorizeIndex < _payees.length
            ? _payees[_authorizeIndex].fullName
            : '';
        return 'Authorize paying for $payee · '
            '${_authorizeIndex + 1} of ${_payees.length}';
      case _Phase.loadDetail:
        return 'Setting up membership…';
      case _Phase.wizard:
        return '';
    }
  }

  Widget _chromeBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kept mounted so entered values survive a "back to edit" round-trip;
        // "Add another person" clears it explicitly for a fresh person.
        Offstage(
          offstage: _phase != _Phase.create,
          child: MemberCreateForm(
            key: _formKey,
            onEmailPresenceChanged: (has) =>
                setState(() => _hasEmail = has),
          ),
        ),
        _phaseContent(),
      ],
    );
  }

  Widget _phaseContent() {
    switch (_phase) {
      case _Phase.create:
        return const SizedBox.shrink();
      case _Phase.duplicate:
        return DuplicateMemberPanel(
          matches: _matches,
          selectedMatchId: _selectedMatchId ?? '',
          onSelect: (id) => setState(() => _selectedMatchId = id),
        );
      case _Phase.failure:
        return AddMemberFailureView(
          message: _failureMessage,
          needsStripeSetup: _failureNeedsStripe,
        );
      case _Phase.roster:
        return AddMemberRosterView(
          group: _group,
          onAddAnother: _onAddAnother,
        );
      case _Phase.choosePayer:
        return ChoosePayerView(
          group: _group,
          selectedPayerId: _payerId,
          onSelect: (id) => setState(() => _payerId = id),
        );
      case _Phase.authorize:
        return _authorizeBody();
      case _Phase.loadDetail:
        return _loadDetailBody();
      case _Phase.wizard:
        return const SizedBox.shrink();
    }
  }

  Widget _authorizeBody() {
    return BlocProvider.value(
      value: _detailBloc!,
      child: BlocListener<MemberDetailBloc, MemberDetailState>(
        listenWhen: (_, curr) =>
            curr is MemberDetailLoaded || curr is MemberDetailError,
        listener: (_, state) => _onAuthorizeDetailState(state),
        child: _authorizePane(),
      ),
    );
  }

  Widget _authorizePane() {
    if (!_payerLoaded) {
      if (_payerLoadError) return _PayerLoadError(onRetry: _retryPayerLoad);
      return const SizedBox(
        height: DesignConstants.dialogProcessingHeight,
        child: Center(child: AppSpinner()),
      );
    }
    final payee = _payees[_authorizeIndex];
    return AuthorizePayerView(
      payees: _payees,
      committedIds: _committedPayeeIds,
      currentIndex: _authorizeIndex,
      payerName: _payerName,
      payeeName: payee.fullName,
      gymName: selectedGym.gymName ?? '',
      fetchingWaiver: _fetchingWaiver,
      waiverError: _waiverError,
      waiverBody: _waiverBody,
      submitting: _submitting,
      commitError: _commitError,
      onWaiverRetry: _fetchWaiverForCurrentPayee,
      onCommitRetry: _confirmAuthorize,
      onSignChanged: (name, consent) => setState(() {
        _signerName = name;
        _consent = consent;
      }),
    );
  }

  Widget _loadDetailBody() {
    return BlocProvider.value(
      value: _detailBloc!,
      child: BlocListener<MemberDetailBloc, MemberDetailState>(
        listenWhen: (_, curr) =>
            curr is MemberDetailLoaded || curr is MemberDetailError,
        listener: (_, state) => _onDetailState(state),
        child: AddMemberLoadDetailView(state: _loadState),
      ),
    );
  }

  Widget _chromeFooter(bool creating) {
    switch (_phase) {
      case _Phase.create:
        return CreateInviteActions(
          createLabel: 'Create',
          canInvite: _hasEmail,
          busy: creating,
          onCreate: (sendInvite) => _onCreate(sendInvite: sendInvite),
          onCancel: _close,
        );
      case _Phase.duplicate:
        return DuplicateFooter(
          busy: creating,
          onBackToEdit: _onBackToEdit,
          onCreateAnyway: _onCreateAnyway,
          onUseExisting: _onUseExisting,
        );
      case _Phase.failure:
        return AppDialogActions(
          primaryLabel: 'Back to edit',
          primaryOnPressed: _onBackToEdit,
          secondaryLabel: 'Close',
          secondaryOnPressed: _close,
        );
      case _Phase.roster:
        return _rosterFooter();
      case _Phase.choosePayer:
        return AppDialogActions(
          primaryLabel: 'Authorize & continue',
          primaryOnPressed: _payerId == null ? null : _onAuthorizeStart,
          secondaryLabel: 'Back',
          secondaryOnPressed: () =>
              setState(() => _phase = _Phase.roster),
        );
      case _Phase.authorize:
        return _authorizeFooter();
      case _Phase.loadDetail:
        return _loadDetailFooter();
      case _Phase.wizard:
        return const SizedBox.shrink();
    }
  }

  Widget _rosterFooter() {
    if (_group.length >= 2) {
      return AppDialogActions(
        primaryLabel: 'Choose who pays',
        primaryOnPressed: () =>
            setState(() => _phase = _Phase.choosePayer),
        secondaryLabel: 'Done, not linked yet',
        secondaryOnPressed: _onDoneNotLinked,
      );
    }
    return AppDialogActions(
      primaryLabel: 'Continue to memberships',
      primaryOnPressed: _onContinue,
      secondaryLabel: 'Done',
      secondaryOnPressed: _close,
    );
  }

  Widget _authorizeFooter() {
    return AppDialogActions(
      primaryLabel:
          _isLastPayee ? 'Authorize & finish' : 'Authorize & next',
      isLoading: _submitting,
      primaryOnPressed: _canAuthorize ? _confirmAuthorize : null,
      secondaryLabel: _committedPayeeIds.isEmpty ? 'Back' : 'Finish later',
      secondaryOnPressed: _submitting
          ? null
          : (_committedPayeeIds.isEmpty
              ? () => setState(() => _phase = _Phase.choosePayer)
              : _close),
    );
  }

  Widget _loadDetailFooter() {
    switch (_loadState) {
      case AddMemberLoadState.loading:
        return AppDialogActions(
          primaryLabel: 'Continue',
          primaryOnPressed: null,
          secondaryLabel: 'Done',
          secondaryOnPressed: _close,
        );
      case AddMemberLoadState.error:
        return AppDialogActions(
          primaryLabel: 'Retry',
          primaryOnPressed: _retryLoad,
          secondaryLabel: 'View member',
          secondaryOnPressed: _viewLoadedMember,
        );
      case AddMemberLoadState.frozen:
        return AppDialogActions(
          primaryLabel: 'View member',
          primaryOnPressed: _viewLoadedMember,
          secondaryLabel: 'Done',
          secondaryOnPressed: _close,
        );
    }
  }
}

/// The retryable failure panel for the authorize step's initial payer load
/// (the member is already saved, so this never strands the user).
class _PayerLoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const _PayerLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.error_sharp,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.badRed,
        ),
        Text("We couldn't load this member", style: DesignConstants.h2),
        Text(
          'They were saved. Retry to continue authorizing a payer for '
          'the group.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        AppOutlineButton(
          text: 'Retry',
          onPressed: onRetry,
          borderRadius: DesignConstants.radiusSmall,
        ),
      ],
    );
  }
}
