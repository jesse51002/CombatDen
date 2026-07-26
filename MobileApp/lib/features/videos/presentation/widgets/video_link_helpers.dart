import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';

/// Where a video card plays: YouTube, outside the app.
///
/// Prefers the card's own [GymVideoCard.url] (the canonical watch URL the feed
/// serves) and falls back to building the standard watch URL from
/// [GymVideoCard.videoId] — which also covers a `url` that arrives blank or
/// without a scheme, since a schemeless URI has no handler to launch. Returns
/// null when the card carries neither, so the caller can stay silent rather
/// than throw.
Uri? videoUriFor(GymVideoCard card) {
  final url = card.url.trim();
  if (url.isNotEmpty) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) return parsed;
  }
  final id = card.videoId.trim();
  if (id.isEmpty) return null;
  return Uri.parse(
    'https://www.youtube.com/watch?v=${Uri.encodeComponent(id)}',
  );
}

/// Hand [card]'s watch URL to the OS — the YouTube app when it's installed,
/// the browser otherwise. Returns false when the card has nothing to open, no
/// handler took the intent, or launching threw, so the caller can surface a
/// message.
Future<bool> launchVideoFor(GymVideoCard card) async {
  final uri = videoUriFor(card);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e, st) {
    log('launchVideoFor failed', error: e, stackTrace: st);
    return false;
  }
}

/// Open [card] on YouTube and, when that fails, tell the member instead of
/// leaving a dead tap. Returns whether the video was opened.
///
/// The messenger is captured before the await, so no [BuildContext] crosses
/// the async gap.
Future<bool> openVideoFor(BuildContext context, GymVideoCard card) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await launchVideoFor(card);
  if (opened) return true;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text("Couldn't open the video", style: DesignConstants.p),
      ),
    );
  return false;
}
