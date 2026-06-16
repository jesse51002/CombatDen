import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Collects a one-off card for the start wizard's one-time
/// charge. Tokenizes the card client-side and pops a
/// [CustomCardCapture] (pm id + brand/last-four + the
/// save-as-default choice) — it never dispatches a bloc
/// event, so the card is not saved unless the caller, after a
/// successful charge, acts on [CustomCardCapture.setAsDefault].
///
/// When the payer has no card on file ([forceDefault]) the
/// save-as-default choice is hidden and forced on — a
/// one-time-only purchase with no saved card must leave one.
class OneTimeCardDialog extends StatefulWidget {
  final bool forceDefault;

  const OneTimeCardDialog({
    super.key,
    required this.forceDefault,
  });

  static Future<CustomCardCapture?> show({
    required BuildContext context,
    required bool forceDefault,
  }) {
    return showDialog<CustomCardCapture>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          OneTimeCardDialog(forceDefault: forceDefault),
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
  late bool _setAsDefault = widget.forceDefault;

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
          setAsDefault: _setAsDefault,
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
      title: 'Use a different card',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            widget.forceDefault
                ? 'This card is charged once for today’s '
                    'one-time purchase and saved as the '
                    'default card. Card details go straight '
                    'to Stripe.'
                : 'This card is charged once for today’s '
                    'one-time purchase. Card details go '
                    'straight to Stripe and are never '
                    'stored on our servers.',
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
          if (!widget.forceDefault)
            _SetDefaultToggle(
              value: _setAsDefault,
              onChanged: (v) =>
                  setState(() => _setAsDefault = v),
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

/// "Save as default" switch, shown only when the payer
/// already has a card on file (otherwise the card is forced
/// to become the default and the choice is hidden).
class _SetDefaultToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SetDefaultToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: DesignConstants.primaryColor,
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Save as the default card',
        style: DesignConstants.p,
      ),
      subtitle: Text(
        'Replaces the card on file after this purchase '
        'succeeds; future recurring cycles use it.',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
    );
  }
}
