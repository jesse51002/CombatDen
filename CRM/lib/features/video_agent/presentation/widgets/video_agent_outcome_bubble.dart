import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/video_agent/data/models/video_agent_models.dart';

/// In-chat outcome card for a proposed spec — the conversation record of an
/// Accept or a dismiss. [ChatMessageStatus.saved] reads green with a check;
/// [ChatMessageStatus.rejected] reads neutral with a cancel mark.
class VideoAgentOutcomeBubble extends StatelessWidget {
  final String text;
  final ChatMessageStatus status;

  const VideoAgentOutcomeBubble({
    super.key,
    required this.text,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      ChatMessageStatus.saved => DesignConstants.goodGreen,
      ChatMessageStatus.error => DesignConstants.badRed,
      _ => DesignConstants.text3rd,
    };
    final IconData icon = switch (status) {
      ChatMessageStatus.saved => Symbols.check_circle_sharp,
      ChatMessageStatus.error => Symbols.error_sharp,
      _ => Symbols.cancel_sharp,
    };
    // Saved/error read in their own colour; a neutral dismissal keeps the label
    // legible in the secondary text colour rather than the faint marker grey.
    final Color textColor = status == ChatMessageStatus.saved ||
            status == ChatMessageStatus.error
        ? color
        : DesignConstants.text2nd;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingMedium,
            children: [
              Icon(
                icon,
                size: DesignConstants.iconSizeMedium,
                color: color,
                weight: DesignConstants.iconWeight,
              ),
              Flexible(
                child: Text(
                  text,
                  style: DesignConstants.h3Regular.copyWith(color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
