import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_dialog/app_dialog.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';
import 'package:app_management/shared/widgets/custom_text_field.dart';

/// Confirms removing a video. For agent-curated feed videos it asks an
/// optional "why" so the agent learns to keep videos like it out of the
/// feed automatically next time, instead of resurfacing the same mistake.
class RemoveVideoDialog extends StatefulWidget {
  final String videoTitle;
  final bool teachAgent;

  const RemoveVideoDialog({
    super.key,
    required this.videoTitle,
    required this.teachAgent,
  });

  static Future<void> show(
    BuildContext context, {
    required String videoTitle,
    required bool teachAgent,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          RemoveVideoDialog(videoTitle: videoTitle, teachAgent: teachAgent),
    );
  }

  @override
  State<RemoveVideoDialog> createState() => _RemoveVideoDialogState();
}

class _RemoveVideoDialogState extends State<RemoveVideoDialog> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Remove this video?',
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
              "Tell the agent why. It'll learn to keep videos like this "
              'out of the feed automatically next time, so you never have '
              'to remove it again.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            CustomTextField(
              controller: _reasonController,
              label: 'Why remove it? (optional)',
              hintText: 'e.g. wrong discipline, off-topic, too graphic',
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
              text: 'Remove',
              fullWidth: true,
              backgroundColor: DesignConstants.redDark,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
