import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';

/// Dropdown list of memberships used by dialogs that
/// target a specific membership (cancel, change price,
/// mark paid cash, add/remove discount).
class MembershipPicker extends StatelessWidget {
  final List<MembershipInfo> memberships;
  final MembershipInfo? selected;
  final ValueChanged<MembershipInfo> onChanged;
  final String label;

  const MembershipPicker({
    super.key,
    required this.memberships,
    required this.selected,
    required this.onChanged,
    this.label = 'Membership',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          label,
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingSmall,
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
          child: DropdownButtonHideUnderline(
            child: DropdownButton<MembershipInfo>(
              isExpanded: true,
              value: selected,
              icon: Icon(
                Symbols.expand_more_sharp,
                color: DesignConstants.text,
                weight: DesignConstants.iconWeight,
              ),
              dropdownColor: DesignConstants.popup,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text,
              ),
              items: memberships
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(
                        m.planName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (m) {
                if (m != null) onChanged(m);
              },
            ),
          ),
        ),
      ],
    );
  }
}
