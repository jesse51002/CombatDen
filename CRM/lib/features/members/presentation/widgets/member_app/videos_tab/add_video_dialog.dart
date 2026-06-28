import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members/data/youtube_url.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Two-step "Add custom video": the owner pastes a YouTube link, the backend
/// looks up its real details (via [onLookup]), and the dialog shows those
/// details for **confirmation** before anything is added. On confirm it pops the
/// URL string; the caller performs the actual add. Cancel / dismiss pops null.
class AddVideoDialog extends StatefulWidget {
  /// Fetches a link's real details without adding it (the lookup endpoint).
  final Future<Video> Function(String url) onLookup;

  const AddVideoDialog({super.key, required this.onLookup});

  static Future<String?> show(
    BuildContext context, {
    required Future<Video> Function(String url) onLookup,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => AddVideoDialog(onLookup: onLookup),
    );
  }

  @override
  State<AddVideoDialog> createState() => _AddVideoDialogState();
}

enum _Phase { input, loading, confirm }

class _AddVideoDialogState extends State<AddVideoDialog> {
  final TextEditingController _urlController = TextEditingController();
  _Phase _phase = _Phase.input;
  Video? _preview;
  String? _error;

  bool get _isValid => extractYoutubeId(_urlController.text) != null;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    if (!_isValid) {
      setState(
        () => _error =
            'That doesn’t look like a YouTube link. Try a '
            'youtube.com/watch?v=… or youtu.be/… URL.',
      );
      return;
    }
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final video = await widget.onLookup(_urlController.text.trim());
      if (!mounted) return;
      setState(() {
        _preview = video;
        _phase = _Phase.confirm;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.input;
        _error =
            'Couldn’t find that video on YouTube. Check the link and try again.';
      });
    }
  }

  void _confirmAdd() => Navigator.of(context).pop(_urlController.text.trim());

  void _back() => setState(() {
    _phase = _Phase.input;
    _preview = null;
  });

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.confirm && _preview != null) {
      return _confirmDialog(_preview!);
    }
    return _inputDialog(loading: _phase == _Phase.loading);
  }

  Widget _inputDialog({required bool loading}) {
    return AppDialog(
      title: 'Add a video',
      showCloseButton: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Paste a YouTube link to add it to this gym’s feed. We’ll show you '
            'the video’s details before adding it.',
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          CustomTextField(
            controller: _urlController,
            label: 'YouTube link',
            hintText: 'https://www.youtube.com/watch?v=…',
            enabled: !loading,
            onSubmitted: loading ? null : _lookup,
          ),
          if (_error != null)
            Text(
              _error!,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
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
              text: 'Look up',
              fullWidth: true,
              isLoading: loading,
              onPressed: loading ? null : _lookup,
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmDialog(Video video) {
    return AppDialog(
      title: 'Add this video?',
      showCloseButton: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [_VideoPreview(video: video)],
      ),
      actions: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(
            child: AppOutlineButton(
              text: 'Back',
              fullWidth: true,
              onPressed: _back,
            ),
          ),
          Expanded(
            child: AppPrimaryButton(
              text: 'Add to feed',
              fullWidth: true,
              onPressed: _confirmAdd,
            ),
          ),
        ],
      ),
    );
  }
}

/// The fetched video's details shown for confirmation: thumbnail, title, and
/// channel ‧ views.
class _VideoPreview extends StatelessWidget {
  final Video video;

  const _VideoPreview({required this.video});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        // Show the stored thumbnail; nothing when there isn't one (or it fails).
        if (video.thumbnailUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                video.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        Text(
          video.title.isNotEmpty ? video.title : 'Untitled video',
          style: DesignConstants.h3,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          video.metaLabel.isNotEmpty ? video.metaLabel : 'YouTube',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
