import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/member_app/video_agent/user_message_bubble.dart';

/// The owner's answer to a multi-choice question, rendered right-aligned: the
/// question's options shown read-only with the selected ones highlighted.
///
/// When the owner typed a custom reply instead (no selection), the options show
/// none-selected and the typed [text] appears below them.
class VideoAgentAnswerBubble extends StatelessWidget {
  final List<String> options;
  final List<String> selectedOptions;
  final String text;

  const VideoAgentAnswerBubble({
    super.key,
    required this.options,
    required this.selectedOptions,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final typed = selectedOptions.isEmpty && text.isNotEmpty;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: DesignConstants.spacingSmall,
          children: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: DesignConstants.spacingSmall,
              runSpacing: DesignConstants.spacingSmall,
              children: [
                for (final option in options)
                  _AnswerChip(
                    label: option,
                    selected: selectedOptions.contains(option),
                  ),
              ],
            ),
            if (typed) UserMessageBubble(text: text),
          ],
        ),
      ),
    );
  }
}

/// One read-only chip: highlighted (accent fill + check) when selected,
/// dimmed (card fill + hollow ring) when not.
class _AnswerChip extends StatelessWidget {
  final String label;
  final bool selected;

  const _AnswerChip({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: selected ? DesignConstants.primaryColor : DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(
          color:
              selected ? DesignConstants.primaryColor : DesignConstants.line,
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
            size: DesignConstants.iconSizeSmall,
            weight: DesignConstants.iconWeight,
            color: selected
                ? DesignConstants.onAccent
                : DesignConstants.text3rd,
          ),
          Text(
            label,
            style: DesignConstants.p.copyWith(
              color: selected
                  ? DesignConstants.onAccent
                  : DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
