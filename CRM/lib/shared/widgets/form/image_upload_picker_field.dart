import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/uploads/image_upload_repository.dart';

/// Enforced aspect ratio + max width for the upload preview.
const double _kAspect = 16 / 9;
const double _kMaxWidth = 360;

/// Labeled image upload field.
///
/// On tap: opens the system file picker, uploads the chosen
/// image to the CDN via [category] (`'reward'` or `'member'`),
/// shows a loading spinner during the upload, then calls
/// [onUploaded] with the returned CDN URL and shows the
/// uploaded preview.  Inline error text is shown on failure.
///
/// An optional current [imageUrl] or bundled [imageAsset] is
/// displayed as the initial preview before any upload.
class ImageUploadPickerField extends StatefulWidget {
  final String label;

  /// Backend upload category: `'reward'` or `'member'`.
  final String category;

  /// Called with the CDN URL after a successful upload.
  final void Function(String url) onUploaded;

  /// Optional current image URL shown as the initial preview.
  final String? imageUrl;

  /// Optional bundled asset path shown when [imageUrl] is absent.
  final String? imageAsset;

  const ImageUploadPickerField({
    super.key,
    required this.label,
    required this.category,
    required this.onUploaded,
    this.imageUrl,
    this.imageAsset,
  });

  @override
  State<ImageUploadPickerField> createState() => _ImageUploadPickerFieldState();
}

class _ImageUploadPickerFieldState extends State<ImageUploadPickerField> {
  late final ImageUploadRepository _repo;
  String? _uploadedUrl;
  bool _isUploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = ImageUploadRepository(ApiClient());
  }

  String? get _effectiveUrl => _uploadedUrl ?? widget.imageUrl;

  bool get _hasImage =>
      (_effectiveUrl?.isNotEmpty ?? false) ||
      widget.imageAsset != null;

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
        _isUploading = false;
      });
      widget.onUploaded(url);
    } catch (e, st) {
      log('Image upload failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _error = 'Upload failed — please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(widget.label, style: DesignConstants.h2),
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
                  aspectRatio: _kAspect,
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
                          color: DesignConstants.text3rd,
                          width: DesignConstants.buttonBorder,
                        ),
                      ),
                      child: _isUploading
                          ? const _LoadingOverlay()
                          : _hasImage
                              ? _Preview(
                                  imageUrl: _effectiveUrl,
                                  asset: widget.imageAsset,
                                )
                              : const _UploadPrompt(),
                    ),
                  ),
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

  const _Preview({this.imageUrl, this.asset});

  Widget _image() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    if (asset != null) {
      return Image.asset(asset!, fit: BoxFit.cover);
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
