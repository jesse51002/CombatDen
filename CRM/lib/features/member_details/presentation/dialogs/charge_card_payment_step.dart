import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/one_time_card_section.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/saved_card_section.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// The charge dialog's payment step: the amount + reason, then the
/// card to bill — the payer's saved default (with edit / set-new-
/// default) OR a one-off card just for this charge. Card selection
/// is deliberately its own concern, separate from who is paying.
class ChargeCardPaymentStep extends StatelessWidget {
  final String beneficiaryName;

  /// The payer's saved default card (driven from bloc state so an
  /// edit re-renders the new card automatically), or null when none.
  final CardOnFile? cardOnFile;

  /// A one-off card captured for this charge (null = bill the saved
  /// default).
  final CustomCardCapture? customCard;

  final TextEditingController amountController;
  final TextEditingController descriptionController;
  final String? error;

  /// When true the charge is settled out of band (cash) — no card is
  /// charged, so the card options are hidden.
  final bool paidCash;
  final ValueChanged<bool> onPaidCashChanged;

  /// Opens the saved-default-card editor (sets a new card on file).
  final VoidCallback onEditCardOnFile;
  final VoidCallback onAddOrChangeCustomCard;
  final VoidCallback onRemoveCustomCard;

  const ChargeCardPaymentStep({
    super.key,
    required this.beneficiaryName,
    required this.cardOnFile,
    required this.customCard,
    required this.amountController,
    required this.descriptionController,
    required this.error,
    required this.paidCash,
    required this.onPaidCashChanged,
    required this.onEditCardOnFile,
    required this.onAddOrChangeCustomCard,
    required this.onRemoveCustomCard,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'One-time charge for $beneficiaryName.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
          ),
        ),
        CustomTextField(
          controller: amountController,
          label: 'Amount (USD)',
          hintText: '50.00',
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'[0-9.,$]'),
            ),
          ],
        ),
        CustomTextField(
          controller: descriptionController,
          label: 'Reason',
          hintText: 'Private session',
        ),
        SwitchListTile(
          value: paidCash,
          onChanged: onPaidCashChanged,
          activeThumbColor: DesignConstants.primaryColor,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Paid in cash (no card charge)',
            style: DesignConstants.p,
          ),
          subtitle: Text(
            'Record this as settled out of band — no card is '
            'charged.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
        if (!paidCash) ...[
          SavedCardSection(
            cardOnFile: cardOnFile,
            hasRecurring: false,
            onAddOrEdit: onEditCardOnFile,
          ),
          OneTimeCardSection(
            customCard: customCard,
            onAddOrChange: onAddOrChangeCustomCard,
            onRemove: onRemoveCustomCard,
          ),
        ],
        if (error != null)
          Text(
            error!,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
      ],
    );
  }
}
