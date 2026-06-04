import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/filter_bar.dart';

/// Search box + Add New Member button + Add Filter row.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:3581`.
class MembersControls extends StatelessWidget {
  const MembersControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          spacing: DesignConstants.spacingBig,
          children: [
            Expanded(
              child: AppSearchBox(
                hintText: ' search name....',
                onChanged: (q) => debugPrint(
                  'Search filter not wired this pass: $q',
                ),
              ),
            ),
            AppPrimaryButton(
              text: 'Add New Member',
              textStyle: DesignConstants.h2,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
                vertical: DesignConstants.spacingMedium,
              ),
              onPressed: () => debugPrint(
                'Add Member flow is out of scope this pass',
              ),
            ),
          ],
        ),
        FilterBar(
          filters: const [],
          onAddFilter: () => debugPrint(
            'Filter picker not wired this pass',
          ),
          onRemoveFilter: (_) => debugPrint(
            'Filter remove not wired this pass',
          ),
        ),
      ],
    );
  }
}
