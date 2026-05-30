import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// The employee's short bio. Width-capped so the line length stays readable
/// (~65–75 characters) instead of running the full width of the page.
class EmployeeAboutSection extends StatelessWidget {
  final String bio;

  const EmployeeAboutSection({super.key, required this.bio});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Text(
        bio,
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
      ),
    );
  }
}
