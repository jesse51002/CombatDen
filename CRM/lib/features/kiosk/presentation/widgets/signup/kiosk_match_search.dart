import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The other route into the E2 offer: find the existing member by name.
///
/// It is the shipped kiosk-home composition — `AppSearchBox` at kiosk scale
/// over plain, centred, avatar-free name rows — pointed at the SIGNUP cubit
/// instead of the check-in one. Picking a row lands on the same confirm card
/// the 409 route lands on, so both ways in end in the same decision.
///
/// Avatar-free is not an oversight: a shared lobby iPad showing member faces
/// beside searchable names is a directory of everyone who trains here.
class KioskMatchSearch extends StatefulWidget {
  const KioskMatchSearch({super.key});

  @override
  State<KioskMatchSearch> createState() => _KioskMatchSearchState();
}

class _KioskMatchSearchState extends State<KioskMatchSearch> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        AppSearchBox(
          controller: _controller,
          hintText: 'Start typing their name',
          textStyle: DesignConstants.kioskFieldText,
          // The kiosk lifts muted WORDS off `text3rd` for contrast at 2m.
          hintColor: DesignConstants.text2nd,
          onChanged: cubit.searchExistingPeople,
        ),
        const _Results(),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.matches != cur.matches ||
          prev.matchSearching != cur.matchSearching ||
          prev.matchSearchFailed != cur.matchSearchFailed ||
          prev.matchQuery != cur.matchQuery,
      builder: (context, state) {
        if (state.matches.isNotEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < state.matches.length; i++)
                _NameRow(row: state.matches[i], first: i == 0),
            ],
          );
        }
        if (state.matchSearching) return const _Status(child: AppSpinner());
        if (state.matchSearchFailed) {
          return const _Status(
            child: _StatusText(
              'We couldn\'t search right now — please see the front desk.',
            ),
          );
        }
        if (state.matchQuery.trim().length >= kKioskSearchMinChars) {
          return const _Status(
            child: _StatusText(
              'No matches. Add them as someone new instead.',
            ),
          );
        }
        return const SizedBox.shrink();
      },
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
      onTap: () => context.read<KioskSignupCubit>().pickMatchRow(row),
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
          // The FULL name: two members sharing a first name and last initial
          // must stay distinguishable at the moment someone taps one of them.
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
