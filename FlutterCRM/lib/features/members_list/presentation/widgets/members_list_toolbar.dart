import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// Toolbar with search field, view switcher, and
/// "Add New Member" button.
///
/// On wide screens these sit in a single row. On narrow
/// screens each item stacks vertically.
class MembersListToolbar extends StatelessWidget {
  final MembersListView activeView;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<MembersListView> onViewChanged;
  final VoidCallback onAddNewMember;

  const MembersListToolbar({
    super.key,
    required this.activeView,
    required this.onSearchChanged,
    required this.onViewChanged,
    required this.onAddNewMember,
  });

  static const _views = MembersListView.values;

  /// Breakpoint below which the toolbar stacks
  /// vertically.
  static const double _wideBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return _wideLayout();
        }
        return _narrowLayout();
      },
    );
  }

  Widget _wideLayout() {
    return Row(
      children: [
        Expanded(
          flex: 35,
          child: AppSearchBox(
            onChanged: onSearchChanged,
          ),
        ),
        const SizedBox(
          width: DesignConstants.spacingLarge,
        ),
        ViewSwitcher(
          labels: _views
              .map((v) => v.displayLabel)
              .toList(),
          selectedIndex: _views.indexOf(activeView),
          onSelected: (index) =>
              onViewChanged(_views[index]),
        ),
        const Spacer(),
        AppPrimaryButton(
          text: 'Add New Member',
          onPressed: onAddNewMember,
        ),
      ],
    );
  }

  Widget _narrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        AppSearchBox(
          onChanged: onSearchChanged,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ViewSwitcher(
            labels: _views
                .map((v) => v.displayLabel)
                .toList(),
            selectedIndex:
                _views.indexOf(activeView),
            onSelected: (index) =>
                onViewChanged(_views[index]),
          ),
        ),
        AppPrimaryButton(
          text: 'Add New Member',
          onPressed: onAddNewMember,
          fullWidth: true,
        ),
      ],
    );
  }
}
