import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_response.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/batch_check_in_result_row.dart';

/// The batch check-in's per-member breakdown, read live off the [ScheduleBloc]:
/// a summary line plus one row per member (✓ "+N pts" / already in / ✗ failed,
/// with any non-blocking warnings as a small note). Staff always records, so
/// there is no "check in anyway" retry.
class BatchCheckInResultsView extends StatelessWidget {
  final Map<String, String> memberNames;

  const BatchCheckInResultsView({
    super.key,
    required this.memberNames,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScheduleBloc, ScheduleState>(
      builder: (context, state) {
        final result =
            state is ScheduleLoaded ? state.batchCheckInResult : null;
        if (result == null) return const CheckInProcessingView();
        return _Breakdown(result: result, memberNames: memberNames);
      },
    );
  }
}

class _Breakdown extends StatelessWidget {
  final BatchCheckInResponse result;
  final Map<String, String> memberNames;

  const _Breakdown({
    required this.result,
    required this.memberNames,
  });

  @override
  Widget build(BuildContext context) {
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
      ],
    );
  }
}
