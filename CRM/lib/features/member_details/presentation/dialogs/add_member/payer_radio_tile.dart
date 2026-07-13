import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/existing_member_pill.dart';
import 'package:crm/shared/widgets/member_avatar.dart';

/// A single-select payer row for the choose-payer step: avatar + name (+ an
/// existing-member pill) with a trailing radio glyph. The selected tile lifts
/// to an accent fill + accent border; the whole row is the tap target.
class PayerRadioTile extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final bool wasExisting;
  final bool selected;
  final VoidCallback onTap;

  const PayerRadioTile({
    super.key,
    required this.name,
    required this.wasExisting,
    required this.selected,
    required this.onTap,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(DesignConstants.radiusSmall),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          decoration: BoxDecoration(
            color: selected
                ? DesignConstants.primaryColor10
                : DesignConstants.backgroundColor,
            borderRadius:
                BorderRadius.circular(DesignConstants.radiusSmall),
            border: Border.all(
              color: selected
                  ? DesignConstants.primaryColor
                  : DesignConstants.divider,
              width: selected
                  ? DesignConstants.buttonBorder
                  : DesignConstants.dividerThickness,
            ),
          ),
          child: Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              MemberAvatar(
                name: name,
                photoUrl: photoUrl,
                size: DesignConstants.iconSizeBig,
              ),
              Expanded(
                child: Text(name, style: DesignConstants.h3),
              ),
              if (wasExisting) const ExistingMemberPill(),
              Icon(
                selected
                    ? Symbols.radio_button_checked_sharp
                    : Symbols.radio_button_unchecked_sharp,
                size: DesignConstants.iconSizeLarge,
                weight: DesignConstants.iconWeight,
                color: selected
                    ? DesignConstants.primaryColor
                    : DesignConstants.text2nd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
