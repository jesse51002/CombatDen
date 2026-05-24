"""Audit helpers for `videos_output.yaml` — used by the `audit-output` skill so
the LLM reasons over a **compact title list** instead of loading the whole output
file into context.

    # compact list: one `<video_id>\t<title>\t<channel>` line per video
    poetry run python -m scripts.youtube_batch.audit list --app-id combatden

    # drop videos by id; survivors rewritten in place, removed ones logged
    poetry run python -m scripts.youtube_batch.audit remove --app-id combatden \
        --ids VIDEOID1,VIDEOID2 --reason "negative about muay thai"

`remove` rewrites `videos_output.yaml` with the survivors (so the API serves the
clean set immediately) and appends each removed video — plus the reason and a
timestamp — to `videos_output.removed.yaml` for transparency and recovery.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import yaml

from schema.video_output import VideoOutput
from src.api.service.videos_service import VideosService

# scripts/youtube_batch/audit.py -> <root>/apps
_DEFAULT_APPS_ROOT = Path(__file__).resolve().parent.parent.parent / "apps"
OUTPUT_FILENAME = "videos_output.yaml"
REMOVED_FILENAME = "videos_output.removed.yaml"


def video_id_from_url(url: str) -> str:
    """The YouTube video id from a watch URL (its `v` query param)."""
    return (parse_qs(urlparse(url).query).get("v") or [""])[0]


def partition_videos(
    videos: list[VideoOutput], remove_ids: set[str]
) -> tuple[list[VideoOutput], list[VideoOutput]]:
    """Split videos into (kept, removed) by video id, preserving order."""
    kept: list[VideoOutput] = []
    removed: list[VideoOutput] = []
    for video in videos:
        target = removed if video_id_from_url(video.url) in remove_ids else kept
        target.append(video)
    return kept, removed


def _dump(data: object, path: Path) -> None:
    path.write_text(
        yaml.safe_dump(
            data, sort_keys=False, allow_unicode=True, default_flow_style=False
        ),
        encoding="utf-8",
    )


def _load_removed_log(path: Path) -> list[dict]:
    """Existing removed-records list, or [] if the sidecar doesn't exist yet."""
    if not path.is_file():
        return []
    return (yaml.safe_load(path.read_text()) or {}).get("removed", [])


def list_titles(app_id: str, apps_root: Path) -> None:
    """Print one compact `<id>\t<title>\t<channel>` line per video."""
    output = asyncio.run(VideosService(apps_root=apps_root).load_output(app_id))
    for video in output.videos:
        print(f"{video_id_from_url(video.url)}\t{video.title}\t{video.channel_name}")


def remove_videos(
    app_id: str, apps_root: Path, ids: list[str], reason: str
) -> None:
    """Drop the given video ids from videos_output.yaml; log the removals."""
    output = asyncio.run(VideosService(apps_root=apps_root).load_output(app_id))
    remove_ids = {i.strip() for i in ids if i.strip()}

    kept, removed = partition_videos(output.videos, remove_ids)
    matched = {video_id_from_url(v.url) for v in removed}
    for missing in sorted(remove_ids - matched):
        print(f"warning: no video with id {missing!r}", file=sys.stderr)
    if not removed:
        print("nothing removed", file=sys.stderr)
        return

    app_dir = apps_root / app_id
    survivors = output.model_copy(update={"videos": kept})
    _dump(survivors.model_dump(mode="json"), app_dir / OUTPUT_FILENAME)

    now = datetime.now(timezone.utc).isoformat()
    log = _load_removed_log(app_dir / REMOVED_FILENAME)
    for video in removed:
        record = video.model_dump(mode="json")
        record["removed_at"] = now
        record["removed_reason"] = reason
        log.append(record)
    _dump({"removed": log}, app_dir / REMOVED_FILENAME)

    print(f"removed {len(removed)}, kept {len(kept)} -> {OUTPUT_FILENAME}")


def main(argv: list[str] | None = None) -> int:
    # Shared options live on a parent parser so --apps-root is accepted whether
    # it comes before or after the subcommand.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--app-id", required=True)
    common.add_argument("--apps-root", type=Path, default=_DEFAULT_APPS_ROOT)

    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser(
        "list", parents=[common], help="print a compact id/title/channel list"
    )
    p_remove = sub.add_parser(
        "remove", parents=[common], help="drop videos by id, logging removals"
    )
    p_remove.add_argument("--ids", required=True, help="comma-separated video ids")
    p_remove.add_argument("--reason", required=True, help="why they were removed")

    args = parser.parse_args(argv)
    if args.command == "list":
        list_titles(args.app_id, args.apps_root)
    else:
        remove_videos(
            args.app_id, args.apps_root, args.ids.split(","), args.reason
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
