import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_dialog/app_dialog.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';
import 'package:app_management/shared/widgets/custom_text_field.dart';

/// Whether the dialog removes a video from the feed or keeps a rejected one
/// back in it. Drives the copy, the reason hint, and the confirm button.
enum VideoCurationMode { remove, keep }

/// Confirms removing a video from the feed, or keeping a rejected one back.
/// For agent-curated videos it asks an optional "why" so the agent learns to
/// surface / suppress videos like it automatically next time, instead of
/// resurfacing the same mistake.
class VideoCurationDialog extends StatefulWidget {
  final String videoTitle;
  final bool teachAgent;
  final VideoCurationMode mode;

  const VideoCurationDialog({
    super.key,
    required this.videoTitle,
    required this.teachAgent,
    required this.mode,
  });

  static Future<void> show(
    BuildContext context, {
    required String videoTitle,
    required bool teachAgent,
    VideoCurationMode mode = VideoCurationMode.remove,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => VideoCurationDialog(
        videoTitle: videoTitle,
        teachAgent: teachAgent,
        mode: mode,
      ),
    );
  }

  @override
  State<VideoCurationDialog> createState() => _VideoCurationDialogState();
}

class _VideoCurationDialogState extends State<VideoCurationDialog> {
  final TextEditingController _reasonController = TextEditingController();

  bool get _isKeep => widget.mode == VideoCurationMode.keep;

  String get _title => _isKeep ? 'Keep this video?' : 'Remove this video?';

  String get _confirmLabel => _isKeep ? 'Keep' : 'Remove';

  Color get _confirmColor =>
      _isKeep ? DesignConstants.goodGreen : DesignConstants.redDark;

  String get _teachText => _isKeep
      ? "Tell the agent why you want it back. It'll learn to surface "
            'videos like this automatically next time, so it stays in the '
            'feed.'
      : "Tell the agent why. It'll learn to keep videos like this out of "
            'the feed automatically next time, so you never have to remove '
            'it again.';

  String get _reasonLabel =>
      _isKeep ? 'Why keep it? (optional)' : 'Why remove it? (optional)';

  String get _reasonHint => _isKeep
      ? 'e.g. great breakdown, on-topic, members asked for it'
      : 'e.g. wrong discipline, off-topic, too graphic';

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: _title,
      showCloseButton: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            widget.videoTitle,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          if (widget.teachAgent) ...[
            Text(
              _teachText,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            CustomTextField(
              controller: _reasonController,
              label: _reasonLabel,
              hintText: _reasonHint,
            ),
          ],
        ],
      ),
      actions: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(
            child: AppOutlineButton(
              text: 'Cancel',
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: AppPrimaryButton(
              text: _confirmLabel,
              fullWidth: true,
              backgroundColor: _confirmColor,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
