import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_upgrade_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/upgrade_membership_success_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/upgrade_plan_picker.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

enum _Step { select, preview, processing, success }

/// Cross-plan upgrade: pick a DIFFERENT recurring plan, preview the
/// prorated difference charged now + the new monthly, then commit via
/// [UpgradeMembershipRequested]. Submitting drives an in-dialog
/// spinner → success step; the outcome rides the bloc's dedicated
/// upgrade channel ([isUpgrading] / [upgradeSuccess] / [upgradeError])
/// so the screen-level overlay + error dialog never fire while this
/// dialog is open (mirrors the charge-card dialog).
class UpgradeMembershipDialog extends StatefulWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;
  final String coveredMemberId;

  const UpgradeMembershipDialog({
    super.key,
    required this.member,
    required this.membership,
    required this.coveredMemberId,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    required MembershipInfo membership,
    required String coveredMemberId,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: UpgradeMembershipDialog(
          member: member,
          membership: membership,
          coveredMemberId: coveredMemberId,
        ),
      ),
    );
  }

  @override
  State<UpgradeMembershipDialog> createState() =>
      _UpgradeMembershipDialogState();
}

class _UpgradeMembershipDialogState
    extends State<UpgradeMembershipDialog> {
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  late final MemberDetailBloc _bloc;
  late final Future<List<MembershipPlanResponse>> _plans;
  late final int _successTokenAtOpen;

  /// The resolved upgrade-target plans, cached so the success step can
  /// name the plan the staff picked (the upgrade endpoint returns only
  /// the successor item_id).
  List<MembershipPlanResponse> _loadedPlans = const [];

  String? _targetPlanId;
  ProrationBehavior _proration = ProrationBehavior.prorateToAnchor;
  _Step _step = _Step.select;
  String _upgradedPlanName = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<MemberDetailBloc>();
    final st = _bloc.state;
    _successTokenAtOpen =
        st is MemberDetailLoaded ? st.upgradeSuccess : 0;
    // Clear any prior upgrade error so a stale failure never flashes.
    _bloc.add(const UpgradeMembershipOutcomeCleared());
    _plans = _loadPlans();
    _plans.then((list) {
      if (mounted) _loadedPlans = list;
    });
  }

  String get _itemId => widget.membership.itemId;

  /// The gym's recurring plans the member could upgrade TO — every
  /// recurring plan except the one this membership is already on.
  Future<List<MembershipPlanResponse>> _loadPlans() async {
    final plans =
        await _repository.listMembershipPlans(widget.member.gymId);
    return plans
        .where((p) =>
            p.planType == PlanType.recurring &&
            p.planId != widget.membership.planId &&
            p.activePrice != null)
        .toList();
  }

  Future<DueNowVsRecurringPreview?> _loadPreview() {
    return _repository.upgradePreview(
      MemberMembershipsUpgradeRequest(
        itemId: _itemId,
        memberId: widget.coveredMemberId,
        targetPlanId: _targetPlanId!,
        prorationBehavior: _proration,
        // The preview endpoint ignores idempotency_key, but send a real
        // UUID (not '') so it stays valid if the schema ever hardens.
        idempotencyKey: const Uuid().v4(),
      ),
    );
  }

  String _resolvePlanName(String planId) {
    for (final p in _loadedPlans) {
      if (p.planId == planId) return p.planName;
    }
    return 'the new plan';
  }

  void _commit() {
    setState(() {
      _error = null;
      _upgradedPlanName = _resolvePlanName(_targetPlanId!);
      _step = _Step.processing;
    });
    _bloc.add(
      UpgradeMembershipRequested(
        itemId: _itemId,
        memberId: widget.coveredMemberId,
        targetPlanId: _targetPlanId!,
        prorationBehavior: _proration,
      ),
    );
  }

  void _onState(BuildContext context, MemberDetailState state) {
    if (state is! MemberDetailLoaded) return;
    if (_step != _Step.processing) return;
    final err = state.upgradeError;
    if (err != null) {
      setState(() {
        _error = err;
        _step = _Step.preview;
      });
      _bloc.add(const UpgradeMembershipOutcomeCleared());
      return;
    }
    if (state.upgradeSuccess != _successTokenAtOpen) {
      setState(() => _step = _Step.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MemberDetailBloc, MemberDetailState>(
      listenWhen: (prev, curr) => curr is MemberDetailLoaded,
      listener: _onState,
      child: AppDialog(
        title: 'Upgrade plan',
        showCloseButton: _step != _Step.processing,
        body: _buildBody(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.select:
        return UpgradePlanPicker(
          plans: _plans,
          currentPlanName: widget.membership.planName,
          currentPrice: widget.membership.baseCost,
          selectedPlanId: _targetPlanId,
          proration: _proration,
          onPlanSelected: (id) => setState(() => _targetPlanId = id),
          onProrationChanged: (v) => setState(() => _proration = v),
        );
      case _Step.preview:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
            InvoicePreviewSection(
              loadPreview: _loadPreview,
              loadCurrent: () => _repository.getUpcomingInvoice(
                widget.membership.paidByMemberId,
              ),
              recurringFallbackMonthly:
                  widget.member.totalMonthlyRecurringPrice,
              dueNowLabel: 'Charged now (prorated difference)',
              emptyLabel: 'No charge now.',
            ),
          ],
        );
      case _Step.processing:
        return const _UpgradeProcessing();
      case _Step.success:
        return UpgradeMembershipSuccessView(
          memberName: widget.member.firstName,
          planName: _upgradedPlanName,
        );
    }
  }

  Widget _buildActions() {
    switch (_step) {
      case _Step.select:
        return AppDialogActions(
          primaryLabel: 'Preview',
          primaryOnPressed: _targetPlanId == null
              ? null
              : () => setState(() => _step = _Step.preview),
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _Step.preview:
        return AppDialogActions(
          primaryLabel: 'Upgrade plan',
          primaryOnPressed: _commit,
          secondaryLabel: 'Back',
          secondaryOnPressed: () => setState(() {
            _step = _Step.select;
            _error = null;
          }),
        );
      case _Step.processing:
        return const AppDialogActions(
          primaryLabel: 'Upgrade plan',
          isLoading: true,
          primaryOnPressed: null,
        );
      case _Step.success:
        return AppDialogActions(
          primaryLabel: 'Done',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}

class _UpgradeProcessing extends StatelessWidget {
  const _UpgradeProcessing();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.dialogProcessingHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            const AppSpinner(),
            Text(
              'Upgrading…',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
