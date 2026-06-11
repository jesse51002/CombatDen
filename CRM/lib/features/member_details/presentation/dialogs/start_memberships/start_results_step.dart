import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_results_breakdown.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_results_failed.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_results_processing.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 8 — the per-membership breakdown. A 201 is NOT
/// success/fail: each membership reports created (✓) or
/// failed (✗ + the error). Failure granularity is the
/// charge group, so a mixed cart can half-succeed; the
/// "retry failed" affordance re-sends ONLY the failed
/// items as a new request (new idempotency key). When two
/// separate charges were made, says so plainly.
class StartResultsStep extends StatelessWidget {
  final Map<String, String> memberNames;
  final Map<String, String> planNames;
  final VoidCallback onRetryFailed;
  final VoidCallback onBackToPayment;

  /// Jump to a created membership: closes the wizard and
  /// opens that member's detail page.
  final ValueChanged<String> onViewMember;

  const StartResultsStep({
    super.key,
    required this.memberNames,
    required this.planNames,
    required this.onRetryFailed,
    required this.onBackToPayment,
    required this.onViewMember,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberDetailBloc,
        MemberDetailState>(
      builder: (context, state) {
        if (state is! MemberDetailLoaded) {
          return const SizedBox(
            height: 160,
            child: Center(child: AppSpinner()),
          );
        }
        if (state.isStartingMemberships) {
          return const StartResultsProcessing();
        }
        final error = state.startError;
        if (error != null) {
          return StartResultsFailed(
            error: error,
            onBackToPayment: onBackToPayment,
          );
        }
        final result = state.startResult;
        if (result == null) {
          return const StartResultsProcessing();
        }
        return StartResultsBreakdown(
          result: result,
          memberNames: memberNames,
          planNames: planNames,
          onRetryFailed: onRetryFailed,
          onViewMember: onViewMember,
        );
      },
    );
  }
}
