"""Pure-logic unit tests for the YouTube Data API client helpers (no network).

Covers the two parsers that turn the API's wire shapes into our row fields: the
ISO-8601 duration → seconds, and the highest-res thumbnail selection.
"""

import pytest

from src.videos.service.youtube_metadata import (
    _AVATAR_THUMBNAIL_PREFERENCE,
    _VIDEO_THUMBNAIL_PREFERENCE,
    YouTubeMetadataClient,
)


@pytest.mark.parametrize(
    ("iso", "expected"),
    [
        ("PT1H2M3S", 3723),
        ("PT5M", 300),
        ("PT45S", 45),
        ("PT1H", 3600),
        ("P1DT2H", 93600),  # a day + two hours (very long upload)
        ("P0D", 0),  # a live broadcast
        ("PT0S", 0),
    ],
)
def test_parse_duration_known_forms(iso: str, expected: int):
    assert YouTubeMetadataClient._parse_duration(iso) == expected


@pytest.mark.parametrize("bad", [None, "", "garbage", "1H2M", 123])
def test_parse_duration_rejects_unparseable(bad: object):
    assert YouTubeMetadataClient._parse_duration(bad) is None


def test_pick_thumbnail_prefers_highest_res():
    thumbnails = {
        "default": {"url": "d"},
        "medium": {"url": "m"},
        "high": {"url": "h"},
        "standard": {"url": "s"},
        "maxres": {"url": "x"},
    }
    # Video preference leads with maxres.
    assert (
        YouTubeMetadataClient._pick_thumbnail(
            thumbnails, _VIDEO_THUMBNAIL_PREFERENCE
        )
        == "x"
    )


def test_pick_thumbnail_falls_back_through_preference():
    # Only medium + default present → video preference skips the missing higher
    # tiers and lands on medium.
    thumbnails = {"default": {"url": "d"}, "medium": {"url": "m"}}
    assert (
        YouTubeMetadataClient._pick_thumbnail(
            thumbnails, _VIDEO_THUMBNAIL_PREFERENCE
        )
        == "m"
    )
    # The avatar preference (high > medium > default) lands on medium too.
    assert (
        YouTubeMetadataClient._pick_thumbnail(
            thumbnails, _AVATAR_THUMBNAIL_PREFERENCE
        )
        == "m"
    )


@pytest.mark.parametrize(
    "thumbnails", [None, {}, "nope", {"default": {}}, {"default": {"url": ""}}]
)
def test_pick_thumbnail_missing_yields_empty(thumbnails: object):
    assert (
        YouTubeMetadataClient._pick_thumbnail(
            thumbnails, _VIDEO_THUMBNAIL_PREFERENCE
        )
        == ""
    )


@pytest.mark.parametrize(
    ("value", "expected"),
    [("123", 123), (456, 456), (None, None), ("x", None), ("", None)],
)
def test_to_int_coerces_or_none(value: object, expected: int | None):
    assert YouTubeMetadataClient._to_int(value) == expected
