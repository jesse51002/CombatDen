import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_bloc.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_event.dart';
import 'package:mobile_app/features/class_booking/bloc/booking_state.dart';
import 'package:theme_flutter/theme/theme_text.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';
import 'package:mobile_app/shared/widgets/error_message.dart';

/// Footer CTA for the class detail — reserve when not booked, cancel (with a
/// confirm step) when booked. A full class and other 4xx surface as a designed
/// inline error above the button; reserve / cancel success are handled by the
/// screen's listeners (navigate to the booked screen / show a confirmation).
///
/// The footer is the ACTION half of the screen's reservation story; the
/// affirmative "you hold this" half is [ClassReservedTag] up in the meta
/// block. Cancel is deliberately the only thing down here — a status line
/// beside it would just restate what the tag already said.
class ClassBookingFooter extends StatelessWidget {
  const ClassBookingFooter({super.key, this.buttonKey});

  final Key? buttonKey;

  Future<void> _confirmCancel(BuildContext context) async {
    final bloc = context.read<BookingBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancel reservation?', style: DesignConstants.h2),
        content: Text(
          'You can book this class again later if you change your mind.',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep it', style: DesignConstants.h3),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Cancel reservation',
              style: DesignConstants.h3.copyWith(color: DesignConstants.badRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) bloc.add(const BookingCancelRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BookingBloc, BookingState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionDivider(),
            if (state.status == BookingStatus.error)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  DesignConstants.paddingBig,
                  DesignConstants.spacingLarge,
                  DesignConstants.paddingBig,
                  0,
                ),
                // One source of copy: the bloc already resolved the backend's
                // machine-readable `code` to member-facing wording
                // (BookingRejection), so the footer never re-decides what a
                // rejection says.
                child: ErrorMessage(
                  message: state.errorMessage ??
                      'Something went wrong. Please try again.',
                ),
              ),
            Padding(
              padding: EdgeInsets.all(DesignConstants.paddingBig),
              child: KeyedSubtree(
                key: buttonKey,
                child: _CtaButton(state: state, onCancel: _confirmCancel),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.state, required this.onCancel});

  final BookingState state;
  final Future<void> Function(BuildContext) onCancel;

  @override
  Widget build(BuildContext context) {
    if (state.booked) {
      final cancelling = state.status == BookingStatus.cancelling;
      return AppOutlineButton(
        text: cancelling ? 'Cancelling…' : 'Cancel reservation',
        fullWidth: true,
        borderRadius: DesignConstants.radiusBig,
        borderColor: DesignConstants.badRed,
        textColor: DesignConstants.badRed,
        onPressed: state.isBusy ? null : () => onCancel(context),
      );
    }
    final reserving = state.status == BookingStatus.reserving;
    return AppPrimaryButton(
      text: reserving
          ? 'Reserving…'
          : ThemeText.value(
              CombatDenSlots.reserveCta,
              fallback: 'Reserve your spot',
            ),
      fullWidth: true,
      borderRadius: DesignConstants.radiusBig,
      onPressed: state.isBusy
          ? null
          : () => context.read<BookingBloc>().add(
                const BookingReserveRequested(),
              ),
    );
  }
}
