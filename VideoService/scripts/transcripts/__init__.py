"""Transcript-fetch pass: enrich a company's fetched feed with video transcripts
(via Apify) so the classifier judges real content, not just title + description.

A separate manual pass from the YouTube fetch and the classify pass: it costs
money per transcript and is slow (an async Apify run), so it is run on demand and
its result is cached on each per-video file.
"""
