import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// Column definitions for the members table, one set per view.
///
/// Pure data, kept out of [MembersTable] so the widget stays readable
/// as views are added.
List<AppDataTableColumn> membersTableColumns(
  MembersListView view,
) {
  return switch (view) {
    MembersListView.all => const [
        AppDataTableColumn(
          label: 'Name',
          minWidth: 180,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Contact',
          minWidth: 200,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Membership',
          minWidth: 220,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Last Class',
          minWidth: 130,
        ),
      ],
    MembersListView.trial => const [
        AppDataTableColumn(
          label: 'Name',
          minWidth: 180,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Days Remaining',
          minWidth: 140,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Trial Start Date',
          minWidth: 140,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Trial End Date',
          minWidth: 140,
          fill: true,
        ),
      ],
    MembersListView.frozen => const [
        AppDataTableColumn(
          label: 'Name',
          minWidth: 180,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Freeze Start',
          minWidth: 140,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Freeze End',
          minWidth: 140,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Days Until Unfrozen',
          minWidth: 160,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Price',
          minWidth: 120,
        ),
      ],
    MembersListView.overdue => const [
        AppDataTableColumn(
          label: 'Name',
          minWidth: 180,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Contact',
          minWidth: 200,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Membership',
          minWidth: 200,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Days Late',
          minWidth: 120,
        ),
      ],
    // The unfinished-signup queue: who they are, both ways to reach
    // them (a stalled signup often carries only one of the two), how
    // long they have waited, and the action that finishes it.
    MembersListView.incomplete => const [
        AppDataTableColumn(
          label: 'Name',
          minWidth: 180,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Email',
          minWidth: 200,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Phone',
          minWidth: 150,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Waiting',
          minWidth: 110,
        ),
        AppDataTableColumn(
          label: '',
          minWidth: 150,
        ),
      ],
  };
}
