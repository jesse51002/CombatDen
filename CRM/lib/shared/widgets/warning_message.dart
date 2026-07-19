import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Inline warning banner — the cautionary sibling of
/// [ErrorMessage] (`error_message.dart`): same tinted-row
/// shape, in the `okYellow` warning palette with a warning
/// icon. For prominent heads-ups that aren't failures
/// (e.g. "the card will be charged twice today").
///
/// Pass [title] for a two-line heads-up: a heavier title line
/// above the [message] body. With no [title] it renders a single
/// centered message line (existing call sites are unchanged).
class WarningMessage extends StatelessWidget {
  final String message;
  final String? title;

  const WarningMessage({
    super.key,
    required this.message,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.okYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: DesignConstants.okYellow.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          crossAxisAlignment: title == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              Symbols.warning_sharp,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.okYellow,
              weight: DesignConstants.iconWeight,
            ),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final body = Text(
      message,
      style: DesignConstants.p.copyWith(
        color: DesignConstants.okYellow,
      ),
    );
    if (title == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          title!,
          style: DesignConstants.pSemibold.copyWith(
            color: DesignConstants.okYellow,
          ),
        ),
        body,
      ],
    );
  }
}
