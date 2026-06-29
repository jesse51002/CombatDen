import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/video_agent/bloc/video_agent_bloc.dart';
import 'package:crm/features/video_agent/bloc/video_agent_event.dart';
import 'package:crm/features/video_agent/data/models/video_agent_models.dart';

/// Chip-based answer surface rendered when the agent asks an [AgentQuestion].
///
/// Single-select ([AgentQuestion.multiSelect] == false): tapping a chip
/// immediately sends that option as the next message and clears the question.
///
/// Multi-select: chips toggle; a "Send" button sends the joined selection
/// once at least one option is chosen. The text input bar remains available
/// so the owner may type a custom reply instead.
class VideoAgentQuestionChips extends StatefulWidget {
  final AgentQuestion question;

  const VideoAgentQuestionChips({super.key, required this.question});

  @override
  State<VideoAgentQuestionChips> createState() =>
      _VideoAgentQuestionChipsState();
}

class _VideoAgentQuestionChipsState
    extends State<VideoAgentQuestionChips> {
  final Set<int> _selected = {};

  void _send(BuildContext context, String text, List<String> selected) {
    context.read<VideoAgentBloc>().add(
      VideoAgentMessageSent(text, selectedOptions: selected),
    );
  }

  void _sendSelected(BuildContext context) {
    if (_selected.isEmpty) return;
    final selected =
        _selected.map((i) => widget.question.options[i]).toList();
    _send(context, selected.join(', '), selected);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(color: DesignConstants.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Row(
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                Symbols.help_outline_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.primaryColor,
              ),
              Expanded(
                child: Text(
                  widget.question.question,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ),
            ],
          ),
          _OptionChips(
            options: widget.question.options,
            multiSelect: widget.question.multiSelect,
            selected: _selected,
            onTap: (i) {
              if (!widget.question.multiSelect) {
                final opt = widget.question.options[i];
                _send(context, opt, [opt]);
                return;
              }
              setState(() {
                if (_selected.contains(i)) {
                  _selected.remove(i);
                } else {
                  _selected.add(i);
                }
              });
            },
          ),
          if (widget.question.multiSelect)
            Align(
              alignment: Alignment.centerRight,
              child: _SendButton(
                enabled: _selected.isNotEmpty,
                onPressed: () => _sendSelected(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionChips extends StatelessWidget {
  final List<String> options;
  final bool multiSelect;
  final Set<int> selected;
  final ValueChanged<int> onTap;

  const _OptionChips({
    required this.options,
    required this.multiSelect,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignConstants.spacingSmall,
      runSpacing: DesignConstants.spacingSmall,
      children: [
        for (var i = 0; i < options.length; i++)
          _Chip(
            label: options[i],
            isSelected: selected.contains(i),
            multiSelect: multiSelect,
            onTap: () => onTap(i),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool multiSelect;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.isSelected,
    required this.multiSelect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? DesignConstants.primaryColor
              : DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: Border.all(
            color: isSelected
                ? DesignConstants.primaryColor
                : DesignConstants.line,
            width: DesignConstants.buttonBorderSize,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            if (multiSelect)
              Icon(
                isSelected
                    ? Symbols.check_circle_sharp
                    : Symbols.radio_button_unchecked_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: isSelected
                    ? DesignConstants.onAccent
                    : DesignConstants.text3rd,
              ),
            Text(
              label,
              style: DesignConstants.p.copyWith(
                color: isSelected
                    ? DesignConstants.onAccent
                    : DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _SendButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: enabled
              ? DesignConstants.primaryColor
              : DesignConstants.primaryColor25,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Icon(
              Symbols.send_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.onAccent,
            ),
            Text(
              'Send',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
