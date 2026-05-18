"""Golden-dataset eval for the cutout validator (``background_check.md``).

This is a real test, just an expensive one: it calls the live vision model
once per hand-labeled image and checks the verdict against the label in
``data/cutouts/manifest.yaml``. A mock cannot test a prompt — only the real
model can tell us whether the prompt actually distinguishes a composed
subject from leftover backdrop.

It is tagged ``golden`` and excluded from the default ``make test`` (which
stays offline, fast, free). Run it deliberately::

    make test-golden                  # whole corpus; scorecard streamed
    make test-golden ARGS="-k web"    # subset by name

Cost is bounded: the corpus is evaluated **once** per session (shared
fixture); keep ``manifest.yaml`` small.

Strictness: this is run deliberately by a human (it is not in CI), so the
bar is **every labeled case correct** — the default threshold is 1.0. The
composed-subject regression case is additionally asserted hard and
individually — it is the exact bug that started this. The full per-image
breakdown is always printed so every miss is visible. ``CUTOUT_GOLDEN_
THRESHOLD`` can *loosen* the gate for a deliberate, known-transient run
(e.g. ``CUTOUT_GOLDEN_THRESHOLD=0.85``); the default stays all-must-pass.
"""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from pathlib import Path

import pytest
import yaml

from src.modules.images.background_service import BackgroundService
from src.shared.services.llm_client import LiteLLMClient

pytestmark = pytest.mark.golden

_CUTOUTS = Path(__file__).parent / "data" / "cutouts"
_MANIFEST = _CUTOUTS / "manifest.yaml"
_DEFAULT_THRESHOLD = 1.0  # every labeled case must be correct


@dataclass(frozen=True)
class _Result:
    name: str
    category: str
    origin: str
    expected_ok: bool
    actual_ok: bool
    reason: str

    @property
    def correct(self) -> bool:
        return self.actual_ok == self.expected_ok


def _entries() -> list[dict]:
    manifest = yaml.safe_load(_MANIFEST.read_text(encoding="utf-8"))
    return manifest["images"]


@pytest.fixture(scope="session")
def golden_results() -> list[_Result]:
    """Evaluate the whole corpus once (bounds cost to one call per image)."""
    validator = BackgroundService(llm=LiteLLMClient())
    results: list[_Result] = []
    for entry in _entries():
        before = _CUTOUTS / entry["before"]
        after = _CUTOUTS / entry["file"]
        assert before.exists(), f"missing BEFORE fixture: {before}"
        assert after.exists(), f"missing AFTER fixture: {after}"
        verdict = asyncio.run(validator.validate_cutout(before, after))
        results.append(
            _Result(
                name=entry["name"],
                category=entry["category"],
                origin=entry["origin"],
                expected_ok=bool(entry["expected_ok"]),
                actual_ok=bool(verdict.ok),
                reason=verdict.reason,
            )
        )
    return results


def _scorecard(results: list[_Result]) -> str:
    correct = sum(r.correct for r in results)
    lines = [
        "",
        f"cutout golden scorecard — {correct}/{len(results)} correct",
        "-" * 72,
    ]
    for r in sorted(results, key=lambda x: (x.correct, x.category)):
        mark = "PASS" if r.correct else "FAIL"
        lines.append(
            f"  [{mark}] {r.name:<28} exp={r.expected_ok!s:<5} "
            f"got={r.actual_ok!s:<5} ({r.category})"
        )
        if not r.correct:
            lines.append(f"         reason: {r.reason}")
    lines.append("-" * 72)
    return "\n".join(lines)


def test_cutout_regression_composed_subject(
    golden_results: list[_Result],
) -> None:
    """The exact bug: a composed subject (icon on a disc/badge) must not be
    rejected as if the disc were leftover background. Hard, individual."""
    regression = {e["name"] for e in _entries() if e.get("regression")}
    assert regression, "no regression-tagged image in the manifest"
    for r in golden_results:
        if r.name in regression:
            assert r.actual_ok is True, (
                f"REGRESSION: {r.name} wrongly rejected — {r.reason}"
            )


def test_cutout_golden_dataset(golden_results: list[_Result]) -> None:
    """Aggregate accuracy across the labeled corpus."""
    card = _scorecard(golden_results)
    print(card)
    threshold = float(
        os.environ.get("CUTOUT_GOLDEN_THRESHOLD", _DEFAULT_THRESHOLD)
    )
    accuracy = sum(r.correct for r in golden_results) / len(golden_results)
    assert accuracy >= threshold, (
        f"cutout validator accuracy {accuracy:.0%} < "
        f"required {threshold:.0%}\n{card}"
    )
