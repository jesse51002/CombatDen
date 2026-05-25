import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/screens/video_agent_edit_screen.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/content_focus_cards.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// Top card of the Videos tab: the current content focus (We surface /
/// We avoid, side by side) with the agent-edit call to action filling
/// the width beneath it.
class EditAndFocusCard extends StatelessWidget {
  const EditAndFocusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: const [_FocusPanel(), _EditPanel()],
      ),
    );
  }
}

class _FocusPanel extends StatelessWidget {
  const _FocusPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Content focus', style: DesignConstants.h1),
        const ContentFocusCards(),
      ],
    );
  }
}

class _EditPanel extends StatelessWidget {
  const _EditPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              Symbols.auto_awesome_sharp,
              color: DesignConstants.primaryColor,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeBig,
            ),
            Text('Edit with Agent', style: DesignConstants.h2),
          ],
        ),
        Text(
          'Editing the feed is a conversation, not a form. The agent asks '
          'about your gym, rewrites the content focus, and regenerates the '
          'searches that pull videos so the feed always matches what you '
          'actually teach.',
          style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
        ),
        AppPrimaryButton(
          text: 'Start editing',
          fullWidth: true,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const VideoAgentEditScreen(),
            ),
          ),
        ),
      ],
    );
  }
}
