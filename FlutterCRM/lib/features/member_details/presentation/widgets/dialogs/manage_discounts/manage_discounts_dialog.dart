import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/shared/widgets/discount_grid.dart';
import 'package:crm/features/member_details/data/models/member_memberships_update_discounts_request.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_preview_section.dart';

/// Lets staff add or remove discounts from a single
/// membership. Currently applied discounts are shown as
/// removable chips; remaining gym discounts are shown in
/// a picker with a live preview before confirming.
class ManageDiscountsDialog extends StatefulWidget {
  final String crmUserId;
  final String gymId;
  final MembershipInfo membership;

  const ManageDiscountsDialog({
    super.key,
    required this.crmUserId,
    required this.gymId,
    required this.membership,
  });

  static Future<void> show({
    required BuildContext context,
    required String crmUserId,
    required String gymId,
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
          child: ManageDiscountsDialog(
            crmUserId: crmUserId,
            gymId: gymId,
            membership: membership,
          ),
        ),
      ),
    );
  }

  @override
  State<ManageDiscountsDialog> createState() =>
      _ManageDiscountsDialogState();
}

class _ManageDiscountsDialogState
    extends State<ManageDiscountsDialog> {
  late Future<List<DiscountResponse>> _future;
  DiscountResponse? _pendingDiscount;

  @override
  void initState() {
    super.initState();
    _future = context
        .read<MemberRepository>()
        .listGymDiscounts(widget.gymId);
  }

  List<BillingAffectedPerson> _affected() {
    final byId = <String, bool>{};
    final list = <BillingAffectedPerson>[];
    for (final p in widget.membership.payingFor) {
      if (byId.containsKey(p.crmUserId)) continue;
      byId[p.crmUserId] = true;
      list.add(
        BillingAffectedPerson(
          fullName: p.fullName,
          initial:
              p.firstName.isNotEmpty ? p.firstName[0] : '?',
          photoUrl: p.photoUrl,
        ),
      );
    }
    return list;
  }

  /// Resolve an itemId to act on. Prefers the viewer's
  /// own item, but falls back to any entry in the members
  /// map — on cancelled memberships the viewer may no
  /// longer be listed, but the cancelled rows themselves
  /// still carry their item ids.
  String? _resolveItemId() {
    final own =
        widget.membership.itemIdFor(widget.crmUserId);
    if (own != null) return own;
    if (widget.membership.members.isEmpty) return null;
    return widget.membership.members.values.first.itemId;
  }

  String _resolveCrmUserId() {
    if (widget.membership.members.containsKey(
      widget.crmUserId,
    )) {
      return widget.crmUserId;
    }
    if (widget.membership.members.isEmpty) {
      return widget.crmUserId;
    }
    return widget.membership.members.keys.first;
  }

  Future<void> _onRemove(
    String discountId,
    String discountName,
  ) async {
    final itemId = _resolveItemId();
    if (itemId == null) return;
    final crmUserId = _resolveCrmUserId();

    final confirmed =
        await BillingConfirmationDialog.show(
      context: context,
      title: 'Remove discount',
      summary:
          'Removes $discountName from ${widget.membership.planName}. '
          'The next bill will reflect the higher amount.',
      effects: [
        BillingEffect(
          icon: Symbols.remove_circle_sharp,
          text: 'Discount removed: $discountName.',
          iconColor: DesignConstants.badRed,
        ),
        const BillingEffect(
          icon: Symbols.trending_up_sharp,
          text: 'Future bills increase accordingly.',
        ),
      ],
      affected: _affected(),
      confirmLabel: 'Remove Discount',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;

    final nextIds = widget.membership.discounts
        .map((d) => d.discountId)
        .where((id) => id != discountId)
        .toList();
    context.read<MemberDetailBloc>().add(
          UpdateDiscountsRequested(
            itemId: itemId,
            crmUserId: crmUserId,
            discountIds: nextIds,
          ),
        );
    Navigator.of(context).pop();
  }

  Future<void> _onAdd() async {
    final itemId = _resolveItemId();
    final crmUserId = _resolveCrmUserId();
    final d = _pendingDiscount;
    if (itemId == null || d == null) return;

    final confirmed =
        await BillingConfirmationDialog.show(
      context: context,
      title: 'Add discount',
      summary:
          'Applies ${d.discountName} to ${widget.membership.planName}.',
      effects: [
        BillingEffect(
          icon: Symbols.add_circle_sharp,
          text:
              'Discount added: ${d.discountName} · ${d.displayLabel}.',
        ),
        const BillingEffect(
          icon: Symbols.trending_down_sharp,
          text: 'Future bills decrease accordingly.',
        ),
      ],
      affected: _affected(),
      confirmLabel: 'Add Discount',
      confirmColor: DesignConstants.primaryColor,
    );
    if (!confirmed || !mounted) return;

    final nextIds = [
      ...widget.membership.discounts.map((x) => x.discountId),
      d.discountId,
    ];
    context.read<MemberDetailBloc>().add(
          UpdateDiscountsRequested(
            itemId: itemId,
            crmUserId: crmUserId,
            discountIds: nextIds,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final applied = widget.membership.discounts;
    final appliedIds =
        applied.map((d) => d.discountId).toSet();
    return AppDialog(
      title: 'Manage Discounts',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          if (applied.isEmpty)
            Text(
              'No discounts applied.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            )
          else
            Wrap(
              spacing: DesignConstants.spacingSmall,
              runSpacing: DesignConstants.spacingSmall,
              children: applied
                  .map(
                    (d) => _RemovableChip(
                      label: d.discountName,
                      sublabel: d.discountLabel,
                      onRemove: () => _onRemove(
                        d.discountId,
                        d.discountName,
                      ),
                    ),
                  )
                  .toList(),
            ),
          Divider(color: DesignConstants.divider),
          FutureBuilder<List<DiscountResponse>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState !=
                  ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: DesignConstants
                          .spacingLarge,
                    ),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final available = (snapshot.data ?? [])
                  .where(
                    (d) =>
                        !appliedIds.contains(d.discountId),
                  )
                  .toList();
              if (available.isEmpty) {
                return Text(
                  'No more gym discounts available.',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                );
              }
              return _AddDiscountSection(
                available: available,
                selected: _pendingDiscount,
                membership: widget.membership,
                crmUserId: _resolveCrmUserId(),
                itemId: _resolveItemId(),
                onSelectionChanged: (d) => setState(
                  () => _pendingDiscount = d,
                ),
                onConfirm: _onAdd,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final String label;
  final String sublabel;
  final VoidCallback onRemove;

  const _RemovableChip({
    required this.label,
    required this.sublabel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
        border: Border.all(
          color: DesignConstants.primaryColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(
            '$label · $sublabel',
            style: DesignConstants.pSmall,
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Symbols.close_sharp,
              size: 16,
              color: DesignConstants.badRed,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddDiscountSection extends StatelessWidget {
  final List<DiscountResponse> available;
  final DiscountResponse? selected;
  final MembershipInfo membership;
  final String crmUserId;
  final String? itemId;
  final ValueChanged<DiscountResponse?>
      onSelectionChanged;
  final VoidCallback onConfirm;

  const _AddDiscountSection({
    required this.available,
    required this.selected,
    required this.membership,
    required this.crmUserId,
    required this.itemId,
    required this.onSelectionChanged,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MemberRepository>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Add a discount',
          style: DesignConstants.h3,
        ),
        DiscountGrid(
          discounts: available,
          selectedIds: selected == null
              ? const {}
              : {selected!.discountId},
          onTap: (d) => onSelectionChanged(
            selected?.discountId == d.discountId ? null : d,
          ),
        ),
        if (selected != null && itemId != null)
          InvoicePreviewSection(
            refreshKey: selected!.discountId,
            loadPreview: () => repository
                .previewUpdateMembershipDiscounts(
              MemberMembershipsUpdateDiscountsRequest(
                itemId: itemId!,
                crmUserId: crmUserId,
                discountIds: [
                  ...membership.discounts
                      .map((x) => x.discountId),
                  selected!.discountId,
                ],
                idempotencyKey: const Uuid().v4(),
              ),
            ),
          ),
        AppOutlineButton(
          text: 'Add Discount',
          onPressed:
              selected != null && itemId != null
                  ? onConfirm
                  : null,
          borderRadius: DesignConstants.radiusSmall,
          fullWidth: true,
        ),
      ],
    );
  }
}
