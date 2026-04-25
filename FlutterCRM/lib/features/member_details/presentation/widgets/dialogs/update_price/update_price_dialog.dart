import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:uuid/uuid.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_update_price_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_preview_section.dart';

/// Migrates a member from an outdated price to the plan's
/// current active price. Two steps: pick which covered
/// member to update, then review the billing impact.
class UpdatePriceDialog extends StatefulWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;

  const UpdatePriceDialog({
    super.key,
    required this.member,
    required this.membership,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    required MembershipInfo membership,
  }) {
    final bloc = context.read<MemberDetailBloc>();
    final repository = context.read<MemberRepository>();
    return showDialog<void>(
      context: context,
      builder: (_) => RepositoryProvider.value(
        value: repository,
        child: BlocProvider.value(
          value: bloc,
          child: UpdatePriceDialog(
            member: member,
            membership: membership,
          ),
        ),
      ),
    );
  }

  @override
  State<UpdatePriceDialog> createState() =>
      _UpdatePriceDialogState();
}

enum _Step { pickMember, confirm }

class _UpdatePriceDialogState
    extends State<UpdatePriceDialog> {
  late Future<MembershipPlanResponse?> _planFuture;
  _Step _step = _Step.pickMember;
  PayingForMember? _selected;

  @override
  void initState() {
    super.initState();
    _planFuture = _loadPlan();
  }

  Future<MembershipPlanResponse?> _loadPlan() async {
    final plans = await context
        .read<MemberRepository>()
        .listMembershipPlans(widget.member.gymId);
    for (final p in plans) {
      if (p.planId == widget.membership.planId) return p;
    }
    return null;
  }

  List<PayingForMember> get _outdated => widget
      .membership.payingFor
      .where(
        (p) => widget.membership
            .isOnOutdatedPriceFor(p.crmUserId),
      )
      .toList();

  void _onPick(PayingForMember p) {
    setState(() {
      _selected = p;
      _step = _Step.confirm;
    });
  }

  void _onBack() {
    setState(() {
      _selected = null;
      _step = _Step.pickMember;
    });
  }

  void _onConfirm(String newPriceId) {
    final selected = _selected;
    if (selected == null) return;
    final itemId =
        widget.membership.itemIdFor(selected.crmUserId);
    if (itemId == null) return;
    context.read<MemberDetailBloc>().add(
          UpdatePriceRequested(
            itemId: itemId,
            crmUserId: selected.crmUserId,
            newPriceId: newPriceId,
            prorate: true,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MembershipPlanResponse?>(
      future: _planFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState !=
            ConnectionState.done;
        final plan = snapshot.data;
        final newPriceId = plan?.activePrice?.priceId;
        return AppDialog(
          title: _step == _Step.pickMember
              ? 'Update Price'
              : 'Confirm Price Update',
          body: loading
              ? const _Loading()
              : _body(plan),
          actions: _actions(newPriceId, loading),
        );
      },
    );
  }

  Widget _body(MembershipPlanResponse? plan) {
    if (plan?.activePrice == null) {
      return Text(
        'Could not resolve the current plan price.',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.badRed,
        ),
      );
    }
    if (_step == _Step.pickMember) {
      return _PickStep(
        outdated: _outdated,
        currentPrice: plan!.activePrice!.price,
        onSelect: _onPick,
      );
    }
    return _ConfirmStep(
      member: _selected!,
      membership: widget.membership,
      plan: plan!,
    );
  }

  AppDialogActions _actions(
    String? newPriceId,
    bool loading,
  ) {
    if (_step == _Step.pickMember) {
      return const AppDialogActions(
        primaryLabel: 'Cancel',
      );
    }
    return AppDialogActions(
      primaryLabel: 'Update Price',
      primaryColor: DesignConstants.primaryColor,
      primaryOnPressed:
          !loading && newPriceId != null && _selected != null
              ? () => _onConfirm(newPriceId)
              : null,
      secondaryLabel: 'Back',
      secondaryOnPressed: _onBack,
    );
  }
}

class _PickStep extends StatelessWidget {
  final List<PayingForMember> outdated;
  final int currentPrice;
  final ValueChanged<PayingForMember> onSelect;

  const _PickStep({
    required this.outdated,
    required this.currentPrice,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (outdated.isEmpty) {
      return Text(
        'No one on this plan is on an outdated price.',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Who do you want to move to the current price of '
          '${formatMinorUnits(currentPrice, currency: 'USD')}?',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: outdated
              .map(
                (p) => _MemberTile(
                  member: p,
                  onTap: () => onSelect(p),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final PayingForMember member;
  final VoidCallback onTap;

  const _MemberTile({
    required this.member,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: DesignConstants.divider,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: DesignConstants.card,
              backgroundImage: member.photoUrl != null
                  ? NetworkImage(member.photoUrl!)
                  : null,
              child: member.photoUrl == null
                  ? Icon(
                      Symbols.person_sharp,
                      size: 18,
                      color: DesignConstants.text3rd,
                      weight:
                          DesignConstants.iconWeight,
                    )
                  : null,
            ),
            Expanded(
              child: Text(
                member.fullName,
                style: DesignConstants.p,
              ),
            ),
            Icon(
              Symbols.chevron_right_sharp,
              color: DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  final PayingForMember member;
  final MembershipInfo membership;
  final MembershipPlanResponse plan;

  const _ConfirmStep({
    required this.member,
    required this.membership,
    required this.plan,
  });

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MemberRepository>();
    final itemId = membership.itemIdFor(member.crmUserId);
    final newPriceId = plan.activePrice!.priceId;
    final newPrice = formatMinorUnits(
      plan.activePrice!.price,
      currency: 'USD',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          '${member.fullName} will move to the current '
          'price of $newPrice. The difference is prorated '
          'on the next bill.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        if (itemId != null)
          InvoicePreviewSection(
            refreshKey: '$itemId-$newPriceId',
            loadPreview: () =>
                repository.previewUpdateMembershipPrice(
              MemberMembershipsUpdatePriceRequest(
                itemId: itemId,
                crmUserId: member.crmUserId,
                newPriceId: newPriceId,
                prorate: true,
                idempotencyKey: const Uuid().v4(),
              ),
            ),
          ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(
        DesignConstants.spacingLarge,
      ),
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
