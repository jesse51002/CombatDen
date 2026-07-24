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
/// [forPayer] switches only what a picked row MEANS — the payer seat rather
/// than a payee on the roster — and the one line of copy that would otherwise
/// offer the wrong way out of an empty result.
///
/// [noMatchMessage] overrides that empty line for a screen where neither
/// shipped variant is true. The identify step is the case: nothing is seated
/// there yet, so "you can keep paying yourself" names a person who does not
/// exist.
class KioskMatchSearch extends StatefulWidget {
  /// Pick a PAYER rather than a payee.
  final bool forPayer;

  /// What to say when the search answered with nobody. Null keeps the shipped
  /// per-[forPayer] line.
  final String? noMatchMessage;

  /// The search box's placeholder. The default addresses somebody looking
  /// another person up; a screen where the member is looking for THEMSELVES
  /// passes its own.
  final String hintText;

  const KioskMatchSearch({
    super.key,
    this.forPayer = false,
    this.noMatchMessage,
    this.hintText = 'Start typing their name',
  });

  @override
  State<KioskMatchSearch> createState() => _KioskMatchSearchState();
}

class _KioskMatchSearchState extends State<KioskMatchSearch> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Seeded FROM state, so a screen re-entered with a query still standing
    // (the identify step after "no, that's not me") shows the box and the rows
    // agreeing with each other. Every route that OPENS a search clears the
    // query first, so this can never carry the previous person's typing.
    _controller = TextEditingController(
      text: context.read<KioskSignupCubit>().state.matchQuery,
    );
  }

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
          hintText: widget.hintText,
          textStyle: DesignConstants.kioskFieldText,
          // The kiosk lifts muted WORDS off `text3rd` for contrast at 2m.
          hintColor: DesignConstants.text2nd,
          onChanged: cubit.searchExistingPeople,
        ),
        _Results(
          forPayer: widget.forPayer,
          noMatchMessage: widget.noMatchMessage,
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  final bool forPayer;
  final String? noMatchMessage;

  const _Results({required this.forPayer, this.noMatchMessage});

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingMedium,
            children: [
              for (final match in state.matches)
                KioskNameRow(
                  // The FULL name: two members sharing a first name and last
                  // initial must stay distinguishable at the moment somebody
                  // taps one of them.
                  name: match.name,
                  onTap: () => forPayer
                      ? context.read<KioskSignupCubit>().pickPayerRow(match)
                      : context.read<KioskSignupCubit>().pickMatchRow(match),
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
              noMatchMessage ??
                  (forPayer
                      // A payer must already be a member here, so "add them as
                      // someone new" is not an answer on this screen.
                      ? 'No matches. You can keep paying yourself, or the '
                          'front desk can set this up.'
                      : 'No matches. Add them as someone new instead.'),
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
