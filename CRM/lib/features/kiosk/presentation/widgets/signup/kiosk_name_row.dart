import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One pickable person, as a plain centred name over a hairline.
///
/// It is the kiosk's ONE "choose a person from a list" row: the CRM name
/// search renders its results with it, and the payer picker renders the people
/// already on this signup with it too. Both lists therefore look and feel
/// identical, which is the point — "already here" and "someone else who trains
/// here" are two sources of the same kind of answer, not two kinds of control.
///
/// **Avatar-free, and that is deliberate**: a shared lobby iPad showing member
/// faces beside searchable names is a directory of everyone who trains here.
/// The FULL name is shown because two members sharing a first name and last
/// initial must stay distinguishable at the moment somebody taps one of them.
class KioskNameRow extends StatelessWidget {
  final String name;

  /// The quiet second line — a masked email, or what they are on this roster
  /// for. Null renders the name alone.
  final String? note;

  /// First in its list: no top hairline, so a list never opens on a rule.
  final bool first;

  final VoidCallback onTap;

  const KioskNameRow({
    super.key,
    required this.name,
    required this.first,
    required this.onTap,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final second = note;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(top: BorderSide(color: DesignConstants.lineSoft)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingLarge,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              name,
              style: DesignConstants.kioskName,
              textAlign: TextAlign.center,
            ),
            if (second != null)
              Text(
                second,
                style: DesignConstants.kioskCaption.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
