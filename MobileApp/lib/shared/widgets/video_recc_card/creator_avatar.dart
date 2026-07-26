import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The single place that decides whether a video has a creator avatar.
///
/// The served feed's `channel_avatar_url` is routinely absent — the shared
/// video pool carries no avatar for a channel, so the field arrives as an
/// empty string rather than null. An empty (or whitespace-only) URL is
/// therefore treated as **no avatar**: this returns null and every call site
/// omits the avatar entirely instead of rendering a broken circle. When a real
/// URL is present it resolves to the same `cached_network_image` provider the
/// cards have always used.
ImageProvider? creatorAvatarProvider(String? url) {
  final trimmed = url?.trim() ?? '';
  return trimmed.isEmpty ? null : CachedNetworkImageProvider(trimmed);
}

/// The circular creator avatar shown beside a video's title.
///
/// Render it only when [creatorAvatarProvider] returned a non-null provider —
/// callers drop it from their `children` list entirely when there is no
/// avatar, so no placeholder circle and no reserved gap are left behind.
/// [size] is an asset dimension, not a spacing token, so it is passed as a
/// plain pixel value by the owning card.
///
/// A URL that FAILS to load collapses to nothing, exactly like an absent one.
/// This matters because YouTube rotates a channel's avatar URL whenever the
/// creator changes their picture, so a stored URL goes stale and 404s on its
/// own — and a stale avatar drawn as a filled disc is worse than no avatar at
/// all. The row's `spacing:` keeps the remaining gap honest.
class CreatorAvatar extends StatelessWidget {
  const CreatorAvatar({
    super.key,
    required this.image,
    required this.size,
  });

  final ImageProvider image;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
