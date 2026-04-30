import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/gym_type/gym_type_option.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// "Gym Type" card — the admin picks which discipline reskins the
/// member-facing app (cage / mat / ring / dojo).
class GymTypeCard extends StatelessWidget {
  final GymType selected;

  const GymTypeCard({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingBig,
        vertical: DesignConstants.paddingBig,
      ),
      child: Column(
        spacing: DesignConstants.spacingBig,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              'Gym Type',
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                Expanded(
                  child: GymTypeOption(
                    label: 'MMA',
                    iconAsset: 'assets/images/gym_type_mma.png',
                    selected: selected == GymType.mma,
                    onTap: () => debugPrint('TODO: in-preview action'),
                  ),
                ),
                Expanded(
                  child: GymTypeOption(
                    label: 'Judo / BJJ',
                    iconAsset: 'assets/images/gym_type_judo_bjj.png',
                    selected: selected == GymType.judoBjj,
                    onTap: () => debugPrint('TODO: in-preview action'),
                  ),
                ),
                Expanded(
                  child: GymTypeOption(
                    label: 'Boxing / Kickboxing',
                    iconAsset: 'assets/images/gym_type_boxing.png',
                    selected: selected == GymType.boxingKickboxing,
                    onTap: () => debugPrint('TODO: in-preview action'),
                  ),
                ),
                Expanded(
                  child: GymTypeOption(
                    label: 'Karate / Taekawdo',
                    iconAsset: 'assets/images/gym_type_karate.png',
                    selected: selected == GymType.karateTaekwondo,
                    onTap: () => debugPrint('TODO: in-preview action'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
