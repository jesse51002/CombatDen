import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A label: value row used across detail screens.
///
/// Supports optional link styling for phone/email values.
class InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final InfoRowLinkType? linkType;
  final TextStyle? textStyle;

  const InfoRow({
    super.key,
    required this.label,
    this.value,
    this.linkType,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value ?? '—';
    final style = textStyle ?? DesignConstants.p;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: style.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Expanded(
          child: linkType != null && value != null
              ? _buildLink(displayValue, style)
              : Text(
                  displayValue,
                  style: style,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }

  Widget _buildLink(String text, TextStyle style) {
    return GestureDetector(
      onTap: () => _launchLink(),
      child: Text(
        text,
        style: style.copyWith(
          color: DesignConstants.hyperlink,
          decoration: TextDecoration.underline,
          decorationColor: DesignConstants.hyperlink,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _launchLink() async {
    if (value == null) return;

    final Uri uri;
    switch (linkType) {
      case InfoRowLinkType.phone:
        uri = Uri(scheme: 'tel', path: value);
      case InfoRowLinkType.email:
        uri = Uri(scheme: 'mailto', path: value);
      case null:
        return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

/// The type of link for an [InfoRow] value.
enum InfoRowLinkType { phone, email }
