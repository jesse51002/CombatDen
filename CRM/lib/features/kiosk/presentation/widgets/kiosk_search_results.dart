import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The name-search results — plain, centered name rows (deliberately NO
/// avatars/photos). Also renders the searching / no-match / failed states.
/// Tapping a name hands off to the class pick via [KioskFlowCubit.selectMember].
///
/// Every populated state carries its OWN top gap and the resting state is a
/// true zero-height box, so an empty result list adds nothing to the search
/// half — that is what keeps the field on the QR's optical centre at rest
/// (see [KioskNameSearch]). Never re-introduce the gap as a parent column
/// spacing: that would reserve it even when this renders nothing.
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
    return Padding(
      padding: const EdgeInsets.only(top: DesignConstants.spacingLarge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++)
            _NameRow(row: rows[i], first: i == 0),
        ],
      ),
    );
  }
}

class _NameRow extends StatelessWidget {
  final MemberRow row;
  final bool first;

  const _NameRow({required this.row, required this.first});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.read<KioskFlowCubit>().selectMember(row),
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(top: BorderSide(color: DesignConstants.lineSoft)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingLarge,
        ),
        child: Text(
          // The member's FULL name — two members who share a first name + last
          // initial must stay distinguishable at the moment they tap to check
          // in (a first-initial abbreviation collides silently).
          row.name,
          style: DesignConstants.kioskName,
          textAlign: TextAlign.center,
        ),
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
