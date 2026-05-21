import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/customization/data/customization_api_client.dart';
import 'package:mobile_app/customization/data/models/customization.dart';

/// App-level singleton holding the active customization.
///
/// Fully app-agnostic: it parses whatever the backend returns
/// into typed-value maps and validates against the
/// [expectedColorKeys] / [expectedImageKeys] / [expectedFontKeys]
/// / [expectedTextKeys] the app declares. Missing expected slots
/// are warned about LOUDLY in the logs — never thrown — so the
/// app always runs on fallbacks.
///
/// Loaded once at startup: fresh network ► disk last-good ►
/// per-call defaults. [initialize] never throws.
class CustomizationService {
  CustomizationService(
    this._apiClient, {
    required this.expectedColorKeys,
    required this.expectedImageKeys,
    required this.expectedFontKeys,
    required this.expectedTextKeys,
  });

  final CustomizationApiClient _apiClient;

  /// Slot ids the app expects the backend to provide. Used only
  /// for the loud missing-slot warning — never to gate anything.
  final List<String> expectedColorKeys;
  final List<String> expectedImageKeys;
  final List<String> expectedFontKeys;
  final List<String> expectedTextKeys;

  static const String _prefsKey = 'customization_last_good_json';

  Customization? _current;
  Customization? get current => _current;
  bool get isLoaded => _current != null;

  /// Loads disk last-good, then refreshes from the network
  /// (hard 5s cap), then warns loudly about any missing expected
  /// slots. Awaited before `runApp`, so `BrandColor` /
  /// `BrandImage` resolve branded values from the first frame.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    final cached = prefs.getString(_prefsKey);
    if (cached != null) {
      _tryAdopt(cached);
    }

    try {
      final json = await _apiClient.fetchOutput().timeout(
            const Duration(seconds: 5),
          );
      final raw = jsonEncode(json);
      if (_tryAdopt(raw)) {
        await prefs.setString(_prefsKey, raw);
      }
    } catch (e) {
      debugPrint('Customization refresh failed: $e');
      // Keep disk last-good / defaults.
    }

    _warnMissingSlots();
  }

  /// Absolute, deduped, non-empty image URLs for cache warming.
  List<String> imageUrlsForPrewarm() {
    final current = _current;
    if (current == null) return const [];
    final urls = <String>{};
    for (final raw in current.images.values) {
      if (raw.isEmpty) continue;
      urls.add(_apiClient.resolveImageUrl(raw));
    }
    return urls.toList(growable: false);
  }

  /// Resolves a raw slot URL to an absolute one.
  String resolveImageUrl(String raw) =>
      _apiClient.resolveImageUrl(raw);

  bool _tryAdopt(String rawJson) {
    try {
      final decoded =
          jsonDecode(rawJson) as Map<String, dynamic>;
      _current = Customization.fromJson(decoded);
      return true;
    } catch (e) {
      debugPrint('Customization parse failed: $e');
      return false;
    }
  }

  void _warnMissingSlots() {
    final colors = _current?.colors ?? const {};
    final images = _current?.images ?? const {};
    final fonts = _current?.fonts ?? const {};
    final texts = _current?.texts ?? const {};
    final missingColors = expectedColorKeys
        .where((k) => colors[k]?.color == null)
        .toList();
    final missingImages = expectedImageKeys
        .where((k) => (images[k] ?? '').isEmpty)
        .toList();
    final missingFonts = expectedFontKeys
        .where((k) => (fonts[k] ?? '').isEmpty)
        .toList();
    final missingTexts = expectedTextKeys
        .where((k) => (texts[k] ?? '').isEmpty)
        .toList();
    if (missingColors.isEmpty &&
        missingImages.isEmpty &&
        missingFonts.isEmpty &&
        missingTexts.isEmpty) {
      return;
    }

    debugPrint(
      '\n========================================================\n'
      '[CUSTOMIZATION] ⚠️⚠️⚠️  MISSING EXPECTED SLOTS — '
      'using fallbacks\n'
      '  loaded: ${isLoaded ? _current!.app : "<nothing>"}\n'
      '  colors missing: '
      '${missingColors.isEmpty ? "-" : missingColors.join(", ")}\n'
      '  images missing: '
      '${missingImages.isEmpty ? "-" : missingImages.join(", ")}\n'
      '  fonts missing : '
      '${missingFonts.isEmpty ? "-" : missingFonts.join(", ")}\n'
      '  texts missing : '
      '${missingTexts.isEmpty ? "-" : missingTexts.join(", ")}\n'
      '========================================================\n',
    );
  }
}
