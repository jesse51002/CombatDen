"""Studio app tests — launch, stream, poll, and the brief commit path.

Every test runs against a temp apps root and a temp ``.studio`` dir, with a
STUBBED pipeline: a real run costs about a dollar of provider spend, so
nothing here generates anything. The stub emits the same ``ProgressEvent``s
the real executor does and writes the same files, which is all the studio
sees of it.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

import pytest
import yaml
from fastapi.testclient import TestClient

from src.executor.progress_event import ProgressEvent, ProgressEventKind
from src.studio.config import settings
from src.studio.main import app
from src.studio.service import brief_service as brief_service_module
from src.studio.service import run_launcher as run_launcher_module
from src.studio.service import run_reader as run_reader_module
from src.studio.service import run_registry as run_registry_module
from src.studio.service.brief_service import BriefService
from src.studio.service.run_launcher import RunLauncher
from src.studio.service.run_reader import RunReader
from src.studio.service.run_registry import RunRegistry

FIXTURE_APP_YAML = (
    Path(__file__).resolve().parent / "data" / "apps" / "demo" / "app.yaml"
)
APP = "demo"

_BRIEF = {
    "name": "Iron & Ash",
    "short_desc": "Heavy, warm, unfussy.",
    "long_desc": "A soot-and-ember gym brand: warm metal, hard edges.",
    "colors_description": "charcoal base with an ember orange accent",
    "mode": "dark",
}


def _launch_body(run_name: str, **overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "app_id": APP,
        "run_name": run_name,
        "brief": {
            "design_direction": {
                "name": _BRIEF["name"],
                "short_desc": _BRIEF["short_desc"],
                "long_desc": _BRIEF["long_desc"],
            },
            "colors_direction": {
                "description": _BRIEF["colors_description"],
                "mode": _BRIEF["mode"],
            },
        },
    }
    body.update(overrides)
    return body


class _StubPipeline:
    """Emits a realistic event stream and writes one image, no spend.

    ``_GATE`` (set per-test) makes the run block until a sentinel file
    appears, which is how the "one run at a time" test keeps a run in
    flight while it fires a second launch.
    """

    gate: Path | None = None

    async def run(self, run_ctx, *, seed=None, progress=None):
        await self._emit(
            progress,
            ProgressEvent(
                kind=ProgressEventKind.RUN_STARTED,
                app_id=run_ctx.app_id,
                run_id=run_ctx.run_id,
                total_levels=2,
                total_nodes=2,
            ),
        )
        await self._emit(
            progress,
            ProgressEvent(
                kind=ProgressEventKind.LEVEL_STARTED,
                level=0,
                level_nodes=["color"],
                total_levels=2,
            ),
        )
        await self._emit(
            progress,
            ProgressEvent(
                kind=ProgressEventKind.NODE_STARTED, node="color", level=0
            ),
        )
        await self._emit(
            progress,
            ProgressEvent(
                kind=ProgressEventKind.NODE_FINISHED,
                node="color",
                level=0,
                ok=True,
                elapsed_seconds=0.01,
            ),
        )
        if self.gate is not None:
            await self._wait_for_gate()
        # The real ImageNode writes final_images/<slot>.png before its
        # node_finished lands; the studio's image endpoint depends on that
        # order, so the stub keeps it.
        image = Path(str(run_ctx.image_path("hero")))
        image.parent.mkdir(parents=True, exist_ok=True)
        image.write_bytes(b"\x89PNG stub hero")
        await self._emit(
            progress,
            ProgressEvent(
                kind=ProgressEventKind.NODE_FINISHED,
                node="hero",
                image_slot="hero",
                level=1,
                ok=True,
                elapsed_seconds=0.02,
            ),
        )
        await self._emit(
            progress,
            ProgressEvent(
                kind=ProgressEventKind.RUN_FINISHED,
                app_id=run_ctx.app_id,
                run_id=run_ctx.run_id,
                elapsed_seconds=0.05,
                cost=0.0,
                generated=["color", "hero"],
            ),
        )
        return _StubResult(run_ctx)

    async def _wait_for_gate(self) -> None:
        import asyncio

        assert self.gate is not None
        for _ in range(500):  # 5s ceiling; the test releases far sooner
            if self.gate.exists():
                return
            await asyncio.sleep(0.01)

    @staticmethod
    async def _emit(progress, event: ProgressEvent) -> None:
        if progress is not None:
            await progress.emit(event)


class _StubResult:
    def __init__(self, run_ctx) -> None:
        self.run_ctx = run_ctx


class _StubWriter:
    """Writes the one artifact the studio cares about: output.yaml."""

    def write(self, result: _StubResult, run_ctx, **_kwargs) -> None:
        run_ctx.output_path().write_text("app: demo\n", encoding="utf-8")


class _FailingPipeline:
    async def run(self, run_ctx, *, seed=None, progress=None):
        raise RuntimeError("provider melted")


@pytest.fixture
def studio(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """A studio wired to temp dirs, with the pipeline + writer stubbed.

    Yields ``(client, apps_root, studio_root)``. The client is entered as a
    context manager so every request shares ONE event loop — without that,
    the background run task started by a POST would be orphaned when the
    next request opened a fresh one.
    """
    apps_root = tmp_path / "apps"
    (apps_root / APP).mkdir(parents=True)
    (apps_root / APP / "app.yaml").write_text(
        FIXTURE_APP_YAML.read_text(encoding="utf-8"), encoding="utf-8"
    )
    studio_root = tmp_path / ".studio"

    monkeypatch.setattr(settings, "apps_root", apps_root)
    monkeypatch.setattr(settings, "studio_root", studio_root)

    registry = RunRegistry(settings.runs_dir)
    briefs = BriefService(settings.briefs_dir)
    monkeypatch.setattr(run_registry_module, "_registry", registry)
    monkeypatch.setattr(brief_service_module, "_service", briefs)
    monkeypatch.setattr(
        run_launcher_module,
        "_launcher",
        RunLauncher(registry, briefs, apps_root),
    )
    monkeypatch.setattr(
        run_reader_module, "_reader", RunReader(registry, apps_root)
    )
    monkeypatch.setattr(run_launcher_module, "Pipeline", _StubPipeline)
    monkeypatch.setattr(run_launcher_module, "Writer", _StubWriter)
    _StubPipeline.gate = None

    with TestClient(app) as client:
        yield client, apps_root, studio_root


def _records(client: TestClient, run_id: str) -> list[dict[str, Any]]:
    """Drain the SSE stream into the records it carried."""
    out: list[dict[str, Any]] = []
    with client.stream("GET", f"/runs/{run_id}/events") as resp:
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("text/event-stream")
        for line in resp.iter_lines():
            if line.startswith("data: "):
                out.append(json.loads(line.removeprefix("data: ")))
    return out


def _await_terminal(client: TestClient, run_id: str) -> dict[str, Any]:
    """Poll the snapshot until the run settles (the poll fallback path)."""
    for _ in range(500):
        body = client.get(f"/runs/{run_id}").json()
        if body["status"] != "running":
            return body
        time.sleep(0.01)
    raise AssertionError(f"run {run_id} never settled")


# --- health + brief commit -------------------------------------------------


def test_health(studio) -> None:
    client, _, _ = studio
    assert client.get("/health").json() == {"status": "ok"}


def test_commit_brief_writes_a_validated_yaml(studio) -> None:
    client, _, studio_root = studio

    resp = client.post("/briefs", json=_BRIEF)

    assert resp.status_code == 201
    body = resp.json()
    # The design name slugifies into the filename stem.
    assert body["slug"] == "iron-ash"
    written = studio_root / "briefs" / "iron-ash.yaml"
    assert written.is_file()
    # Exactly the five-field contract, nothing invented.
    saved = yaml.safe_load(written.read_text())
    assert saved == {
        "design_direction": {
            "name": _BRIEF["name"],
            "short_desc": _BRIEF["short_desc"],
            "long_desc": _BRIEF["long_desc"],
        },
        "colors_direction": {
            "description": _BRIEF["colors_description"],
            "mode": "dark",
        },
    }
    assert body["brief"] == saved


def test_commit_brief_never_touches_the_checked_in_customization(
    studio,
) -> None:
    """The brief lands in .studio/briefs/, never apps/<app>/customization.yaml
    — overwriting that would silently change what `make run` generates."""
    client, apps_root, _ = studio
    client.post("/briefs", json=_BRIEF)
    assert not (apps_root / APP / "customization.yaml").exists()


def test_commit_brief_rejects_a_blank_field(studio) -> None:
    """The non-empty validators on Customization are the authority; a blank
    field surfaces as a 422, not a written file."""
    client, _, studio_root = studio

    resp = client.post("/briefs", json={**_BRIEF, "short_desc": "   "})

    assert resp.status_code == 422
    assert not (studio_root / "briefs").exists()


def test_commit_brief_rejects_a_sixth_field(studio) -> None:
    """extra='forbid' all the way through: there is no sixth brief field."""
    resp = studio[0].post("/briefs", json={**_BRIEF, "vibe": "spicy"})
    assert resp.status_code == 422


def test_commit_brief_takes_an_explicit_slug(studio) -> None:
    client, _, studio_root = studio
    resp = client.post("/briefs", json={**_BRIEF, "slug": "my-draft"})
    assert resp.status_code == 201
    assert (studio_root / "briefs" / "my-draft.yaml").is_file()


def test_commit_brief_refuses_an_unsluggable_name(studio) -> None:
    resp = studio[0].post("/briefs", json={**_BRIEF, "name": "!!!"})
    assert resp.status_code == 422
    assert "slug" in resp.json()["detail"]


# --- launching + streaming -------------------------------------------------


def test_launch_returns_immediately_and_streams_the_whole_run(
    studio,
) -> None:
    client, apps_root, studio_root = studio

    resp = client.post("/runs", json=_launch_body("ironash"))

    assert resp.status_code == 202
    accepted = resp.json()
    assert accepted["app_id"] == APP
    assert accepted["run_name"] == "ironash"
    assert accepted["status"] == "running"
    run_id = accepted["run_id"]

    records = _records(client, run_id)

    # Replayed from index 0, in order, ending on the terminal record.
    assert [r["index"] for r in records] == list(range(len(records)))
    assert records[0]["kind"] == "launched"
    assert records[0]["app_id"] == APP
    assert records[0]["run_name"] == "ironash"
    assert records[-1]["kind"] == "settled"
    assert records[-1]["status"] == "succeeded"
    # The executor's events ride through verbatim.
    kinds = [
        r["event"]["kind"] for r in records if r["kind"] == "progress"
    ]
    assert kinds[0] == "run_started"
    assert kinds[-1] == "run_finished"
    # The image slot a client needs in order to fetch what just landed.
    finished = [
        r["event"]
        for r in records
        if r["kind"] == "progress"
        and r["event"]["kind"] == "node_finished"
    ]
    assert [e["image_slot"] for e in finished] == [None, "hero"]

    # The run really was produced into a NEW dir under the apps root.
    assert (apps_root / APP / "ironash" / "output.yaml").is_file()
    # And the durable log holds exactly what the stream carried.
    log = studio_root / "runs" / f"{run_id}.jsonl"
    lines = [
        json.loads(line)
        for line in log.read_text().splitlines()
        if line.strip()
    ]
    assert lines == records


def test_a_late_subscriber_is_replayed_from_zero(studio) -> None:
    """The demo's whole point: a tab opened after the run finished still
    sees every event, not an empty stream."""
    client, _, _ = studio
    run_id = client.post("/runs", json=_launch_body("late")).json()["run_id"]
    _await_terminal(client, run_id)

    records = _records(client, run_id)

    assert records[0]["index"] == 0
    assert records[0]["kind"] == "launched"
    assert records[-1]["kind"] == "settled"


def test_snapshot_carries_the_same_records_as_the_stream(studio) -> None:
    client, _, _ = studio
    run_id = client.post("/runs", json=_launch_body("poll")).json()["run_id"]

    snapshot = _await_terminal(client, run_id)
    records = _records(client, run_id)

    assert snapshot["status"] == "succeeded"
    assert snapshot["run_name"] == "poll"
    assert snapshot["finished_at"]
    assert snapshot["error"] is None
    assert snapshot["records"] == records


def test_a_failed_run_settles_with_the_error(studio, monkeypatch) -> None:
    client, _, _ = studio
    monkeypatch.setattr(run_launcher_module, "Pipeline", _FailingPipeline)

    run_id = client.post("/runs", json=_launch_body("boom")).json()["run_id"]
    snapshot = _await_terminal(client, run_id)

    assert snapshot["status"] == "failed"
    assert "provider melted" in snapshot["error"]
    # A watcher still gets a terminal record — the stream always ends.
    assert _records(client, run_id)[-1]["kind"] == "settled"


# --- the refusals ----------------------------------------------------------


def test_only_one_run_at_a_time(studio, tmp_path: Path) -> None:
    """Providers rate-limit, so a second launch is refused (409) rather than
    queued — and the refusal names what is already running."""
    client, _, _ = studio
    gate = tmp_path / "release"
    _StubPipeline.gate = gate

    first = client.post("/runs", json=_launch_body("first")).json()

    resp = client.post("/runs", json=_launch_body("second"))

    assert resp.status_code == 409
    detail = resp.json()["detail"]
    assert detail["active_run_id"] == first["run_id"]
    assert detail["active_run_name"] == "first"
    assert "one at a time" in detail["message"]

    gate.touch()
    _await_terminal(client, first["run_id"])
    # With the slot free, the next launch is accepted.
    assert client.post("/runs", json=_launch_body("second")).status_code == 202


def test_launch_refuses_an_existing_run_name(studio) -> None:
    """The launch path only ever CREATES a run dir, so the pipeline's
    destructive in-place overwrite is unreachable from the browser."""
    client, apps_root, _ = studio
    (apps_root / APP / "taken").mkdir(parents=True)
    (apps_root / APP / "taken" / "output.yaml").write_text("app: demo\n")

    resp = client.post("/runs", json=_launch_body("taken"))

    assert resp.status_code == 409
    assert "already exists" in resp.json()["detail"]
    # Untouched.
    assert (apps_root / APP / "taken" / "output.yaml").read_text() == (
        "app: demo\n"
    )


def test_launch_rejects_a_run_name_that_escapes_the_app_dir(studio) -> None:
    for bad in ("../evil", "a/b", "..", ".", ""):
        resp = studio[0].post("/runs", json=_launch_body(bad))
        assert resp.status_code == 422, bad


def test_launch_rejects_an_unknown_app(studio) -> None:
    resp = studio[0].post("/runs", json=_launch_body("x", app_id="nosuch"))
    assert resp.status_code == 404


def test_launch_needs_exactly_one_brief_source(studio) -> None:
    client, _, _ = studio
    both = _launch_body("x")
    both["brief_slug"] = "iron-ash"
    assert client.post("/runs", json=both).status_code == 422

    neither = _launch_body("x")
    del neither["brief"]
    assert client.post("/runs", json=neither).status_code == 422


def test_launch_from_a_saved_brief_slug(studio) -> None:
    """The form's commit and the launch are two halves of one flow — and the
    agent's eventual accept path will reuse the same commit."""
    client, apps_root, _ = studio
    slug = client.post("/briefs", json=_BRIEF).json()["slug"]

    body = _launch_body("fromslug")
    del body["brief"]
    body["brief_slug"] = slug
    run_id = client.post("/runs", json=body).json()["run_id"]

    assert _await_terminal(client, run_id)["status"] == "succeeded"
    assert (apps_root / APP / "fromslug" / "output.yaml").is_file()


def test_launch_from_an_unknown_brief_slug(studio) -> None:
    body = _launch_body("x")
    del body["brief"]
    body["brief_slug"] = "never-written"
    assert studio[0].post("/runs", json=body).status_code == 404


# --- reading a run ---------------------------------------------------------


def test_images_are_servable_as_soon_as_they_land(studio, tmp_path) -> None:
    """The read API can't do this — it loads output.yaml first, which only
    exists once the whole run finishes. The studio serves the file itself."""
    client, _, _ = studio
    gate = tmp_path / "release"
    _StubPipeline.gate = gate

    run_id = client.post("/runs", json=_launch_body("live")).json()["run_id"]
    # Mid-run: the image has not been produced yet.
    assert client.get(f"/runs/{run_id}/images/hero").status_code == 404

    gate.touch()
    _await_terminal(client, run_id)

    resp = client.get(f"/runs/{run_id}/images/hero")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/png"
    assert resp.content == b"\x89PNG stub hero"


def test_unknown_run_and_slot_are_404(studio) -> None:
    client, _, _ = studio
    run_id = client.post("/runs", json=_launch_body("r")).json()["run_id"]
    _await_terminal(client, run_id)

    assert client.get(f"/runs/{run_id}/images/nosuch").status_code == 404
    assert client.get("/runs/" + "0" * 32).status_code == 404
    assert client.get("/runs/" + "0" * 32 + "/events").status_code == 404


def test_a_malformed_run_id_never_becomes_a_path(studio) -> None:
    """Run ids are uuid4 hex and are pattern-checked before they are joined
    onto .studio/runs/ — a traversal attempt is a 404, not a read."""
    client, _, _ = studio
    assert client.get("/runs/..%2F..%2Fetc%2Fpasswd").status_code == 404
    assert client.get("/runs/not-a-uuid").status_code == 404


def test_active_reports_the_in_flight_run(studio, tmp_path: Path) -> None:
    client, _, _ = studio
    assert client.get("/runs/active").json() is None

    gate = tmp_path / "release"
    _StubPipeline.gate = gate
    run_id = client.post("/runs", json=_launch_body("busy")).json()["run_id"]

    active = client.get("/runs/active").json()
    assert active["run_id"] == run_id
    assert active["status"] == "running"

    gate.touch()
    _await_terminal(client, run_id)
    assert client.get("/runs/active").json() is None


def test_a_log_without_a_terminal_record_reads_as_crashed(studio) -> None:
    """The reason the durable log exists: output.yaml presence cannot tell
    'still going' from 'the process died half way'. A non-terminal last line
    can."""
    client, _, studio_root = studio
    run_id = "b" * 32
    log = studio_root / "runs" / f"{run_id}.jsonl"
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(
        json.dumps(
            {
                "kind": "launched",
                "index": 0,
                "at": "2026-07-27T00:00:00+00:00",
                "run_id": run_id,
                "app_id": APP,
                "run_name": "halfway",
            }
        )
        + "\n"
        + json.dumps(
            {
                "kind": "progress",
                "index": 1,
                "at": "2026-07-27T00:00:01+00:00",
                "event": {"kind": "run_started", "app_id": APP},
            }
        )
        + "\n",
        encoding="utf-8",
    )

    snapshot = client.get(f"/runs/{run_id}").json()

    assert snapshot["status"] == "crashed"
    assert snapshot["run_name"] == "halfway"
    assert "died" in snapshot["error"]
    # A subscriber to a crashed run still gets a terminal record, so its
    # EventSource can close instead of reconnecting forever.
    records = _records(client, run_id)
    assert records[-1]["kind"] == "settled"
    assert records[-1]["status"] == "crashed"
