import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Migrates a member's membership to the plan's current
/// active price. The merged contract takes no target price
/// id — only `item_id`, `member_id`, and a prorate flag —
/// so this dialog only offers the prorate choice and
/// dispatches [UpdatePriceRequested].
class UpdatePriceDialog extends StatefulWidget {
  final MembershipInfo membership;
  final String coveredMemberId;
  final String coveredMemberName;

  const UpdatePriceDialog({
    super.key,
    required this.membership,
    required this.coveredMemberId,
    required this.coveredMemberName,
  });

  /// Resolves the membership item for [coveredMemberId] and
  /// shows the dialog. No-op when the member is not covered.
  static Future<void> show({
    required BuildContext context,
    required MembershipInfo membership,
    required String coveredMemberId,
    required String coveredMemberName,
  }) {
    if (membership.itemIdFor(coveredMemberId) == null) {
      return Future.value();
    }
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: UpdatePriceDialog(
          membership: membership,
          coveredMemberId: coveredMemberId,
          coveredMemberName: coveredMemberName,
        ),
      ),
    );
  }

  @override
  State<UpdatePriceDialog> createState() =>
      _UpdatePriceDialogState();
}

class _UpdatePriceDialogState extends State<UpdatePriceDialog> {
  bool _prorate = false;

  void _submit() {
    final itemId =
        widget.membership.itemIdFor(widget.coveredMemberId);
    if (itemId == null) {
      Navigator.of(context).pop();
      return;
    }
    context.read<MemberDetailBloc>().add(
          UpdatePriceRequested(
            itemId: itemId,
            memberId: widget.coveredMemberId,
            prorate: _prorate,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Migrate to current price',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Move ${widget.coveredMemberName}’s '
            '${widget.membership.planName} membership to the '
            'plan’s current active price. They are currently '
            'billed at an older price.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
          _ProrateToggle(
            value: _prorate,
            onChanged: (v) => setState(() => _prorate = v),
          ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Migrate price',
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}

class _ProrateToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ProrateToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
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
            color: value
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
            width: value ? 2 : 1,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              value
                  ? Symbols.check_box_sharp
                  : Symbols.check_box_outline_blank_sharp,
              size: DesignConstants.iconSizeLarge,
              weight: DesignConstants.iconWeight,
              color: value
                  ? DesignConstants.primaryColor
                  : DesignConstants.text3rd,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    'Prorate the change',
                    style: DesignConstants.p.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Charge or credit the difference for '
                    'the remainder of this cycle now.',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
