import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Settings section that links to the video-feed configuration screen.
///
/// The owner taps "Configure video feed" to open [VideoConfigScreen], where
/// they chat with an agent to author their gym's keep/avoid criteria and
/// YouTube search queries.
class VideoConfigSettingsSection extends StatelessWidget {
  const VideoConfigSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Video feed config', style: DesignConstants.h1),
        const _Description(),
        AppPrimaryButton(
          text: 'Configure video feed',
          onPressed: () => Navigator.of(context).pushNamed(
            AppRoutes.videoConfig,
          ),
        ),
      ],
    );
  }
}

class _Description extends StatelessWidget {
  const _Description();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Chat with an AI agent to set the keep/avoid criteria and YouTube '
      'search queries that shape your members\' video feed. The agent '
      'proposes a config you review and confirm before it takes effect.',
      style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
    );
  }
}
