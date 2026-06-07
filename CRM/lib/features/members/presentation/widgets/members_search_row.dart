import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Top control row above the members table: a fully-rounded search box
/// on the left and the accent "Add New Member" CTA on the right.
class MembersSearchRow extends StatelessWidget {
  final VoidCallback onAddMember;
  final ValueChanged<String> onSearchChanged;

  const MembersSearchRow({
    super.key,
    required this.onAddMember,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        Expanded(child: _SearchBox(onChanged: onSearchChanged)),
        AppPrimaryButton(text: 'Add New Member', onPressed: onAddMember),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBox({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingMedium,
      ),
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.search_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text3rd,
            size: DesignConstants.iconSizeMedium,
          ),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text,
              ),
              cursorColor: DesignConstants.primaryColor,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'search name....',
                hintStyle: DesignConstants.h2.copyWith(
                  color: DesignConstants.text3rd,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
