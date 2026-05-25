import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_video_agent.dart';

/// Renders a selection answer the way the agent asks it: the offered
/// options as chips, the admin's picks filled in. Right-aligned, like the
/// admin's other replies.
class ChoiceAnswerCard extends StatelessWidget {
  final ChoiceAnswer answer;

  const ChoiceAnswerCard({super.key, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          decoration: BoxDecoration(
            color: DesignConstants.primaryColor10,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: DesignConstants.spacingMedium,
            children: [
              Text(
                answer.multiSelect ? 'Selected all that apply' : 'Selected',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: DesignConstants.spacingSmall,
                runSpacing: DesignConstants.spacingSmall,
                children: [
                  for (final option in answer.options) _OptionChip(option),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final ChoiceOption option;

  const _OptionChip(this.option);

  @override
  Widget build(BuildContext context) {
    final selected = option.selected;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: selected ? DesignConstants.primaryColor : Colors.transparent,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(
          color: selected
              ? DesignConstants.primaryColor
              : DesignConstants.text3rd,
          width: DesignConstants.buttonBorderSize,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            selected
                ? Symbols.check_circle_sharp
                : Symbols.radio_button_unchecked_sharp,
            color: selected
                ? DesignConstants.backgroundColor
                : DesignConstants.text3rd,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeSmall,
          ),
          Text(
            option.label,
            style: DesignConstants.p.copyWith(
              color: selected
                  ? DesignConstants.backgroundColor
                  : DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
