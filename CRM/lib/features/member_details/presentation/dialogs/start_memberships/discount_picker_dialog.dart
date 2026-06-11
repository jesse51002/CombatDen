import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_form.dart';
import 'package:crm/features/member_details/presentation/widgets/discount_lifetime_label.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/discount_grid.dart';

/// What the picker hands back: exactly one of [presetId]
/// (an existing preset picked from the grid) or [custom]
/// (an inline value, minted server-side as a one-shot
/// custom).
class DiscountPickerResult {
  final String? presetId;
  final DiscountValue? custom;

  const DiscountPickerResult.preset(String id)
      : presetId = id,
        custom = null;

  const DiscountPickerResult.custom(DiscountValue value)
      : presetId = null,
        custom = value;
}

/// The "Add discount" picker for one membership draft on
/// the deals step: the gym's preset discounts plus the
/// inline custom value form. Tapping an unadded preset (or
/// adding a custom) pops with the pick; presets already on
/// the membership render selected and inert — they are
/// removed from the membership card's grid, not here.
class DiscountPickerDialog extends StatefulWidget {
  final String planName;
  final List<DiscountResponse> presets;

  /// Preset ids already added to this membership.
  final Set<String> addedPresetIds;

  const DiscountPickerDialog({
    super.key,
    required this.planName,
    required this.presets,
    required this.addedPresetIds,
  });

  static Future<DiscountPickerResult?> show({
    required BuildContext context,
    required String planName,
    required List<DiscountResponse> presets,
    required Set<String> addedPresetIds,
  }) {
    return showDialog<DiscountPickerResult>(
      context: context,
      builder: (_) => DiscountPickerDialog(
        planName: planName,
        presets: presets,
        addedPresetIds: addedPresetIds,
      ),
    );
  }

  @override
  State<DiscountPickerDialog> createState() =>
      _DiscountPickerDialogState();
}

class _DiscountPickerDialogState
    extends State<DiscountPickerDialog> {
  bool _showCustomForm = false;

  void _onPresetTap(DiscountOption option) {
    if (widget.addedPresetIds.contains(option.id)) {
      return;
    }
    Navigator.of(context).pop(
      DiscountPickerResult.preset(option.id),
    );
  }

  void _onCustomAdd(DiscountValue value) {
    Navigator.of(context).pop(
      DiscountPickerResult.custom(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Add discount',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            'For the ${widget.planName} membership.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
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
              selectedIds: widget.addedPresetIds,
              onToggle: _onPresetTap,
            )
          else
            Text(
              'This gym has no discount presets.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          if (_showCustomForm)
            CustomDiscountValueForm(
              onAdd: _onCustomAdd,
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
