import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Collects new card details via the Stripe [CardField]
/// (web-supported), tokenizes them into a Stripe
/// PaymentMethod client-side, and dispatches
/// [UpdateCardRequested] with the resulting
/// `payment_method_id` — the backend never sees raw PAN.
///
/// The request body the bloc builds is a
/// [MembersManagementUpdateCardRequest]; this dialog only
/// produces the `payment_method_id` it carries.
///
/// When a [card] is already on file the dialog shows its
/// summary and a destructive "Remove card" action. Removal
/// isn't handled here — tapping it pops `true` so the
/// caller can run the existing confirmation flow against a
/// still-mounted page context.
class UpdateCardDialog extends StatefulWidget {
  final String memberName;
  final CardOnFile? card;

  const UpdateCardDialog({
    super.key,
    required this.memberName,
    this.card,
  });

  /// Resolves `true` only when the user taps "Remove card";
  /// `false` on save, cancel, or dismiss.
  static Future<bool> show({
    required BuildContext context,
    required String memberName,
    CardOnFile? card,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: UpdateCardDialog(
          memberName: memberName,
          card: card,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  State<UpdateCardDialog> createState() =>
      _UpdateCardDialogState();
}

class _UpdateCardDialogState extends State<UpdateCardDialog> {
  bool _complete = false;
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (!_complete || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final paymentMethod =
          await Stripe.instance.createPaymentMethod(
        params: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      if (!mounted) return;
      context.read<MemberDetailBloc>().add(
            UpdateCardRequested(paymentMethod.id),
          );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error =
            'We couldn’t save that card. Check the details '
            'and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return AppDialog(
      showCloseButton: !_submitting,
      title: card == null ? 'Add card' : 'Update card',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          if (card != null) _CurrentCardLine(card: card),
          Text(
            card == null
                ? 'Enter a card for ${widget.memberName}. '
                    'Card details go straight to Stripe and '
                    'are never stored on our servers.'
                : 'Enter a new card to replace the saved one '
                    'for ${widget.memberName}. Card details '
                    'go straight to Stripe and are never '
                    'stored on our servers.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusBig,
              ),
              border: Border.all(
                color: DesignConstants.text,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.spacingMedium,
              ),
              child: CardField(
                enablePostalCode: true,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text,
                ),
                onCardChanged: (details) {
                  final isComplete =
                      details?.complete ?? false;
                  if (isComplete != _complete) {
                    setState(() => _complete = isComplete);
                  }
                },
              ),
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Save card',
        isLoading: _submitting,
        primaryOnPressed:
            _complete && !_submitting ? _submit : null,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: _submitting
            ? null
            : () => Navigator.of(context).pop(),
        destructiveLabel: card == null ? null : 'Remove card',
        destructiveOnPressed: _submitting
            ? null
            : () => Navigator.of(context).pop(true),
      ),
    );
  }
}

/// Read-only summary of the card currently on file, shown
/// above the new-card field when replacing an existing card.
class _CurrentCardLine extends StatelessWidget {
  final CardOnFile card;

  const _CurrentCardLine({required this.card});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Current card  ',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          TextSpan(
            text: '${card.brand} ···· ${card.lastFour} · '
                'Expires ${card.expMonth}/${card.expYear}',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
        ],
      ),
    );
  }
}
