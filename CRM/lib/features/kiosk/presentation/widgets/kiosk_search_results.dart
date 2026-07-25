import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_name_row.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The name-search results — the kiosk's ONE affordant [KioskNameRow]
/// (deliberately NO avatars/photos), plus the searching / no-match / failed
/// states. Tapping a name hands off to [KioskFlowCubit.selectMember].
///
/// Every populated state carries its OWN top gap and the resting state is a
/// true zero-height box, which is what keeps the search field on the QR's
/// optical centre. Never re-introduce that gap as a parent column spacing — it
/// would then be reserved even when this renders nothing.
class KioskSearchResults extends StatelessWidget {
  const KioskSearchResults({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskFlowCubit, KioskFlowState>(
      buildWhen: (prev, cur) =>
          prev.searchResults != cur.searchResults ||
          prev.searching != cur.searching ||
          prev.searchFailed != cur.searchFailed ||
          prev.searchQuery != cur.searchQuery,
      builder: (context, state) {
        if (state.searchResults.isNotEmpty) {
          return _Results(rows: state.searchResults);
        }
        if (state.searching) return const _Status(child: AppSpinner());
        if (state.searchFailed) {
          return const _Status(
            child: _StatusText(
              'We couldn\'t search right now — please see the front desk.',
            ),
          );
        }
        if (state.searchQuery.trim().length >= kKioskSearchMinChars) {
          return const _Status(
            child: _StatusText('No matches — please see the front desk.'),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _Results extends StatelessWidget {
  final List<MemberRow> rows;

  const _Results({required this.rows});

  @override
  Widget build(BuildContext context) {
    // The populated state's OWN top gap — never a parent spacing.
    return Padding(
      padding: const EdgeInsets.only(top: DesignConstants.spacingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          for (final row in rows)
            KioskNameRow(
              // The FULL name: two members sharing a first name must stay
              // distinguishable — an abbreviation collides silently.
              name: row.name,
              onTap: () => context.read<KioskFlowCubit>().selectMember(row),
            ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final Widget child;

  const _Status({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.spacingLarge),
      child: Center(child: child),
    );
  }
}

class _StatusText extends StatelessWidget {
  final String message;

  const _StatusText(this.message);

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: DesignConstants.kioskSectionText.copyWith(
        color: DesignConstants.text2nd,
      ),
      textAlign: TextAlign.center,
    );
  }
}
