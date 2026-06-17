import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Collects a ONE-OFF card for the start wizard's one-time
/// charge. Tokenizes the card client-side and pops a
/// [CustomCardCapture] (pm id + brand/last-four) — it never
/// dispatches a bloc event and is **never saved as the
/// default**: the backend charges it once (attach → pay →
/// detach) for today's one-time purchase only. Saving a
/// default card is the separate "Edit card on file" flow.
class OneTimeCardDialog extends StatefulWidget {
  const OneTimeCardDialog({super.key});

  static Future<CustomCardCapture?> show({
    required BuildContext context,
  }) {
    return showDialog<CustomCardCapture>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const OneTimeCardDialog(),
    );
  }

  @override
  State<OneTimeCardDialog> createState() =>
      _OneTimeCardDialogState();
}

class _OneTimeCardDialogState
    extends State<OneTimeCardDialog> {
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
      final pm = await Stripe.instance.createPaymentMethod(
        params: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        CustomCardCapture(
          pmId: pm.id,
          brand: pm.card.brand ?? 'Card',
          lastFour: pm.card.last4 ?? '••••',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'We couldn’t read that card. Check the '
            'details and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      showCloseButton: !_submitting,
      title: 'Use a one-off card',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'This card is charged once for today’s one-time '
            'purchase only. It is NOT saved and does not '
            'change the card on file — recurring memberships '
            'keep billing the saved card. Card details go '
            'straight to Stripe.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
          CardFieldBox(
            onComplete: (isComplete) {
              if (isComplete != _complete) {
                setState(() => _complete = isComplete);
              }
            },
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
        primaryLabel: 'Use this card',
        isLoading: _submitting,
        primaryOnPressed:
            _complete && !_submitting ? _submit : null,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: _submitting
            ? null
            : () => Navigator.of(context).pop(),
      ),
    );
  }
}
