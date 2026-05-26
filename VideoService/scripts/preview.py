"""Generate a static HTML grid of a company's videos for eyeballing the feed.

    poetry run python -m scripts.preview --app-id bjj      # one app
    poetry run python -m scripts.preview                   # every app

Reads the per-video files and writes ``apps/<app_id>/preview.html`` (next to the
YAMLs) — a filterable grid of thumbnail + title + verdict badges (good / rejected
/ no-transcript) plus a transcript snippet, so you can see at a glance what was
kept vs dropped and why. A dev helper: no server, no deps, opens in a browser.
"""

from __future__ import annotations

import argparse
import asyncio
import html
from pathlib import Path

from schema import VideoOutput, VideosOutput, VideoType
from src.api.service.videos_service import VideosService

# scripts/preview.py -> <root>/apps
_DEFAULT_APPS_ROOT = Path(__file__).resolve().parent.parent / "apps"
_PREVIEW_FILENAME = "preview.html"
_TRANSCRIPT_SNIPPET = 600  # chars of transcript shown per card

_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{app_id} — video feed preview</title>
<style>
  :root {{ color-scheme: light dark; }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; font: 14px/1.4 system-ui, sans-serif; background: #0f1115; color: #e6e6e6; }}
  header {{ position: sticky; top: 0; background: #161922; padding: 14px 20px; border-bottom: 1px solid #2a2f3a; z-index: 2; }}
  h1 {{ margin: 0 0 8px; font-size: 18px; }}
  .filters {{ margin-top: 6px; }}
  .filters button {{ font: inherit; cursor: pointer; margin: 2px 4px 2px 0; padding: 5px 11px; border-radius: 999px;
      border: 1px solid #353b48; background: #1d212b; color: #cdd3df; }}
  .filters button.on {{ background: #3b82f6; border-color: #3b82f6; color: #fff; }}
  .flabel {{ color: #9aa3b2; font-size: 12px; margin-right: 6px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 14px; padding: 18px 20px; }}
  .card {{ background: #161922; border: 1px solid #2a2f3a; border-left-width: 5px; border-radius: 10px; overflow: hidden; display: flex; flex-direction: column; }}
  .card.good {{ border-left-color: #22c55e; }}
  .card.rejected {{ border-left-color: #ef4444; }}
  .card.no_transcript {{ border-left-color: #6b7280; }}
  .card.errored {{ border-left-color: #f59e0b; }}
  .card.unclassified {{ border-left-color: #3b82f6; }}
  .thumb {{ width: 100%; aspect-ratio: 16/9; object-fit: cover; background: #000; display: block; }}
  .body {{ padding: 10px 12px; display: flex; flex-direction: column; gap: 6px; }}
  .title {{ font-weight: 600; }}
  .title a {{ color: #e6e6e6; text-decoration: none; }}
  .title a:hover {{ text-decoration: underline; }}
  .meta {{ color: #9aa3b2; font-size: 12px; }}
  .badges {{ display: flex; flex-wrap: wrap; gap: 5px; }}
  .badge {{ font-size: 11px; padding: 2px 8px; border-radius: 999px; background: #232834; color: #cdd3df; }}
  .badge.good {{ background: #14361f; color: #4ade80; }}
  .badge.rejected {{ background: #3a1717; color: #f87171; }}
  .badge.no_transcript {{ background: #2a2e36; color: #9aa3b2; }}
  .badge.errored {{ background: #3a2a12; color: #fbbf24; }}
  details {{ font-size: 12px; color: #9aa3b2; }}
  details summary {{ cursor: pointer; color: #7c93b8; }}
  .tx {{ white-space: pre-wrap; max-height: 160px; overflow: auto; margin-top: 6px; padding: 8px; background: #11141b; border-radius: 6px; }}
  .none {{ font-style: italic; color: #6b7280; }}
</style></head>
<body>
<header>
  <h1>{app_id} — {company}</h1>
  <div class="meta">{total} videos · {good} good · {rejected} rejected (LLM) · {no_transcript} no transcript · {errored} errored · {unclassified} unclassified</div>
  <div class="filters">
    <span class="flabel">Status</span>
    <button data-group="status" data-f="all" class="on">All ({total})</button>
    <button data-group="status" data-f="good">Good ({good})</button>
    <button data-group="status" data-f="rejected">Rejected ({rejected})</button>
    <button data-group="status" data-f="no_transcript">No transcript ({no_transcript})</button>
    <button data-group="status" data-f="errored">Errored ({errored})</button>
    <button data-group="status" data-f="unclassified">Unclassified ({unclassified})</button>
  </div>
  <div class="filters">
    <span class="flabel">Tag</span>
    <button data-group="tag" data-f="all" class="on">All</button>
    {tag_filters}
  </div>
</header>
<div class="grid">{cards}</div>
<script>
  const active = {{status: 'all', tag: 'all'}};
  const cards = [...document.querySelectorAll('.card')];
  document.querySelectorAll('.filters button').forEach(b => b.onclick = () => {{
    const g = b.dataset.group;
    document.querySelectorAll('.filters button[data-group="' + g + '"]').forEach(x => x.classList.remove('on'));
    b.classList.add('on');
    active[g] = b.dataset.f;
    cards.forEach(c => {{
      const okStatus = active.status === 'all' || c.dataset.status === active.status;
      const okTag = active.tag === 'all' || c.dataset.tag === active.tag;
      c.style.display = (okStatus && okTag) ? '' : 'none';
    }});
  }});
</script>
</body></html>
"""


# reason -> filter/colour bucket; any is_good=False without a known reason falls
# back to "rejected".
_REASON_BUCKET = {
    "no_transcript": "no_transcript",
    "errored_out": "errored",
    "llm_classified_bad": "rejected",
}


def _status(v: VideoOutput) -> str:
    """The filter/colour bucket for one video."""
    if v.is_good is True:
        return "good"
    if v.is_good is None:
        return "unclassified"
    return _REASON_BUCKET.get(v.reason.value if v.reason else "", "rejected")


def _fmt_views(n: int | None) -> str:
    if n is None:
        return "— views"
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M views"
    if n >= 1_000:
        return f"{n / 1_000:.0f}K views"
    return f"{n} views"


def _badge(label: str, cls: str = "") -> str:
    return f'<span class="badge {cls}">{html.escape(label)}</span>'


def _tag(v: VideoOutput) -> str:
    """The tag-filter bucket for one video (genre value, or 'untagged')."""
    return v.tag.value if v.tag else "untagged"


def _card(v: VideoOutput) -> str:
    status = _status(v)
    badges = [_badge(v.tag.value) if v.tag else _badge("untagged")]
    if status == "good":
        badges.append(_badge("✓ good", "good"))
    elif status == "rejected":
        badges.append(_badge("✗ rejected (LLM)", "rejected"))
    elif status == "no_transcript":
        badges.append(_badge("no transcript", "no_transcript"))
    elif status == "errored":
        badges.append(_badge("errored", "errored"))
    else:
        badges.append(_badge("unclassified"))

    tx = (v.transcript or "").strip()
    if tx:
        snippet = html.escape(tx[:_TRANSCRIPT_SNIPPET]) + ("…" if len(tx) > _TRANSCRIPT_SNIPPET else "")
        tx_block = (
            f'<details><summary>transcript ({len(tx):,} chars)</summary>'
            f'<div class="tx">{snippet}</div></details>'
        )
    elif v.transcript_error:
        tx_block = f'<div class="none">no transcript — {html.escape(v.transcript_error)}</div>'
    else:
        tx_block = '<div class="none">no transcript</div>'

    return f"""<div class="card {status}" data-status="{status}" data-tag="{_tag(v)}">
  <a href="{html.escape(v.url)}" target="_blank" rel="noopener">
    <img class="thumb" loading="lazy" src="{html.escape(v.thumbnail_url)}" alt=""></a>
  <div class="body">
    <div class="title"><a href="{html.escape(v.url)}" target="_blank" rel="noopener">{html.escape(v.title)}</a></div>
    <div class="meta">{html.escape(v.channel_name)} · {_fmt_views(v.view_count)}</div>
    <div class="badges">{''.join(badges)}</div>
    {tx_block}
  </div>
</div>"""


def _tag_filter_buttons(output: VideosOutput) -> str:
    """One tag button per genre present, with its count. Ordered by the fixed
    VideoType vocabulary, then 'untagged' last."""
    counts: dict[str, int] = {}
    for v in output.videos:
        counts[_tag(v)] = counts.get(_tag(v), 0) + 1
    order = [t.value for t in VideoType] + ["untagged"]
    present = sorted(counts, key=lambda t: order.index(t) if t in order else len(order))
    return "\n    ".join(
        f'<button data-group="tag" data-f="{html.escape(t)}">{html.escape(t)} ({counts[t]})</button>'
        for t in present
    )


def render(output: VideosOutput) -> str:
    counts = {k: 0 for k in ("good", "rejected", "no_transcript", "errored", "unclassified")}
    for v in output.videos:
        counts[_status(v)] += 1
    cards = "\n".join(_card(v) for v in output.videos)
    return _PAGE.format(
        app_id=html.escape(output.app_id),
        company=html.escape(output.company_name),
        total=len(output.videos),
        tag_filters=_tag_filter_buttons(output),
        cards=cards,
        **counts,
    )


def build(app_id: str, apps_root: Path) -> Path:
    output = asyncio.run(VideosService(apps_root=apps_root).load_output(app_id))
    out_path = apps_root / app_id / _PREVIEW_FILENAME
    out_path.write_text(render(output), encoding="utf-8")
    return out_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", help="company id under apps/ (default: all apps)")
    parser.add_argument("--apps-root", type=Path, default=_DEFAULT_APPS_ROOT)
    args = parser.parse_args(argv)

    if args.app_id:
        app_ids = [args.app_id]
    else:
        app_ids = [p.parent.name for p in sorted(args.apps_root.glob("*/videos_output.yaml"))]
    for app_id in app_ids:
        path = build(app_id, args.apps_root)
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
