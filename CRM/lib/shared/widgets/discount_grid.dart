import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A selectable discount in a [DiscountGrid].
///
/// A plain display shape — the member-detail billing
/// dialogs (a later workflow) map their own coupon model
/// onto this (id + name + the formatted value / duration
/// labels) so the grid never depends on a billing model.
class DiscountOption {
  /// Stable id used for selection and toggling.
  final String id;
  final String name;

  /// Formatted value, e.g. "20% off" or "$15 off".
  final String valueLabel;

  /// Formatted duration, e.g. "Once" / "For 3 months" /
  /// "Forever". Omit when there's nothing to show.
  final String? durationLabel;

  const DiscountOption({
    required this.id,
    required this.name,
    required this.valueLabel,
    this.durationLabel,
  });
}

/// Two-column grid of selectable discount tiles. Works for
/// single- and multi-select: callers drive selection via
/// [selectedIds] and toggle in [onToggle].
///
/// `shrinkWrap`s so it composes inside a scrolling dialog
/// body. A reusable billing primitive.
class DiscountGrid extends StatelessWidget {
  final List<DiscountOption> discounts;
  final Set<String> selectedIds;
  final ValueChanged<DiscountOption> onToggle;

  const DiscountGrid({
    super.key,
    required this.discounts,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: DesignConstants.spacingMedium,
      mainAxisSpacing: DesignConstants.spacingMedium,
      childAspectRatio: 2.0,
      children: discounts
          .map(
            (d) => DiscountTile(
              discount: d,
              isSelected: selectedIds.contains(d.id),
              onTap: () => onToggle(d),
            ),
          )
          .toList(),
    );
  }
}

/// A single discount tile — also exported so a caller can
/// place one outside the grid if needed.
class DiscountTile extends StatelessWidget {
  final DiscountOption discount;
  final bool isSelected;
  final VoidCallback onTap;

  const DiscountTile({
    super.key,
    required this.discount,
    required this.isSelected,
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
          color: isSelected
              ? DesignConstants.primaryColor10
              : DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: isSelected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(child: _Labels(discount: discount)),
            Icon(
              isSelected
                  ? Symbols.check_circle_sharp
                  : Symbols.radio_button_unchecked_sharp,
              size: DesignConstants.iconSizeLarge,
              color: isSelected
                  ? DesignConstants.primaryColor
                  : DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
          ],
        ),
      ),
    );
  }
}

class _Labels extends StatelessWidget {
  final DiscountOption discount;

  const _Labels({required this.discount});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          discount.name,
          style: DesignConstants.p.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          discount.valueLabel,
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (discount.durationLabel != null)
          Text(
            discount.durationLabel!,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text3rd,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
