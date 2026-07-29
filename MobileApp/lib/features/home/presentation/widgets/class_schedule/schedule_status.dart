import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Centered loading spinner / message shown in place of the day list while
/// the class cards load (or when none are available).
class ScheduleStatus extends StatelessWidget {
  const ScheduleStatus({super.key, this.loading = false, this.message});

  final bool loading;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Text(
                message ?? '',
                textAlign: TextAlign.center,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
      ),
    );
  }
}
