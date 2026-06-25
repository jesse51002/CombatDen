import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_upgrade_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/upgrade_plan_picker.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

enum _Step { select, preview }

/// Cross-plan upgrade: pick a DIFFERENT recurring plan, preview the
/// prorated difference charged now + the new monthly, then commit via
/// [UpgradeMembershipRequested]. Mirrors the discount manage dialog's
/// select → preview → commit shape; the plan list is fetched in-dialog.
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

  late final Future<List<MembershipPlanResponse>> _plans;
  String? _targetPlanId;
  ProrationBehavior _proration = ProrationBehavior.prorateToAnchor;
  _Step _step = _Step.select;

  @override
  void initState() {
    super.initState();
    _plans = _loadPlans();
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
        idempotencyKey: '',
      ),
    );
  }

  void _commit() {
    context.read<MemberDetailBloc>().add(
          UpgradeMembershipRequested(
            itemId: _itemId,
            memberId: widget.coveredMemberId,
            targetPlanId: _targetPlanId!,
            prorationBehavior: _proration,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isPreview = _step == _Step.preview;
    return AppDialog(
      title: 'Upgrade plan',
      body: isPreview
          ? InvoicePreviewSection(
              loadPreview: _loadPreview,
              loadCurrent: () => _repository.getUpcomingInvoice(
                widget.membership.paidByMemberId,
              ),
              recurringFallbackMonthly:
                  widget.member.totalMonthlyRecurringPrice,
              dueNowLabel: 'Charged now (prorated difference)',
              emptyLabel: 'No charge now.',
            )
          : UpgradePlanPicker(
              plans: _plans,
              selectedPlanId: _targetPlanId,
              proration: _proration,
              onPlanSelected: (id) =>
                  setState(() => _targetPlanId = id),
              onProrationChanged: (v) =>
                  setState(() => _proration = v),
            ),
      actions: isPreview
          ? AppDialogActions(
              primaryLabel: 'Upgrade plan',
              primaryOnPressed: _commit,
              secondaryLabel: 'Back',
              secondaryOnPressed: () =>
                  setState(() => _step = _Step.select),
            )
          : AppDialogActions(
              primaryLabel: 'Preview',
              primaryOnPressed: _targetPlanId == null
                  ? null
                  : () => setState(() => _step = _Step.preview),
              secondaryLabel: 'Cancel',
              secondaryOnPressed: () =>
                  Navigator.of(context).pop(),
            ),
    );
  }
}
