import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_response.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/batch_check_in_result_row.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The batch check-in's per-member breakdown, read live off the [ScheduleBloc]:
/// a summary line, one row per member (✓ "+N pts" / already in / skipped —
/// reason / ✗ failed — reason), and a "check in anyway" affordance that
/// resubmits only the skipped + failed members (override forced on).
class BatchCheckInResultsView extends StatelessWidget {
  final Map<String, String> memberNames;

  /// Resubmit the skipped + failed members (override forced on).
  final ValueChanged<List<String>> onRetryUnresolved;

  const BatchCheckInResultsView({
    super.key,
    required this.memberNames,
    required this.onRetryUnresolved,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScheduleBloc, ScheduleState>(
      builder: (context, state) {
        final result =
            state is ScheduleLoaded ? state.batchCheckInResult : null;
        if (result == null) return const CheckInProcessingView();
        return _Breakdown(
          result: result,
          memberNames: memberNames,
          onRetryUnresolved: onRetryUnresolved,
        );
      },
    );
  }
}

class _Breakdown extends StatelessWidget {
  final BatchCheckInResponse result;
  final Map<String, String> memberNames;
  final ValueChanged<List<String>> onRetryUnresolved;

  const _Breakdown({
    required this.result,
    required this.memberNames,
    required this.onRetryUnresolved,
  });

  @override
  Widget build(BuildContext context) {
    final unresolved = result.unresolved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          '${result.checkedInCount} of ${result.results.length} '
          'newly checked in.',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: result.results
              .map(
                (r) => BatchCheckInResultRow(
                  item: r,
                  memberName: memberNames[r.memberId] ?? 'Member',
                ),
              )
              .toList(),
        ),
        if (unresolved.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: AppOutlineButton(
              text: 'Check in the remaining ${unresolved.length} anyway',
              borderRadius: DesignConstants.radiusSmall,
              onPressed: () => onRetryUnresolved(
                unresolved.map((r) => r.memberId).toList(),
              ),
            ),
          ),
      ],
    );
  }
}
