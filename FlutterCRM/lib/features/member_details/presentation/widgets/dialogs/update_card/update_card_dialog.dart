import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/update_card/stripe_card_split_field.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Adds or replaces the paying account's saved card.
///
/// Collects card details via three separate Stripe
/// Elements (number, expiry, CVC), tokenises them against
/// the publishable key, and dispatches
/// [UpdateCardRequested] with the resulting payment
/// method id. Raw card details never touch our backend.
class UpdateCardDialog extends StatefulWidget {
  final CardOnFile? existingCard;

  const UpdateCardDialog({
    super.key,
    this.existingCard,
  });

  static Future<void> show({
    required BuildContext context,
    CardOnFile? existingCard,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: UpdateCardDialog(existingCard: existingCard),
      ),
    );
  }

  @override
  State<UpdateCardDialog> createState() =>
      _UpdateCardDialogState();
}

class _UpdateCardDialogState extends State<UpdateCardDialog> {
  CardSplitStatus? _status;
  bool _submitting = false;
  String? _error;

  Future<void> _onConfirm() async {
    if (_submitting) return;
    if (_status?.complete != true) {
      setState(() {
        _error = 'Enter complete card details.';
      });
      return;
    }
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
    } on StripeException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.error.localizedMessage ??
            e.error.message ??
            'Stripe rejected the card.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not tokenise card: $e';
      });
    }
  }

  Future<void> _onUnlink() async {
    final existing = widget.existingCard;
    if (existing == null || _submitting) return;
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Unlink card',
      summary:
          'Removes ${_formatCard(existing)} from this '
          'account and cancels every active recurring '
          'membership on it.',
      effects: const [
        BillingEffect(
          icon: Symbols.credit_card_off_sharp,
          text: 'Saved card removed — future renewals '
              'will fail until a new card is added.',
        ),
        BillingEffect(
          icon: Symbols.cancel_sharp,
          text: 'Every active recurring membership on '
              'this account is cancelled immediately.',
        ),
      ],
      affected: const [],
      confirmLabel: 'Unlink Card',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    context
        .read<MemberDetailBloc>()
        .add(const UnlinkPaymentRequested());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existingCard;
    final isAdd = existing == null;
    return AppDialog(
      title: isAdd ? 'Add Card' : 'Update Card',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          if (existing != null)
            Text(
              'Replacing ${_formatCard(existing)}.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          StripeCardSplitField(
            onChanged: (status) =>
                setState(() => _status = status),
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
        destructiveLabel: existing == null
            ? null
            : 'Unlink Card (${existing.brand} '
                '••••${existing.lastFour})',
        destructiveOnPressed:
            _submitting ? null : _onUnlink,
        primaryLabel: _submitting
            ? 'Saving…'
            : (isAdd ? 'Add Card' : 'Save Card'),
        primaryOnPressed: _submitting ? null : _onConfirm,
        secondaryLabel: 'Cancel',
      ),
    );
  }

  String _formatCard(CardOnFile card) {
    final month = card.expMonth.toString().padLeft(2, '0');
    final year =
        card.expYear.toString().padLeft(4, '0').substring(2);
    return '${card.brand} •••• ${card.lastFour}'
        ' (exp $month/$year)';
  }
}
