import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_form.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_labels.dart';
import 'package:crm/features/member_details/presentation/widgets/discount_lifetime_label.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/discount_grid.dart';

/// One membership's discount controls on the discounts
/// step: the gym's preset multi-pick plus the inline custom
/// value form (one-shot customs minted server-side).
class DraftDiscountsCard extends StatefulWidget {
  final MembershipDraft draft;
  final List<DiscountResponse> presets;
  final ValueChanged<String> onPresetToggle;
  final ValueChanged<DiscountValue> onCustomAdded;
  final ValueChanged<int> onCustomRemoved;

  const DraftDiscountsCard({
    super.key,
    required this.draft,
    required this.presets,
    required this.onPresetToggle,
    required this.onCustomAdded,
    required this.onCustomRemoved,
  });

  @override
  State<DraftDiscountsCard> createState() =>
      _DraftDiscountsCardState();
}

class _DraftDiscountsCardState
    extends State<DraftDiscountsCard> {
  bool _showCustomForm = false;

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            draft.plan.planName,
            style: DesignConstants.h3,
          ),
          if (widget.presets.isNotEmpty)
            DiscountGrid(
              discounts: widget.presets
                  .map(
                    (d) => DiscountOption(
                      id: d.discountId,
                      name: d.discountName,
                      valueLabel: d.displayLabel,
                      durationLabel:
                          discountLifetimeLabel(d),
                    ),
                  )
                  .toList(),
              selectedIds: draft.discountIds,
              onToggle: (d) =>
                  widget.onPresetToggle(d.id),
            )
          else
            Text(
              'This gym has no discount presets.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          if (draft.customDiscounts.isNotEmpty)
            Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingSmall,
              children: [
                for (var i = 0;
                    i < draft.customDiscounts.length;
                    i++)
                  _CustomDiscountRow(
                    value: draft.customDiscounts[i],
                    onRemove: () =>
                        widget.onCustomRemoved(i),
                  ),
              ],
            ),
          if (_showCustomForm)
            CustomDiscountValueForm(
              onAdd: (value) {
                widget.onCustomAdded(value);
                setState(
                  () => _showCustomForm = false,
                );
              },
              onCancel: () => setState(
                () => _showCustomForm = false,
              ),
            )
          else
            AppOutlineButton(
              text: 'Add a custom discount',
              borderRadius: DesignConstants.radiusSmall,
              onPressed: () => setState(
                () => _showCustomForm = true,
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomDiscountRow extends StatelessWidget {
  final DiscountValue value;
  final VoidCallback onRemove;

  const _CustomDiscountRow({
    required this.value,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(
            child: Text(
              'Custom · '
              '${discountValueAmountLabel(value)} · '
              '${discountValueLifetimeLabel(value)}',
              style: DesignConstants.pSmall,
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
            child: Icon(
              Symbols.close_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeSmall,
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
