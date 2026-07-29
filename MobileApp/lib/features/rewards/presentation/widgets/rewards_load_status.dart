import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/loading_dots.dart';

/// Loading (null [message]) / error / empty chrome for a rewards grid that
/// loads from the VideoService, shared by the Points Store and My Rewards.
class RewardsLoadStatus extends StatelessWidget {
  const RewardsLoadStatus(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? const LoadingDots()
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
