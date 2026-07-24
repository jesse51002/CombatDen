import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_name_row.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Find an existing member by name — the other route into the E2 payee offer,
/// and the whole of the payer picker.
///
/// It is the shipped kiosk-home composition — `AppSearchBox` at kiosk scale
/// over plain, centred, avatar-free name rows — pointed at the SIGNUP cubit
/// instead of the check-in one, and driving the ONE debounced,
/// sequence-guarded search the cubit owns. There is no second search anywhere.
///
/// Avatar-free is not an oversight: a shared lobby iPad showing member faces
/// beside searchable names is a directory of everyone who trains here.
///
/// [forPayer] switches only what a picked row MEANS — the payer seat, gated on
/// the member having no card on file, rather than a payee on the roster — and
/// the one line of copy that would otherwise offer the wrong way out of an
/// empty result.
class KioskMatchSearch extends StatefulWidget {
  /// Pick a PAYER (gated) rather than a payee.
  final bool forPayer;

  const KioskMatchSearch({super.key, this.forPayer = false});

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
        _Results(forPayer: widget.forPayer),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  final bool forPayer;

  const _Results({required this.forPayer});

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
                KioskNameRow(
                  // The FULL name: two members sharing a first name and last
                  // initial must stay distinguishable at the moment somebody
                  // taps one of them.
                  name: state.matches[i].name,
                  first: i == 0,
                  onTap: () => forPayer
                      ? context.read<KioskSignupCubit>().pickPayerRow(
                            state.matches[i],
                          )
                      : context.read<KioskSignupCubit>().pickMatchRow(
                            state.matches[i],
                          ),
                ),
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
          return _Status(
            child: _StatusText(
              forPayer
                  // A payer must already be a member here, so "add them as
                  // someone new" is not an answer on this screen.
                  ? 'No matches. You can keep paying yourself, or the front '
                      'desk can set this up.'
                  : 'No matches. Add them as someone new instead.',
            ),
          );
        }
        return const SizedBox.shrink();
      },
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
