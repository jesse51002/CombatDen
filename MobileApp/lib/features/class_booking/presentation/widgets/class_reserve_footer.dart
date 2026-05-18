import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// Footer with a top divider and the primary "Reserve your spot" CTA.
class ClassReserveFooter extends StatelessWidget {
  const ClassReserveFooter({super.key, required this.onReserve});

  final VoidCallback onReserve;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionDivider(),
        Padding(
          padding: EdgeInsets.all(DesignConstants.paddingBig),
          child: AppPrimaryButton(
            text: 'Reserve your spot',
            onPressed: onReserve,
            fullWidth: true,
            borderRadius: DesignConstants.radiusBig,
          ),
        ),
      ],
    );
  }
}
