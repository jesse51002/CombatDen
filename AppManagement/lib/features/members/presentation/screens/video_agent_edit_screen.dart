import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_video_agent.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/video_agent/agent_input_bar.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/video_agent/agent_message_bubble.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/video_agent/choice_answer_card.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/video_agent/search_preview_card.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/video_agent/user_message_bubble.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/videos_descriptions_section.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';

/// Agentic edit experience for the video feed. Visual-only: the agent
/// walks the gym-brief interview, then shows the re-derived content focus
/// and the regenerated searches it will run to refill the feed.
class VideoAgentEditScreen extends StatelessWidget {
  const VideoAgentEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              const _Header(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: DesignConstants.spacingLarge,
                    children: [
                      for (final turn in kMockAgentConversation)
                        switch (turn) {
                          AgentPrompt() => AgentMessageBubble(text: turn.text),
                          TextAnswer() => UserMessageBubble(text: turn.text),
                          ChoiceAnswer() => ChoiceAnswerCard(answer: turn),
                        },
                      const VideosDescriptionsSection(),
                      const SearchPreviewCard(),
                      AppPrimaryButton(
                        text: 'Approve & refresh feed',
                        fullWidth: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
              const AgentInputBar(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Icon(
            Symbols.arrow_back_sharp,
            color: DesignConstants.text,
            weight: DesignConstants.iconWeight,
          ),
        ),
        Text('Edit with Agent', style: DesignConstants.h1),
      ],
    );
  }
}
