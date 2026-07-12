import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/uploads/image_upload_repository.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/form/image_upload_pool_tray.dart';

/// Default aspect ratio + max width for the upload preview. Landscape
/// photos (reward / member / class / gym) preview at 16:9; square art
/// (a rank belt) overrides [ImageUploadPickerField.aspectRatio] to 1.
const double _kAspect = 16 / 9;
const double _kMaxWidth = 360;

/// Labeled image upload field.
///
/// On tap: opens the system file picker, uploads the chosen
/// image to the CDN via [category] (`'reward'`, `'member'`,
/// `'class'`, `'gym'`, or `'rank'`), shows a loading spinner during the
/// upload, then calls [onImageChosen] with the returned CDN URL and shows
/// the uploaded preview.  Inline error text is shown on failure.
///
/// When [poolImages] is non-empty, a horizontally-scrollable tray of
/// tappable default-image chips (plus a trailing upload tile) renders
/// below the preview. Tapping a chip is synchronous — no upload — and
/// fires [onImageChosen] with that pool URL, so the same callback carries
/// both an upload result and a pool pick. An upload always overrides a
/// prior pool pick, and a pool tap clears a prior upload.
///
/// An optional current [imageUrl] or bundled [imageAsset] is
/// displayed as the initial preview before any upload. When
/// neither is set, an optional [defaultImageUrl] is previewed
/// instead (with a "choose your own" caption) so the caller can
/// show the platform default the record will get if the user
/// never uploads their own.
///
/// The field does not validate itself. A host form that marks it
/// [isRequired] passes an [errorText] on a failed submit; that text
/// renders below the preview and the preview border turns red.
class ImageUploadPickerField extends StatefulWidget {
  final String label;

  /// Backend upload category: `'reward'`, `'member'`, `'class'`, `'gym'`,
  /// or `'rank'`.
  final String category;

  /// Called with the chosen CDN URL — fired both when an upload finishes
  /// and when a pool image is tapped.
  final void Function(String url) onImageChosen;

  /// Optional pool of default CDN image URLs. When non-empty, they render
  /// as a tray of tappable chips below the preview; a tap selects one
  /// synchronously (no upload) and fires [onImageChosen]. Empty by default,
  /// so call sites that only upload are visually unchanged.
  final List<String> poolImages;

  /// Whether the host form treats this field as required. The widget itself
  /// never validates — this only marks the label; the host decides what
  /// counts as filled (a [defaultImageUrl] preview never does) and, on a
  /// failed submit, passes an [errorText].
  final bool isRequired;

  /// Validation error supplied by the host form on a failed submit. When
  /// set, the preview border turns red and this text renders below it.
  final String? errorText;

  /// Preview box aspect ratio (width / height). Defaults to 16:9 for the
  /// landscape photo call sites; the rank belt fields pass `1` so a
  /// square belt image previews un-cropped and un-distorted.
  final double aspectRatio;

  /// How the preview image fits its box. Defaults to [BoxFit.cover]
  /// (fill + crop) for photos; the belt fields pass [BoxFit.contain] so
  /// the whole square belt stays visible with no crop or stretch,
  /// matching how `RankBeltImage` renders it everywhere else.
  final BoxFit previewFit;

  /// Optional current image URL shown as the initial preview.
  final String? imageUrl;

  /// Optional bundled asset path shown when [imageUrl] is absent.
  final String? imageAsset;

  /// Optional placeholder image previewed (with a caption) when the
  /// user has chosen no image yet. Purely a preview: it is NOT bubbled
  /// up via [onImageChosen] — the caller only receives a URL once the
  /// user actually uploads or picks one.
  final String? defaultImageUrl;

  /// When true, a full-width tonal upload button sits below the preview so
  /// the upload is an obvious call to action — used where the record gets a
  /// platform default and the owner is nudged to personalize it (the reward
  /// form). The tile itself stays tappable; the button just makes the
  /// affordance unmissable. Off by default so other call sites (class form,
  /// member photo) are visually unchanged.
  final bool prominentUpload;

  const ImageUploadPickerField({
    super.key,
    required this.label,
    required this.category,
    required this.onImageChosen,
    this.poolImages = const [],
    this.isRequired = false,
    this.errorText,
    this.imageUrl,
    this.imageAsset,
    this.defaultImageUrl,
    this.prominentUpload = false,
    this.aspectRatio = _kAspect,
    this.previewFit = BoxFit.cover,
  });

  @override
  State<ImageUploadPickerField> createState() => _ImageUploadPickerFieldState();
}

class _ImageUploadPickerFieldState extends State<ImageUploadPickerField> {
  late final ImageUploadRepository _repo;
  String? _uploadedUrl;
  String? _selectedPoolUrl;
  bool _isUploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = ImageUploadRepository(ApiClient());
  }

  // An upload wins over a pool pick, which wins over the initial [imageUrl].
  // The two in-session sources are kept mutually exclusive (each clears the
  // other on selection), so at most one chip ever shows the selected ring.
  String? get _effectiveUrl =>
      _uploadedUrl ?? _selectedPoolUrl ?? widget.imageUrl;

  bool get _hasImage =>
      (_effectiveUrl?.isNotEmpty ?? false) ||
      widget.imageAsset != null;

  /// Whether to preview [ImageUploadPickerField.defaultImageUrl] because the
  /// user has chosen no image of their own yet.
  bool get _showDefault =>
      !_hasImage && (widget.defaultImageUrl?.isNotEmpty ?? false);

  Future<void> _onTap() async {
    if (_isUploading) return;

    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (xFile == null) return;

    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
      final bytes = await xFile.readAsBytes();
      final url = await _repo.uploadImage(
        bytes: bytes,
        filename: xFile.name,
        category: widget.category,
        mimeType: xFile.mimeType ?? 'image/jpeg',
      );
      if (!mounted) return;
      setState(() {
        _uploadedUrl = url;
        _selectedPoolUrl = null;
        _isUploading = false;
      });
      widget.onImageChosen(url);
    } catch (e, st) {
      log('Image upload failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _error = 'Upload failed — please try again.';
      });
    }
  }

  /// Synchronous pool-chip pick — no upload. Selects [url], clears any
  /// prior upload so the pick wins, and bubbles it via [onImageChosen].
  void _onPoolPick(String url) {
    if (_isUploading) return;
    setState(() {
      _selectedPoolUrl = url;
      _uploadedUrl = null;
      _error = null;
    });
    widget.onImageChosen(url);
  }

  /// The prominent full-width upload CTA (opt-in via
  /// [ImageUploadPickerField.prominentUpload]). Tonal sapphire so it reads as
  /// an unmistakable button without competing with a form's gradient submit.
  Widget _uploadButton() {
    return AppPrimaryButton(
      text: _hasImage ? 'Replace image' : 'Upload your own image',
      fullWidth: true,
      backgroundColor: DesignConstants.primaryColor10,
      textColor: DesignConstants.primaryColor,
      icon: Icon(
        Symbols.add_photo_alternate_sharp,
        size: DesignConstants.iconSizeMedium,
        color: DesignConstants.primaryColor,
        weight: DesignConstants.iconWeight,
      ),
      onPressed: _isUploading ? null : _onTap,
    );
  }

  /// The field label, with a red required marker appended when the host
  /// form marks the field [ImageUploadPickerField.isRequired].
  Widget _label() {
    if (!widget.isRequired) {
      return Text(widget.label, style: DesignConstants.h2);
    }
    return Text.rich(
      TextSpan(
        text: widget.label,
        style: DesignConstants.h2,
        children: [
          TextSpan(
            text: ' *',
            style: DesignConstants.h2.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        _label(),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: _kMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: InkWell(
                    onTap: _isUploading ? null : _onTap,
                    borderRadius: BorderRadius.circular(
                      DesignConstants.radiusBig,
                    ),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: DesignConstants.card,
                        borderRadius: BorderRadius.circular(
                          DesignConstants.radiusBig,
                        ),
                        border: Border.all(
                          color: hasError
                              ? DesignConstants.badRed
                              : DesignConstants.text3rd,
                          width: DesignConstants.buttonBorder,
                        ),
                      ),
                      child: _isUploading
                          ? const _LoadingOverlay()
                          : _hasImage
                              ? _Preview(
                                  imageUrl: _effectiveUrl,
                                  asset: widget.imageAsset,
                                  fit: widget.previewFit,
                                )
                              : _showDefault
                                  ? _Preview(
                                      imageUrl: widget.defaultImageUrl,
                                      fit: widget.previewFit,
                                    )
                                  : const _UploadPrompt(),
                    ),
                  ),
                ),
                if (widget.poolImages.isNotEmpty)
                  ImageUploadPoolTray(
                    poolImages: widget.poolImages,
                    aspectRatio: widget.aspectRatio,
                    selectedUrl: _selectedPoolUrl,
                    disabled: _isUploading,
                    onPick: _onPoolPick,
                    onUpload: _onTap,
                  ),
                if (widget.prominentUpload) _uploadButton(),
                if (_showDefault && !widget.prominentUpload)
                  Text(
                    'Default image — choose your own',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.badRed,
                    ),
                  ),
                if (hasError)
                  Text(
                    widget.errorText!,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.badRed,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        color: DesignConstants.primaryColor,
        strokeWidth: DesignConstants.buttonBorder,
      ),
    );
  }
}

class _UploadPrompt extends StatelessWidget {
  const _UploadPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            Symbols.add_photo_alternate_sharp,
            size: DesignConstants.iconSizeBig,
            color: DesignConstants.text3rd,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            'Upload image',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text3rd,
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final String? imageUrl;
  final String? asset;
  final BoxFit fit;

  const _Preview({this.imageUrl, this.asset, this.fit = BoxFit.cover});

  Widget _image() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: fit,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    if (asset != null) {
      return Image.asset(asset!, fit: fit);
    }
    return ColoredBox(color: DesignConstants.card);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _image(),
        Positioned(
          right: DesignConstants.spacingMedium,
          bottom: DesignConstants.spacingMedium,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingMedium,
              vertical: DesignConstants.spacingSmall,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.popup,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusBig,
              ),
            ),
            child: Text(
              'Change',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
