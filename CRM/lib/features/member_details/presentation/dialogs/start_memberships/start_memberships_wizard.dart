import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_dialog_routes.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_step_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_topbar.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// The staff start-memberships run: `who → plans (×N) → [waivers] → review &
/// charges → payment → results`.
///
/// A thin HOST. Everything the run knows lives in [MembershipWizardCubit];
/// everything it renders is composed from `features/membership_flow/`, at the
/// desk's own scale and in the desk's own voice — both mounted exactly once,
/// here, above the step switcher. What is left is the three things only a host
/// can own: the dialog it lives in, the nested staff dialogs that open over it
/// ([WizardDialogRoutes]), and telling the page behind that the run landed.
///
/// It calls its repositories directly rather than dispatching through
/// `MemberDetailBloc`, exactly as the kiosk does: a purchase is a
/// self-contained transaction with its own idempotency key, retry scope and
/// double-send latch, and routing it through the page's bloc puts all three
/// somewhere a second screen can reach them.
class StartMembershipsWizard extends StatefulWidget {
  final MemberDetailResponse member;

  /// Navigates to another member's detail page — the results receipt's
  /// per-row jump.
  final ValueChanged<String>? onViewMember;

  /// Prepends the always-done `Member added` rung to the rail. True only when
  /// the run is the tail of the add-member flow (the create already happened).
  final bool showAddMemberGroup;

  /// Who starts ticked. The add-member group flow passes the whole group so
  /// everybody the payer just authorized is pre-checked; a detail-page launch
  /// leaves it null and only the viewed member is ticked.
  final Set<String>? initialSelectedMemberIds;

  const StartMembershipsWizard({
    super.key,
    required this.member,
    this.onViewMember,
    this.showAddMemberGroup = false,
    this.initialSelectedMemberIds,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    ValueChanged<String>? onViewMember,
    bool showAddMemberGroup = false,
    Set<String>? initialSelectedMemberIds,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: StartMembershipsWizard(
          member: member,
          onViewMember: onViewMember,
          showAddMemberGroup: showAddMemberGroup,
          initialSelectedMemberIds: initialSelectedMemberIds,
        ),
      ),
    );
  }

  @override
  State<StartMembershipsWizard> createState() =>
      _StartMembershipsWizardState();
}

class _StartMembershipsWizardState extends State<StartMembershipsWizard> {
  late final MemberDetailBloc _detailBloc;
  late final MembershipWizardCubit _cubit;
  late final WizardDialogRoutes _routes;

  /// Whether the landed run has already been announced to the page behind, so
  /// a rebuild cannot re-dispatch the refresh.
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    _detailBloc = context.read<MemberDetailBloc>();
    // Any previous run's breakdown is cleared on open. The run itself no
    // longer rides this channel, but the channel is still live for the page
    // behind, and a stale receipt outliving its wizard is what this prevents.
    _detailBloc.add(const StartMembershipsCleared());
    final apiClient = ApiClient();
    _cubit = MembershipWizardCubit(
      memberRepository: MemberRepository(apiClient: apiClient),
      membershipsRepository: MembershipsRepository(apiClient: apiClient),
      launchMember: widget.member,
      initialTrainingMemberIds: widget.initialSelectedMemberIds,
    );
    _routes = WizardDialogRoutes(
      cubit: _cubit,
      detailBloc: _detailBloc,
      launchMember: widget.member,
    );
    _cubit.open();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  /// The run landed. The page behind is showing memberships that just changed,
  /// so it re-reads — once, whatever the outcome, because a PARTIAL moved real
  /// money too.
  void _announceLanded(MembershipWizardState state) {
    if (_announced || state.startResult == null) return;
    _announced = true;
    _detailBloc.add(
      MemberDetailRequested(widget.member.memberId, gymId: widget.member.gymId),
    );
  }

  void _close() => Navigator.of(context).pop();

  /// Close the run, then open that member's page. The page behind has already
  /// refreshed, and the viewed member needs no navigation at all.
  void _viewMember(String memberId) {
    Navigator.of(context).pop();
    if (memberId != widget.member.memberId) {
      widget.onViewMember?.call(memberId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MembershipWizardCubit>.value(
      value: _cubit,
      child: BlocConsumer<MembershipWizardCubit, MembershipWizardState>(
        listenWhen: (prev, next) => prev.startResult != next.startResult,
        listener: (_, state) => _announceLanded(state),
        builder: (context, state) {
          return MembershipFlowTheme(
            scale: const MembershipFlowScale.admin(),
            copy: const StaffFlowCopy(),
            child: AppDialog(
              // The accessible NAME of the surface; the bar below carries the
              // context a title row has nowhere to put.
              title: WizardChromeCopy.dialogTitle,
              titleBar: WizardTopBar(
                launchMemberName: widget.member.fullName,
                gymName: selectedGym.gymName ?? '',
                step: state.stepIndex + 1,
                stepCount: state.stepCount,
                // The one moment leaving would strand a charge nobody has
                // read the outcome of yet.
                onClose: state.starting ? null : _close,
              ),
              expanded: true,
              maxWidth: DesignConstants.dialogMaxWidthWide,
              contentPadding: const EdgeInsets.all(
                DesignConstants.paddingBig,
              ),
              body: WizardStepView(
                showAddMemberGroup: widget.showAddMemberGroup,
                actions: WizardActions(
                  close: _close,
                  viewMember: _viewMember,
                  addNewMember: () => _routes.addNewMember(context),
                  linkMember: () => _routes.linkMember(context),
                  changePayer: () => _routes.changePayer(context),
                  updateSavedCard: () => _routes.updateSavedCard(context),
                  captureOneOffCard: () => _routes.captureOneOffCard(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
