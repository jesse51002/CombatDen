import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
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

  /// The member whose saved card this edits. Null targets
  /// the currently viewed member; the start-memberships
  /// wizard sets it to the payer so the card is editable
  /// from any launching page.
  final String? targetMemberId;

  /// Whether to offer the destructive "Remove card" action.
  /// True on the member profile (the management surface);
  /// false in checkout flows (start / charge), where removing
  /// a card mid-purchase makes no sense — removal lives on the
  /// profile, behind its own confirmation.
  final bool allowRemove;

  const UpdateCardDialog({
    super.key,
    required this.memberName,
    this.card,
    this.targetMemberId,
    this.allowRemove = true,
  });

  /// Resolves `true` only when the user taps "Remove card";
  /// `false` on save, cancel, or dismiss.
  static Future<bool> show({
    required BuildContext context,
    required String memberName,
    CardOnFile? card,
    String? targetMemberId,
    bool allowRemove = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: UpdateCardDialog(
          memberName: memberName,
          card: card,
          targetMemberId: targetMemberId,
          allowRemove: allowRemove,
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
            UpdateCardRequested(
              paymentMethod.id,
              targetMemberId: widget.targetMemberId,
            ),
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
          _RecurringImpactWarning(
            memberName: widget.memberName,
            replacing: card != null,
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
        primaryLabel: 'Save card',
        isLoading: _submitting,
        primaryOnPressed:
            _complete && !_submitting ? _submit : null,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: _submitting
            ? null
            : () => Navigator.of(context).pop(),
        destructiveLabel: (card == null || !widget.allowRemove)
            ? null
            : 'Remove card',
        destructiveOnPressed:
            (_submitting || !widget.allowRemove)
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

/// Spells out the global side effect of saving a card: it becomes the
/// member's DEFAULT, so every recurring membership they have bills to it —
/// not a one-off for a single purchase.
class _RecurringImpactWarning extends StatelessWidget {
  final String memberName;
  final bool replacing;

  const _RecurringImpactWarning({
    required this.memberName,
    required this.replacing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.okYellow),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            Symbols.warning_sharp,
            size: DesignConstants.iconSizeSmall,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.okYellow,
          ),
          Expanded(
            child: Text(
              replacing
                  ? 'This is $memberName’s saved DEFAULT card. '
                      'Saving a new one re-bills EVERY recurring '
                      'membership they have to it going forward '
                      '— it’s not a one-off for a single charge.'
                  : 'This becomes $memberName’s saved DEFAULT '
                      'card — every recurring membership they '
                      'have bills to it going forward, not just '
                      'one charge.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
