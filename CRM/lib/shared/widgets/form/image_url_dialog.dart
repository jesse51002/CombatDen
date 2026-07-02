import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Enforced 16:9 preview ratio, matching the field and `ClassCard`.
const double _kPreviewAspect = 16 / 9;

/// Small "paste an image link" dialog with a live network preview. There is
/// no file-upload infrastructure — pasting a URL IS the mechanism. The pasted
/// link is resolved as it changes; Confirm stays disabled until an image
/// actually loads, and a broken/unreachable link shows a graceful error state
/// instead of a silent failure. Returns the confirmed URL via `Navigator.pop`,
/// or null on Cancel/dismiss — the caller owns applying it.
class ImageUrlDialog extends StatefulWidget {
  /// Pre-fills the field (e.g. the class's current custom image) so an owner
  /// can tweak rather than retype. Null starts empty.
  final String? initialUrl;

  const ImageUrlDialog({super.key, this.initialUrl});

  static Future<String?> show({
    required BuildContext context,
    String? initialUrl,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => ImageUrlDialog(initialUrl: initialUrl),
    );
  }

  @override
  State<ImageUrlDialog> createState() => _ImageUrlDialogState();
}

/// Whether the currently-typed link has resolved to a loadable image.
enum _PreviewStatus { idle, loading, ok, error }

class _ImageUrlDialogState extends State<ImageUrlDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;

  /// The trimmed URL the current [_status] describes — guards against a
  /// slow-resolving earlier link stamping its result over a newer one.
  String _resolvedUrl = '';
  _PreviewStatus _status = _PreviewStatus.idle;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? '');
    // Preview the prefilled link straight away, before any edit.
    if (_controller.text.trim().isNotEmpty) _resolve(_controller.text);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounce so a pasted link resolves once, not per keystroke of a typed one.
  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _resolve(_controller.text),
    );
  }

  /// Resolve [raw] as a network image; flip [_status] on load or error. Stale
  /// results (a newer link typed meanwhile) are dropped via the [_resolvedUrl]
  /// guard.
  void _resolve(String raw) {
    final url = raw.trim();
    if (url == _resolvedUrl && _status != _PreviewStatus.idle) return;
    setState(() {
      _resolvedUrl = url;
      _status = url.isEmpty ? _PreviewStatus.idle : _PreviewStatus.loading;
    });
    if (url.isEmpty) return;

    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (mounted && _resolvedUrl == url) {
          setState(() => _status = _PreviewStatus.ok);
        }
      },
      onError: (error, _) {
        stream.removeListener(listener);
        if (mounted && _resolvedUrl == url) {
          setState(() => _status = _PreviewStatus.error);
        }
      },
    );
    stream.addListener(listener);
  }

  bool get _canConfirm => _status == _PreviewStatus.ok;

  void _confirm() {
    if (_canConfirm) Navigator.of(context).pop(_resolvedUrl);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Change image',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Paste a link to an image (JPG or PNG). It previews below before '
            'you use it.',
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          CustomTextField(
            controller: _controller,
            label: 'Image link',
            hintText: 'https://example.com/photo.jpg',
            keyboardType: TextInputType.url,
          ),
          _PreviewArea(status: _status, url: _resolvedUrl),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Use this image',
        primaryOnPressed: _canConfirm ? _confirm : null,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// The 16:9 live preview: an empty prompt, a spinner while resolving, the
/// image once loaded, or a "couldn't load" error state.
class _PreviewArea extends StatelessWidget {
  final _PreviewStatus status;
  final String url;

  const _PreviewArea({required this.status, required this.url});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kPreviewAspect,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: Border.all(
            color: DesignConstants.text3rd,
            width: DesignConstants.buttonBorder,
          ),
        ),
        child: switch (status) {
          _PreviewStatus.idle => const _PreviewMessage(
              icon: Symbols.image_sharp,
              text: 'Paste an image link to preview it',
            ),
          _PreviewStatus.loading => const Center(child: AppSpinner()),
          // Already resolved by the listener, so this render is from cache.
          _PreviewStatus.ok => Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _PreviewMessage(
                icon: Symbols.broken_image_sharp,
                text: 'Couldn’t load that image',
                tinted: true,
              ),
            ),
          _PreviewStatus.error => const _PreviewMessage(
              icon: Symbols.broken_image_sharp,
              text: 'Couldn’t load that image',
              tinted: true,
            ),
        },
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  /// Red tint for the error state; otherwise the muted placeholder colour.
  final bool tinted;

  const _PreviewMessage({
    required this.icon,
    required this.text,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        tinted ? DesignConstants.badRed : DesignConstants.text3rd;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            icon,
            size: DesignConstants.iconSizeBig,
            color: color,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            text,
            textAlign: TextAlign.center,
            style: DesignConstants.pSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
