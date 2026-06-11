import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
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
          return const _Processing();
        }
        final error = state.startError;
        if (error != null) {
          return _StartFailed(
            error: error,
            onBackToPayment: onBackToPayment,
          );
        }
        final result = state.startResult;
        if (result == null) {
          return const _Processing();
        }
        return _Breakdown(
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

class _Processing extends StatelessWidget {
  const _Processing();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            const AppSpinner(),
            Text(
              'Starting memberships…',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The whole request was rejected (HTTP 400 validation /
/// transport failure) — nothing was charged or created.
class _StartFailed extends StatelessWidget {
  final String error;
  final VoidCallback onBackToPayment;

  const _StartFailed({
    required this.error,
    required this.onBackToPayment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'The request was not accepted',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.badRed,
          ),
        ),
        Text(error, style: DesignConstants.p),
        AppOutlineButton(
          text: 'Back to payment',
          borderRadius: DesignConstants.radiusSmall,
          onPressed: onBackToPayment,
        ),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  final MemberMembershipsStartResponse result;
  final Map<String, String> memberNames;
  final Map<String, String> planNames;
  final VoidCallback onRetryFailed;
  final ValueChanged<String> onViewMember;

  const _Breakdown({
    required this.result,
    required this.memberNames,
    required this.planNames,
    required this.onRetryFailed,
    required this.onViewMember,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (result.multipleCharges)
          Container(
            padding: const EdgeInsets.all(
              DesignConstants.spacingSmall,
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
            child: Text(
              'Two separate charges were made: one for '
              'the one-time purchases and one for the '
              'recurring memberships.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: result.results
              .map(
                (r) => _ResultRow(
                  item: r,
                  memberName:
                      memberNames[r.memberId] ??
                          'Member',
                  planName:
                      planNames[r.planId] ?? 'Plan',
                  onView: r.isCreated
                      ? () =>
                          onViewMember(r.memberId)
                      : null,
                ),
              )
              .toList(),
        ),
        if (result.hasFailures)
          AppOutlineButton(
            text: 'Retry the failed memberships',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: onRetryFailed,
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final MemberMembershipsStartResultItem item;
  final String memberName;
  final String planName;

  /// Set on created rows — the "link to the membership".
  final VoidCallback? onView;

  const _ResultRow({
    required this.item,
    required this.memberName,
    required this.planName,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final created = item.isCreated;
    final color = created
        ? DesignConstants.goodGreen
        : DesignConstants.badRed;
    final row = Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            created
                ? Symbols.check_circle_sharp
                : Symbols.cancel_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeLarge,
            color: color,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  '$memberName · $planName',
                  style: DesignConstants.p.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  created
                      ? 'Created — tap to view the '
                          'membership'
                      : item.error ?? 'Failed',
                  style:
                      DesignConstants.pSmall.copyWith(
                    color: created
                        ? DesignConstants.text2nd
                        : DesignConstants.badRed,
                  ),
                ),
              ],
            ),
          ),
          Text(
            item.status.displayLabel,
            style: DesignConstants.pSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onView == null) return row;
    return InkWell(
      onTap: onView,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: row,
    );
  }
}
