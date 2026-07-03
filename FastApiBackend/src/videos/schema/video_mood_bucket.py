"""The deterministic ``video_genre`` → ``mood_bucket`` mapping.

A video's mood bucket is DETERMINISTIC CODE derived from its single
``video.tag`` genre — the backend defines only this map; the ``MoodBucket``
vocabulary itself lives in the Database package (``schema.video``) and is never
redefined here (house rule). Member video recs retrieve top-k per bucket and
interleave, so the bucket quota is what stops retrieval collapsing to
all-educational content.

Like ``videos_big_group`` this is fixed shared vocabulary, not per-gym config,
so it stays a small class-less concern module of free functions + a constant.
"""

from __future__ import annotations

from schema.video import MoodBucket, VideoGenre

# The single source of the genre → bucket derivation. Every ``VideoGenre`` maps
# to exactly one ``MoodBucket`` (asserted total in tests, both directions).
GENRE_TO_BUCKET: dict[VideoGenre, MoodBucket] = {
    VideoGenre.educational: MoodBucket.teach,
    VideoGenre.analysis: MoodBucket.teach,
    VideoGenre.entertainment: MoodBucket.enjoy,
    VideoGenre.clips: MoodBucket.enjoy,
    VideoGenre.memes: MoodBucket.enjoy,
    VideoGenre.news: MoodBucket.inform,
    VideoGenre.interview: MoodBucket.human,
    VideoGenre.vlog: MoodBucket.human,
    VideoGenre.professional: MoodBucket.peak,
}


def bucket_for_genre(genre: VideoGenre) -> MoodBucket:
    """The mood bucket a single genre maps to."""
    return GENRE_TO_BUCKET[genre]


def genres_for_bucket(bucket: MoodBucket) -> list[VideoGenre]:
    """The genres that map to ``bucket`` (in ``VideoGenre`` declaration order).

    Used to build the ``video.tag = ANY(...)`` filter for a bucket's candidate
    retrieval.
    """
    return [g for g, b in GENRE_TO_BUCKET.items() if b is bucket]
