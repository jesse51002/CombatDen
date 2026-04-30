import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';

/// Static chart visual for Members-over-time. The line itself is a
/// pre-rendered Figma bitmap (prototype only — when this graduates,
/// swap to a real chart library). Y-axis tick labels and X-axis month
/// labels are real Flutter widgets so they re-flow with the design
/// system.
class MembersTrendChart extends StatelessWidget {
  const MembersTrendChart({super.key});

  static const double _chartHeight = 200;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        _ChartBody(),
        _XAxisLabels(),
      ],
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(
          child: SizedBox(
            height: MembersTrendChart._chartHeight,
            child: Image.asset(
              'assets/images/growth_members_chart.png',
              fit: BoxFit.fill,
            ),
          ),
        ),
        SizedBox(
          height: MembersTrendChart._chartHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final tick in kMockMembersTrendYTicks)
                Text(
                  '$tick -',
                  style: DesignConstants.h2.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _XAxisLabels extends StatelessWidget {
  const _XAxisLabels();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final label in kMockMembersTrendXLabels)
          Text(
            label,
            textAlign: TextAlign.center,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}
