import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
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
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_created_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_failure_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_load_detail_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/duplicate_footer.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/duplicate_member_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/member_create_form.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step_label.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_wizard.dart';
import 'package:crm/features/member_details/presentation/screens/member_detail_screen.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

enum _Phase { create, duplicate, created, failure, loadDetail, wizard }

/// The full add-member-and-membership flow, hosted in one dialog route: create
/// the member (with duplicate handling), confirm, then load the new member and
/// hand off to the start-memberships wizard. A member with no membership is a
/// fine terminal state — the wizard is optional.
class AddMemberFlow extends StatefulWidget {
  /// The section (nested workspace) navigator that owns member-detail routes,
  /// captured at launch so "View member" pushes there (the dialog itself lives
  /// on the root navigator). Mirrors how the members table row navigates.
  final NavigatorState sectionNavigator;

  const AddMemberFlow({super.key, required this.sectionNavigator});

  static Future<void> show(BuildContext context) {
    final sectionNavigator = Navigator.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddMemberFlow(sectionNavigator: sectionNavigator),
    );
  }

  @override
  State<AddMemberFlow> createState() => _AddMemberFlowState();
}

class _AddMemberFlowState extends State<AddMemberFlow> {
  late final MemberCreateBloc _createBloc;
  final _formKey = GlobalKey<MemberCreateFormState>();

  _Phase _phase = _Phase.create;

  // Duplicate step.
  List<DuplicateMemberMatch> _matches = const [];
  String? _selectedMatchId;

  // Whether the create step confirmed an existing duplicate rather than
  // creating a new member (changes the confirmation wording; a frozen block
  // is only reachable this way).
  bool _wasExisting = false;
  MembersManagementCreateRequest? _pendingRequest;

  // Confirmation identity + the created member id.
  String? _createdMemberId;
  String _createdName = '';
  String? _createdEmail;
  String? _createdPhoto;

  // Failure step.
  String _failureMessage = '';
  bool _failureNeedsStripe = false;

  // Load-detail step.
  MemberDetailBloc? _detailBloc;
  AddMemberLoadState _loadState = AddMemberLoadState.loading;
  MemberDetailResponse? _loadedMember;

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

  // ----- Create step -----

  void _onCreate() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final req = form.buildRequest(_gymId);
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

  void _onBackToEdit() {
    _createBloc.add(const MemberCreateReset());
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
        _captureIdentity(state.memberId);
        setState(() {
          _createdMemberId = state.memberId;
          _phase = _Phase.created;
        });
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

  void _captureIdentity(String memberId) {
    if (_wasExisting) {
      final m = _matches.firstWhere((e) => e.memberId == memberId);
      _createdName = m.fullName;
      _createdEmail = m.email;
      _createdPhoto = m.photoUrl;
    } else {
      final r = _pendingRequest;
      _createdName = r == null ? '' : '${r.firstName} ${r.lastName}';
      _createdEmail = r?.email;
      _createdPhoto = r?.photoUrl;
    }
  }

  // ----- Continue → load detail -----

  void _onContinue() {
    final id = _createdMemberId;
    if (id == null) return;
    _detailBloc = MemberDetailBloc(
      repository: MemberRepository(apiClient: ApiClient()),
      scheduleRepository: ScheduleRepository(apiClient: ApiClient()),
      ranksRepository: RanksRepository(apiClient: ApiClient()),
      rewardsRepository: RewardsRepository(apiClient: ApiClient()),
    )..add(MemberDetailRequested(id, gymId: _gymId));
    setState(() {
      _loadState = AddMemberLoadState.loading;
      _phase = _Phase.loadDetail;
    });
  }

  void _retryLoad() {
    final id = _createdMemberId;
    if (id == null) return;
    setState(() => _loadState = AddMemberLoadState.loading);
    _detailBloc?.add(MemberDetailRequested(id, gymId: _gymId));
  }

  void _onDetailState(MemberDetailState state) {
    if (_phase != _Phase.loadDetail) return;
    if (state is MemberDetailLoaded) {
      final frozen = state.member.memberships
          .any((m) => m.status == MembershipStatus.frozen);
      if (frozen) {
        setState(() {
          _loadedMember = state.member;
          _loadState = AddMemberLoadState.frozen;
        });
      } else {
        setState(() {
          _loadedMember = state.member;
          _phase = _Phase.wizard;
        });
      }
    } else if (state is MemberDetailError) {
      setState(() => _loadState = AddMemberLoadState.error);
    }
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

  void _viewCreated() {
    final id = _createdMemberId;
    Navigator.of(context).pop();
    if (id != null) _pushMember(id);
  }

  // ----- Build -----

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.wizard) {
      return BlocProvider.value(
        value: _detailBloc!,
        child: StartMembershipsWizard(
          member: _loadedMember!,
          showAddMemberGroup: true,
          // The wizard pops the dialog itself before this fires.
          onViewMember: _pushMember,
        ),
      );
    }
    if (_phase == _Phase.loadDetail) {
      return BlocProvider.value(
        value: _detailBloc!,
        child: BlocListener<MemberDetailBloc, MemberDetailState>(
          listenWhen: (_, curr) =>
              curr is MemberDetailLoaded || curr is MemberDetailError,
          listener: (_, state) => _onDetailState(state),
          child: AddMemberChrome(
            stepName: 'Setting up membership…',
            body: AddMemberLoadDetailView(state: _loadState),
            footer: _loadDetailFooter(),
          ),
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
              stepName: _stepName,
              body: _createBlocBody(),
              footer: _createBlocFooter(context, creating),
            );
          },
        ),
      ),
    );
  }

  String get _stepName {
    final m = addMemberFlowStepCount(memberCount: 1, hasWaiver: false);
    switch (_phase) {
      case _Phase.duplicate:
        return 'Possible duplicate · Step 1 of $m';
      case _Phase.created:
        return 'Member added · Step 1 of $m';
      case _Phase.create:
      case _Phase.failure:
      case _Phase.loadDetail:
      case _Phase.wizard:
        return 'Create the member · Step 1 of $m';
    }
  }

  Widget _createBlocBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kept mounted so the entered values survive a "back to edit"
        // round-trip from the duplicate / failure steps.
        Offstage(
          offstage: _phase != _Phase.create,
          child: MemberCreateForm(key: _formKey),
        ),
        if (_phase == _Phase.duplicate)
          DuplicateMemberPanel(
            matches: _matches,
            selectedMatchId: _selectedMatchId ?? '',
            onSelect: (id) => setState(() => _selectedMatchId = id),
          ),
        if (_phase == _Phase.created)
          AddMemberCreatedView(
            name: _createdName,
            email: _createdEmail,
            photoUrl: _createdPhoto,
            wasExisting: _wasExisting,
          ),
        if (_phase == _Phase.failure)
          AddMemberFailureView(
            message: _failureMessage,
            needsStripeSetup: _failureNeedsStripe,
          ),
      ],
    );
  }

  Widget _createBlocFooter(BuildContext context, bool creating) {
    switch (_phase) {
      case _Phase.create:
        return AppDialogActions(
          primaryLabel: 'Create member',
          isLoading: creating,
          primaryOnPressed: creating ? null : _onCreate,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _Phase.duplicate:
        return DuplicateFooter(
          busy: creating,
          onBackToEdit: _onBackToEdit,
          onCreateAnyway: _onCreateAnyway,
          onUseExisting: _onUseExisting,
        );
      case _Phase.created:
        return AppDialogActions(
          primaryLabel: 'Continue to memberships',
          primaryOnPressed: _onContinue,
          secondaryLabel: 'Done',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _Phase.failure:
        return AppDialogActions(
          primaryLabel: 'Back to edit',
          primaryOnPressed: _onBackToEdit,
          secondaryLabel: 'Close',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _Phase.loadDetail:
      case _Phase.wizard:
        return const SizedBox.shrink();
    }
  }

  Widget _loadDetailFooter() {
    switch (_loadState) {
      case AddMemberLoadState.loading:
        return AppDialogActions(
          primaryLabel: 'Continue',
          primaryOnPressed: null,
          secondaryLabel: 'Done',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case AddMemberLoadState.error:
        return AppDialogActions(
          primaryLabel: 'Retry',
          primaryOnPressed: _retryLoad,
          secondaryLabel: 'View member',
          secondaryOnPressed: _viewCreated,
        );
      case AddMemberLoadState.frozen:
        return AppDialogActions(
          primaryLabel: 'View member',
          primaryOnPressed: _viewCreated,
          secondaryLabel: 'Done',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}
