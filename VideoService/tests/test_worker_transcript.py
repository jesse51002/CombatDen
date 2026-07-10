"""The Apify transcript client: cue parsing + the batched ``fetch_batch`` mapping.
No network — ``fetch_batch``'s actor run (``_run_batch``) is patched, so no token or
HTTP is needed. (The SRT/HTML-cleaning logic moved here from the retired scraper
transform when transcripts became a lazy Apify fetch; the fetch is now BATCHED —
one actor run over a list of watch urls, mapped back to videos by ``inputUrl``.)"""

from __future__ import annotations

import asyncio

from src.worker import worker_config
from src.worker.worker_apify import (
    WorkerTranscriptClient,
    _transcript_from_item,
    _video_id_from_input_url,
    transcript_from_items,
)


def test_cues_join_into_plain_text() -> None:
    # The batched actor's success cue shape is {text, start, duration}; only text
    # is read, so start/duration are ignored.
    items = [
        {"start": 0.0, "duration": 1.5, "text": "hello"},
        {"start": 1.5, "duration": 1.5, "text": "world"},
    ]
    assert transcript_from_items(items) == "hello world"


def test_wrapper_entry_with_nested_cue_list() -> None:
    # Some actor shapes return one item wrapping the cue list under a key.
    items = [{"transcript": [{"text": "hello"}, {"text": "there"}]}]
    assert transcript_from_items(items) == "hello there"


def test_html_entities_unescaped() -> None:
    items = [{"text": "rock &amp; roll"}, {"text": "&quot;go&quot;"}]
    assert transcript_from_items(items) == 'rock & roll "go"'


def test_srt_shaped_payload_is_stripped() -> None:
    srt = (
        "1\n00:00:00,000 --> 00:00:02,000\nhello\n\n"
        "2\n00:00:02,000 --> 00:00:04,000\nworld"
    )
    assert transcript_from_items([{"text": srt}]) == "hello world"


def test_empty_or_blank_becomes_none() -> None:
    assert transcript_from_items([]) is None
    assert transcript_from_items([{"text": "   "}]) is None
    assert transcript_from_items([{"noText": "x"}]) is None


# --- batch item helpers ---------------------------------------------------------


def _watch(video_id: str) -> str:
    return f"https://www.youtube.com/watch?v={video_id}"


def test_video_id_parsed_from_input_url() -> None:
    assert _video_id_from_input_url({"inputUrl": _watch("abc123")}) == "abc123"
    assert _video_id_from_input_url({"inputUrl": "not a url"}) is None
    assert _video_id_from_input_url({}) is None


def test_success_item_joins_cue_list() -> None:
    item = {
        "inputUrl": _watch("v1"),
        "transcript": [
            {"text": "hello", "start": 0.0, "duration": 1.5},
            {"text": "world", "start": 1.5, "duration": 1.5},
        ],
    }
    assert _transcript_from_item(item) == "hello world"


def test_error_item_has_no_transcript() -> None:
    item = {
        "inputUrl": _watch("v2"),
        "videoId": "v2",
        "error": "No captions",
        "errorCode": "NO_CAPTIONS",
    }
    assert _transcript_from_item(item) is None


# --- fetch_batch (actor run patched, no network) --------------------------------


def _client() -> WorkerTranscriptClient:
    # __init__ builds an ApifyClientAsync with a dummy token — offline, no call is
    # made until _run_batch, which every test patches.
    return WorkerTranscriptClient("dummy-token")


def _patch_run(monkeypatch, client, handler) -> list[list[str]]:
    """Patch the client's actor run to ``handler`` and record the id lists it got."""
    calls: list[list[str]] = []

    async def fake_run_batch(video_ids: list[str]) -> list[object]:
        calls.append(list(video_ids))
        return handler(video_ids)

    monkeypatch.setattr(client, "_run_batch", fake_run_batch)
    return calls


def test_fetch_batch_maps_success_and_error_by_input_url(monkeypatch) -> None:
    client = _client()
    items = [
        {
            "inputUrl": _watch("v1"),
            "transcript": [
                {"text": "hello", "start": 0.0, "duration": 1.0},
                {"text": "world", "start": 1.0, "duration": 1.0},
            ],
        },
        {"inputUrl": _watch("v2"), "error": "No captions", "errorCode": "X"},
    ]
    _patch_run(monkeypatch, client, lambda ids: items)

    out = asyncio.run(client.fetch_batch(["v1", "v2"]))

    # success maps to text, error item maps to None (→ placeholder, not a strike).
    assert out == {"v1": "hello world", "v2": None}


def test_fetch_batch_seeds_dropped_and_ignores_unrequested(monkeypatch) -> None:
    client = _client()
    items = [
        # a video the caller never asked for — ignored.
        {"inputUrl": _watch("other"), "transcript": [{"text": "x"}]},
        # an item with no parseable inputUrl — skipped.
        {"transcript": [{"text": "y"}]},
    ]
    _patch_run(monkeypatch, client, lambda ids: items)

    # v1 was requested but the actor returned nothing for it → seeded None.
    out = asyncio.run(client.fetch_batch(["v1"]))
    assert out == {"v1": None}


def test_fetch_batch_empty_list_is_a_noop(monkeypatch) -> None:
    client = _client()
    calls = _patch_run(monkeypatch, client, lambda ids: [])

    out = asyncio.run(client.fetch_batch([]))

    assert out == {}
    assert calls == []  # no actor run started for an empty miss-list


def test_fetch_batch_timeout_degrades_to_all_placeholder(monkeypatch) -> None:
    monkeypatch.setattr(
        worker_config.settings, "apify_fetch_deadline_seconds", 0.01
    )
    client = _client()

    async def slow(video_ids: list[str]) -> list[object]:
        await asyncio.sleep(5)
        return []

    monkeypatch.setattr(client, "_run_batch", slow)

    out = asyncio.run(client.fetch_batch(["v1", "v2"]))

    # the deadline fired → every requested id gets the placeholder (None), no raise.
    assert out == {"v1": None, "v2": None}


def test_fetch_batch_run_failure_degrades_to_all_placeholder(monkeypatch) -> None:
    client = _client()

    async def boom(video_ids: list[str]) -> list[object]:
        raise RuntimeError("apify unreachable")

    monkeypatch.setattr(client, "_run_batch", boom)

    out = asyncio.run(client.fetch_batch(["v1"]))

    assert out == {"v1": None}  # a run failure never aborts — all placeholder
