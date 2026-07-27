import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/bloc/video_click_event.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_click_scope.dart';

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
/// The open is also REPORTED to the member portal (a `video_clicked` activity)
/// through the app-lifetime [VideoClickScope], so the member's taste profile
/// learns from every video they picked themselves and not only from the one
/// the system recommended. The report is dispatched to a bloc BEFORE the
/// launch is awaited — dispatching is synchronous and the bloc swallows its own
/// failures, so a slow or failing report can never delay the launch or surface
/// an error. Outside the app shell (widget tests, the capture harness) the
/// scope is absent and nothing is reported.
///
/// Pass `reportOpen: false` when the caller already reports this open through
/// another route — the recommendation screen posts the rec-scoped click, which
/// logs the same activity, so reporting here as well would log one tap twice.
///
/// The messenger is captured before the await, so no [BuildContext] crosses
/// the async gap.
Future<bool> openVideoFor(
  BuildContext context,
  GymVideoCard card, {
  bool reportOpen = true,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // Only an openable card is a real open — a card with neither url nor id
  // launches nothing, so it is not taste signal either.
  if (reportOpen && videoUriFor(card) != null) {
    VideoClickScope.maybeOf(context)?.add(VideoOpenedFromFeed(card.videoId));
  }
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
