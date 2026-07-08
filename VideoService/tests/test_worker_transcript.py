"""Pure parsing for the Apify transcript client: cue items -> cleaned plain text.
No network. (The SRT/HTML-cleaning logic moved here from the retired scraper
transform when transcripts became a lazy, transcript-only Apify fetch.)"""

from __future__ import annotations

from src.worker.worker_apify import transcript_from_items


def test_cues_join_into_plain_text() -> None:
    items = [
        {"start": "0.0", "dur": "1.5", "text": "hello"},
        {"start": "1.5", "dur": "1.5", "text": "world"},
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
