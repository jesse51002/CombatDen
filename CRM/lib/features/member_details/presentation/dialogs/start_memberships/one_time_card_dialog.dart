import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_field_label.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_note.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_secure_strip.dart';

/// Collects a ONE-OFF card for the start wizard's one-time
/// charge. Tokenizes the card client-side and pops a
/// [CustomCardCapture] (pm id + brand/last-four) — it never
/// dispatches a bloc event and is **never saved as the
/// default**: the backend charges it once (attach → pay →
/// detach) for today's one-time purchase only.
///
/// It wears the update-card dialog's shape for the opposite reason: there the
/// consequence is that the card reaches every recurring membership, here it is
/// that the card reaches nothing but today. Both state it BEFORE the field,
/// because both are the whole decision — the card entry underneath is
/// identical either way, and a staff member who reads only the box cannot tell
/// the two apart.
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
        _error = _kReadFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return TaskDialog(
      what: _kWhat,
      onClose: _submitting ? null : () => Navigator.of(context).pop(),
      closeTooltip: _kClose,
      title: _kTitle,
      subtitle: _kSubtitle,
      body: TaskPanel(
        children: [
          const FlowInlineNotice(message: _kConsequence),
          const TaskFieldLabel(label: 'Card details', note: _kStripeNote),
          CardFieldBox(
            onComplete: (isComplete) {
              if (isComplete != _complete) {
                setState(() => _complete = isComplete);
              }
            },
          ),
          FlowSecureStrip(gymName: selectedGym.gymName),
          if (error != null)
            Text(
              error,
              style: DesignConstants.pSemibold.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
          const TaskNote(_kNotSaved),
        ],
      ),
      foot: TaskFoot(
        primaryLabel: _kUse,
        busy: _submitting,
        onPrimary: _complete && !_submitting ? _submit : null,
        secondaryLabel: _kCancel,
        onSecondary:
            _submitting ? null : () => Navigator.of(context).pop(),
      ),
    );
  }
}

const String _kWhat = 'Use a one-off card';
const String _kClose = 'Close without taking a card';
const String _kTitle = 'Charge a card just for today';
const String _kSubtitle = 'Nothing about the card on file changes.';
const String _kStripeNote = 'Handled by Stripe';
const String _kConsequence =
    'This card is charged once, for today\'s one-time purchases only. Every '
    'recurring membership keeps billing the card on file — this one never '
    'becomes the default and is never saved to a profile.';
const String _kNotSaved =
    'Tokenized on this gym\'s Stripe account, then dropped once today\'s '
    'charge goes through.';
const String _kUse = 'Use this card';
const String _kCancel = 'Cancel';
const String _kReadFailed =
    'We couldn\'t read that card. Check the details and try again.';
