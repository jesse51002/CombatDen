import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/video_agent/bloc/video_agent_state.dart';
import 'package:crm/features/video_agent/data/models/video_agent_models.dart';
import 'package:crm/features/video_agent/presentation/widgets/video_agent_answer_bubble.dart';
import 'package:crm/features/video_agent/presentation/widgets/video_agent_outcome_bubble.dart';
import 'package:crm/features/members/presentation/widgets/member_app/video_agent/agent_message_bubble.dart';
import 'package:crm/features/members/presentation/widgets/member_app/video_agent/user_message_bubble.dart';

/// Scrollable list of [ChatMessage]s with a typing indicator when the
/// agent is processing.
///
/// Auto-scrolls to the bottom when a new message arrives or typing starts.
class VideoAgentChatList extends StatefulWidget {
  final List<ChatMessage> messages;
  final VideoAgentChatStatus chatStatus;

  const VideoAgentChatList({
    super.key,
    required this.messages,
    required this.chatStatus,
  });

  @override
  State<VideoAgentChatList> createState() => _VideoAgentChatListState();
}

class _VideoAgentChatListState extends State<VideoAgentChatList> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(VideoAgentChatList old) {
    super.didUpdateWidget(old);
    final addedMsg = widget.messages.length != old.messages.length;
    final typingChanged = widget.chatStatus != old.chatStatus;
    if (addedMsg || typingChanged) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTyping =
        widget.chatStatus == VideoAgentChatStatus.typing;
    final itemCount =
        widget.messages.length + (isTyping ? 1 : 0);

    if (itemCount == 0) {
      return const _EmptyState();
    }

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      itemCount: itemCount,
      separatorBuilder: (_, _) =>
          const SizedBox(height: DesignConstants.spacingMedium),
      itemBuilder: (_, i) {
        if (i >= widget.messages.length) {
          return const _TypingBubble();
        }
        final msg = widget.messages[i];
        if (msg.status != ChatMessageStatus.none) {
          return VideoAgentOutcomeBubble(
            text: msg.text,
            status: msg.status,
          );
        }
        if (msg.isUser && msg.options != null) {
          return VideoAgentAnswerBubble(
            options: msg.options!,
            selectedOptions: msg.selectedOptions,
            text: msg.text,
          );
        }
        return msg.isUser
            ? UserMessageBubble(text: msg.text)
            : AgentMessageBubble(text: msg.text);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text('Video feed configuration', style: DesignConstants.h2),
          Text(
            'Tell the agent about your gym — disciplines, what makes '
            'a good video for your members, and what to avoid. It will '
            'propose a config you can review and save.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Animated "..." typing indicator shown while the agent is processing.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  int get _dots => (_ctrl.value * 3).floor() + 1;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => Container(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          decoration: BoxDecoration(
            color: DesignConstants.card,
            borderRadius:
                BorderRadius.circular(DesignConstants.radiusSmall),
          ),
          child: Text(
            '.' * _dots,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
      ),
    );
  }
}
