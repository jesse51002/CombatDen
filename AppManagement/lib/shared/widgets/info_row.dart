import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

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

  void _launchLink() {
    if (value == null || linkType == null) return;
    debugPrint(
      'TODO: launch ${linkType!.name} link "$value" '
      '(url_launcher not wired in this prototype)',
    );
  }
}

/// The type of link for an [InfoRow] value.
enum InfoRowLinkType { phone, email }
