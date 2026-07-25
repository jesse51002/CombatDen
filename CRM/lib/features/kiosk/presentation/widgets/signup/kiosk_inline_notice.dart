import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';

/// The signup lane's ONE inline notice: important, neutral, not the member's
/// fault, and not a dead end. It wears the warm stop palette rather than red,
/// and is the shape every "you should know this before you carry on" line
/// takes — the waiver's republished-version warning, the payer picker's
/// redirect, the card step's "this replaces the card on your profile".
///
/// Its weight is the point: [DesignConstants.kioskBody] on a warm fill
/// out-weighs the ticked facts below it, prominent without alarm language, a
/// red treatment, or a modal.
class KioskInlineNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const KioskInlineNotice({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.info_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.okYellow,
          ),
          Expanded(
            child: Text(message, style: DesignConstants.kioskBody),
          ),
          if (retry != null)
            KioskOutlineButton(text: 'Try again', onPressed: retry),
        ],
      ),
    );
  }
}
