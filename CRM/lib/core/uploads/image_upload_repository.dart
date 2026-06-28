import 'dart:typed_data';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:dio/dio.dart';

/// Repository for the `/api/v1/uploads/image` multipart endpoint.
///
/// Callers provide raw image bytes; this class builds the
/// [FormData], calls [ApiClient.postMultipart], and returns
/// the CDN URL from the response.
///
/// Propagates [ServerException] / [NetworkException] on failure.
class ImageUploadRepository {
  final ApiClient _apiClient;

  const ImageUploadRepository(this._apiClient);

  /// Uploads image [bytes] to the CDN.
  ///
  /// [filename] is the original file name (used for the
  /// multipart part and MIME-type auto-detection fallback).
  /// [category] must be `'reward'` or `'member'`.
  /// [mimeType] should be the actual MIME type from the picker
  /// (e.g. `'image/jpeg'`); defaults to `'image/jpeg'`.
  ///
  /// Returns the CDN URL on success
  /// (`https://cdn.combatden.net/...?v=...`).
  Future<String> uploadImage({
    required Uint8List bytes,
    required String filename,
    required String category,
    String mimeType = 'image/jpeg',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
      'category': category,
    });

    final response =
        await _apiClient.postMultipart<Map<String, dynamic>>(
      '/api/v1/uploads/image',
      data: formData,
    );

    final url = response.data?['url'];
    if (url is! String || url.isEmpty) {
      throw const ServerException(
        'Upload response did not include a URL.',
      );
    }
    return url;
  }
}
