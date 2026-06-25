import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Whose invoice this is — a small avatar (the member's photo, or their
/// initial when there's none) plus their name, optionally over a muted
/// eyebrow caption ("Billed to"). Rendered at the top of an
/// [InvoiceBreakdown] so every invoice display says who it belongs to —
/// the same person + photo treatment used across the member-detail billing
/// surfaces.
class InvoiceAttribution extends StatelessWidget {
  final String name;
  final String? photoUrl;

  /// Optional muted eyebrow above the name (e.g. "Billed to"). Omitted
  /// when null — some surfaces label the section themselves.
  final String? caption;

  const InvoiceAttribution({
    super.key,
    required this.name,
    this.photoUrl,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        CircleAvatar(
          radius: DesignConstants.iconSizeMedium,
          backgroundColor: DesignConstants.backgroundColor,
          backgroundImage:
              url != null ? NetworkImage(url) : null,
          child: url == null
              ? Text(
                  initial,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                )
              : null,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingTiny,
            children: [
              if (caption != null)
                Text(
                  caption!,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              Text(
                name,
                style: DesignConstants.h3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
