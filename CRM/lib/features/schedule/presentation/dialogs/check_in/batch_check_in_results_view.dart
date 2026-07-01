import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_response.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/batch_check_in_result_row.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// The batch check-in's per-member breakdown, read live off the [ScheduleBloc]:
/// a summary line, one row per member (✓ "+N pts" / already in / needs
/// confirmation / ✗ failed, with any non-blocking warnings as a small note),
/// and — when any member was held for confirmation — a "Check in anyway"
/// affordance that resubmits just that subset via [onConfirmWarnings].
/// [inlineError] surfaces a failed confirmation retry without discarding the
/// already-rendered breakdown.
class BatchCheckInResultsView extends StatelessWidget {
  final Map<String, String> memberNames;
  final ValueChanged<List<String>> onConfirmWarnings;
  final String? inlineError;

  const BatchCheckInResultsView({
    super.key,
    required this.memberNames,
    required this.onConfirmWarnings,
    this.inlineError,
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
          onConfirmWarnings: onConfirmWarnings,
          inlineError: inlineError,
        );
      },
    );
  }
}

class _Breakdown extends StatelessWidget {
  final BatchCheckInResponse result;
  final Map<String, String> memberNames;
  final ValueChanged<List<String>> onConfirmWarnings;
  final String? inlineError;

  const _Breakdown({
    required this.result,
    required this.memberNames,
    required this.onConfirmWarnings,
    this.inlineError,
  });

  @override
  Widget build(BuildContext context) {
    final needsConfirmation = result.needsConfirmation;
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
        if (needsConfirmation.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: AppOutlineButton(
              text: 'Check in the remaining ${needsConfirmation.length} '
                  'anyway',
              borderRadius: DesignConstants.radiusSmall,
              onPressed: () => onConfirmWarnings(
                needsConfirmation.map((r) => r.memberId).toList(),
              ),
            ),
          ),
        if (inlineError != null) ErrorMessage(message: inlineError!),
      ],
    );
  }
}
