import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/shared/widgets/view_switcher.dart';

/// The right pane of the agent view: the full feed prompt for the selected
/// gym, rendered read-only as a markdown document, with a "We surface" /
/// "We avoid" switch on top. The owner reads the exact criteria the agent
/// works from here, and edits it by talking to the agent on the left.
class AgentPromptPanel extends StatefulWidget {
  const AgentPromptPanel({super.key});

  @override
  State<AgentPromptPanel> createState() => _AgentPromptPanelState();
}

class _AgentPromptPanelState extends State<AgentPromptPanel> {
  // 0 = We surface (videosDesc), 1 = We avoid (avoidDesc).
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        ViewSwitcher(
          labels: const ['We surface', 'We avoid'],
          selectedIndex: _index,
          onSelected: (i) => setState(() => _index = i),
        ),
        Expanded(child: _PromptBody(index: _index)),
      ],
    );
  }
}

class _PromptBody extends StatelessWidget {
  final int index;

  const _PromptBody({required this.index});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedGym,
      builder: (context, _) {
        final spec = selectedGym.detail?.spec;
        if (spec == null) {
          return _PromptMessage(
            selectedGym.error != null
                ? 'Could not reach the video service to load the prompt.'
                : null,
          );
        }
        final markdown = index == 0 ? spec.videosDesc : spec.avoidDesc;
        return SingleChildScrollView(
          child: MarkdownBody(
            data: markdown,
            selectable: true,
            styleSheet: _promptStyleSheet(),
          ),
        );
      },
    );
  }
}

/// Markdown styling, mapped entirely from [DesignConstants] so the prompt
/// document matches the admin chrome (no hardcoded sizes or colours).
MarkdownStyleSheet _promptStyleSheet() {
  final body = DesignConstants.p.copyWith(color: DesignConstants.text2nd);
  return MarkdownStyleSheet(
    p: body,
    a: body.copyWith(color: DesignConstants.hyperlink),
    h1: DesignConstants.h1,
    h2: DesignConstants.h2,
    h3: DesignConstants.h3,
    h4: DesignConstants.h3,
    h5: DesignConstants.h3,
    h6: DesignConstants.h3,
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    listBullet: body,
    blockSpacing: DesignConstants.spacingMedium,
    listIndent: DesignConstants.spacingLarge,
  );
}

/// Loading (null message) / error chrome while the gym detail resolves.
/// Mirrors the videos tab's content-focus message.
class _PromptMessage extends StatelessWidget {
  final String? message;

  const _PromptMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.primaryColor,
                ),
              )
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
