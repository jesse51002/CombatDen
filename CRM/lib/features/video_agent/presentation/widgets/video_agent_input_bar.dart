import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Pinned input bar for the video-agent chat.
///
/// Shift+Enter inserts a newline; Enter (without shift) submits.
/// Disabled while the agent is typing or a save is in progress.
class VideoAgentInputBar extends StatefulWidget {
  final bool enabled;
  final ValueChanged<String> onSend;

  const VideoAgentInputBar({
    super.key,
    required this.enabled,
    required this.onSend,
  });

  @override
  State<VideoAgentInputBar> createState() => _VideoAgentInputBarState();
}

class _VideoAgentInputBarState extends State<VideoAgentInputBar> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _ctrl.clear();
    widget.onSend(text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.line),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingSmall,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  _send();
                }
              },
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                enabled: widget.enabled,
                maxLines: 5,
                minLines: 1,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.enabled
                      ? 'Describe your gym and what you want to see…'
                      : 'Agent is thinking…',
                  hintStyle: DesignConstants.p.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? _send : null,
            child: Icon(
              Symbols.send_sharp,
              size: DesignConstants.iconSizeMedium,
              weight: DesignConstants.iconWeight,
              color: widget.enabled
                  ? DesignConstants.primaryColor
                  : DesignConstants.text3rd,
            ),
          ),
        ],
      ),
    );
  }
}
