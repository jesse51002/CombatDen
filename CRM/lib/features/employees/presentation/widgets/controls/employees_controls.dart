import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/filter_bar.dart';

/// Search box + Add Employee button + Add Filter row for the
/// employees screen; actions are debug no-ops in the prototype.
class EmployeesControls extends StatelessWidget {
  const EmployeesControls({super.key});

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
                hintText: ' search name or role....',
                onChanged: (q) => debugPrint(
                  'Search filter not wired this pass: $q',
                ),
              ),
            ),
            AppPrimaryButton(
              text: 'Add Employee',
              textStyle: DesignConstants.h2,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
                vertical: DesignConstants.spacingMedium,
              ),
              onPressed: () => debugPrint(
                'Add Employee flow is out of scope this pass',
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
