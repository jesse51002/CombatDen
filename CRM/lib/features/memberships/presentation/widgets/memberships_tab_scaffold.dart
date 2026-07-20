import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Common layout for a Memberships sub-tab: the catalog [table]
/// (a shrink-wrapped `AppDataTable` rendered flat on the page
/// background, matching the members list) with the "Add New … +"
/// [addRow] beneath it, in a scroll view.
///
/// [addRow] is null for a read-only (front-desk) catalog — the create
/// affordance is a WRITE surface, so the tab omits it and only the table
/// renders.
class MembershipsTabScaffold extends StatelessWidget {
  final Widget table;
  final Widget? addRow;

  const MembershipsTabScaffold({
    super.key,
    required this.table,
    this.addRow,
  });

  @override
  Widget build(BuildContext context) {
    final addRow = this.addRow;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: DesignConstants.paddingBig),
      child: Column(
        spacing: DesignConstants.spacingMedium,
        children: [
          table,
          if (addRow != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.screenHorizontalPadding,
              ),
              child: addRow,
            ),
        ],
      ),
    );
  }
}

/// Loading body for a Memberships sub-tab.
class TabLoading extends StatelessWidget {
  const TabLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(child: AppSpinner()),
    );
  }
}

/// Error body for a Memberships sub-tab, with a retry path.
class TabError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const TabError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          ErrorMessage(message: message),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Surfaces a failed catalog mutation as a snackbar.
void showTabActionError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: DesignConstants.p.copyWith(color: DesignConstants.onAccent),
      ),
      backgroundColor: DesignConstants.badRed,
    ),
  );
}

/// Surfaces a committed catalog mutation as a green success snackbar.
void showTabActionSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: DesignConstants.p.copyWith(
          color: DesignConstants.onFill(DesignConstants.goodGreen),
        ),
      ),
      backgroundColor: DesignConstants.goodGreen,
    ),
  );
}
