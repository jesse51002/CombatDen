import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';

/// Navigation header with arrows and membership title.
class CarouselHeader extends StatelessWidget {
  final MembershipInfo membership;
  final int currentIndex;
  final int total;
  final bool hasMultiple;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const CarouselHeader({
    super.key,
    required this.membership,
    required this.currentIndex,
    required this.total,
    required this.hasMultiple,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasMultiple)
          Semantics(
            label: 'Previous membership',
            child: IconButton(
              onPressed: onPrevious,
              icon: Icon(
                Symbols.chevron_left_sharp,
                color: onPrevious != null
                    ? DesignConstants.text
                    : DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ),
        Expanded(
          child: Column(
            children: [
              Text(
                membership.displayName,
                style: DesignConstants.h1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasMultiple)
                Semantics(
                  label: 'Membership '
                      '${currentIndex + 1} of $total',
                  child: Text(
                    '(${currentIndex + 1} / '
                    '$total Memberships)',
                    style:
                        DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasMultiple)
          Semantics(
            label: 'Next membership',
            child: IconButton(
              onPressed: onNext,
              icon: Icon(
                Symbols.chevron_right_sharp,
                color: onNext != null
                    ? DesignConstants.text
                    : DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ),
      ],
    );
  }
}
