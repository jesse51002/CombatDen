"""Tests for the text module: TextSlot input clamping, the response
model, the per-slot retry loop, and the prompt builder."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError

from schema import AppFormat, Customization, TextSet, TextSlot
from src.core.run_context import RunContext
from src.core.util import load_yaml
from src.modules.base import DependencyKind
from src.modules.texts.text_generation_service import (
    MAX_RETRIES,
    TEXT_PROMPT_PATH,
    TextGenerationService,
)
from src.modules.texts.text_models import (
    LLMTextResponse,
    build_text_response_model,
)
from src.modules.texts.text_node import TextNode

# Committed fixture tree (the same demo app every module test uses).
_FIXTURE_APP = Path(__file__).resolve().parent / "data" / "apps" / "demo"
APP_YAML = _FIXTURE_APP / "app.yaml"
CUST_YAML = _FIXTURE_APP / "customization.yaml"


def _run_ctx(tmp_path: Path) -> RunContext:
    app = AppFormat.model_validate(load_yaml(APP_YAML))
    cust = Customization.model_validate(load_yaml(CUST_YAML))
    return RunContext(app, cust, tmp_path)


# --- TextSlot input validation --------------------------------------------


def test_text_slot_clamps_absurd_max_chars() -> None:
    """A YAML typo (max_chars: 1_000_000) clamps to the ceiling at parse."""
    slot = TextSlot.model_validate(
        {
            "id": "x",
            "description": "a slot",
            "max_words": 5,
            "max_chars": 1_000_000,
        }
    )
    assert slot.max_chars == 200  # TEXT_MAX_CHARS_CEILING


def test_text_slot_clamps_zero_max_words_up_to_floor() -> None:
    """A YAML typo (max_words: 0) clamps up to 1 — the LLM is always
    asked to produce at least one word."""
    slot = TextSlot.model_validate(
        {
            "id": "x",
            "description": "a slot",
            "max_words": 0,
            "max_chars": 20,
        }
    )
    assert slot.max_words == 1


def test_text_slot_min_clamped_down_to_max_when_inverted() -> None:
    """A YAML with min > max collapses min down to max (no validation
    error — the user clearly wants 'exactly N words' but typoed
    higher; the pipeline doesn't fail their app on it)."""
    slot = TextSlot.model_validate(
        {
            "id": "x",
            "description": "a slot",
            "min_words": 10,
            "max_words": 3,
            "min_chars": 50,
            "max_chars": 20,
        }
    )
    assert slot.min_words == slot.max_words == 3
    assert slot.min_chars == slot.max_chars == 20


# --- LLMTextResponse + response model -------------------------------------


def test_llm_text_response_rejects_extra_fields() -> None:
    """The narrow per-slot wire shape forbids extras."""
    with pytest.raises(ValidationError):
        LLMTextResponse(value="x", display_name="y")  # type: ignore[call-arg]


def test_text_response_model_keys_by_slot_ids() -> None:
    """The closed wire schema has one required field per slot id."""
    model = build_text_response_model(["booked_screen", "cancel_cta"])
    instance = model(
        booked_screen=LLMTextResponse(value="ok"),
        cancel_cta=LLMTextResponse(value="ok"),
    )
    assert instance.booked_screen.value == "ok"
    assert instance.cancel_cta.value == "ok"


def test_text_response_model_rejects_missing_slot() -> None:
    """A missing slot fails validation (the existing complete_structured
    retry loop catches it and re-asks)."""
    model = build_text_response_model(["a", "b"])
    with pytest.raises(ValidationError) as exc:
        model.model_validate_json('{"a": {"value": "ok"}}')
    assert "b" in str(exc.value)


# --- TextGenerationService: retry loop ------------------------------------


class _ScriptedLLM:
    """Records the LLM call sequence and returns canned per-slot values.

    ``responses`` is a list of dicts (one per call) keyed by slot id.
    Each call constructs the per-request closed response model the
    caller built and returns it (matching what LiteLLMClient does).
    """

    def __init__(self, responses: list[dict[str, str]]) -> None:
        self._responses = responses
        self.calls: list[dict[str, Any]] = []

    async def complete_structured(
        self, messages: list[dict], *, schema: Any, model: str
    ) -> Any:
        idx = len(self.calls)
        self.calls.append({"messages": messages, "schema": schema, "model": model})
        if idx >= len(self._responses):
            raise AssertionError(
                f"LLM was called {idx + 1} times; only "
                f"{len(self._responses)} scripted responses"
            )
        payload = self._responses[idx]
        return schema(
            **{sid: LLMTextResponse(value=v) for sid, v in payload.items()}
        )

    async def complete(self, *args: Any, **kwargs: Any) -> Any:
        raise AssertionError("complete() not expected")


def test_resolve_happy_path_single_call(tmp_path: Path) -> None:
    """All slots pass bounds on the first call → exactly one LLM round-trip."""
    ctx = _run_ctx(tmp_path)
    llm = _ScriptedLLM(
        [
            {
                "booked_screen": "Locked in.",
                "cancel_cta": "Cancel",
                "home_greeting": "Welcome back, fighter.",
            }
        ]
    )
    out = asyncio.run(TextGenerationService(llm).resolve(ctx))

    assert isinstance(out, TextSet)
    assert set(out.texts) == {"booked_screen", "cancel_cta", "home_greeting"}
    assert out.texts["booked_screen"].value == "Locked in."
    assert len(llm.calls) == 1


def test_resolve_retries_only_violators(tmp_path: Path) -> None:
    """First call fails one slot's max_chars → second call only re-asks
    that slot, and the satisfied slots carry through unchanged."""
    ctx = _run_ctx(tmp_path)
    over_chars = "A" * 60  # cancel_cta max_chars is 18
    llm = _ScriptedLLM(
        [
            {
                "booked_screen": "Locked in.",
                "cancel_cta": over_chars,
                "home_greeting": "Welcome back, fighter.",
            },
            {"cancel_cta": "Cancel"},
        ]
    )
    out = asyncio.run(TextGenerationService(llm).resolve(ctx))

    assert set(out.texts) == {"booked_screen", "cancel_cta", "home_greeting"}
    assert out.texts["cancel_cta"].value == "Cancel"
    assert len(llm.calls) == 2
    # Second call's schema only declares the violator's slot — that's
    # the per-slot retry contract.
    second_schema = llm.calls[1]["schema"]
    assert set(second_schema.model_fields) == {"cancel_cta"}


def test_resolve_drops_slot_that_never_satisfies_bounds(
    tmp_path: Path,
) -> None:
    """A slot whose value keeps violating bounds for every attempt is
    omitted from the returned TextSet after MAX_RETRIES."""
    ctx = _run_ctx(tmp_path)
    too_long = "the quick brown fox jumps over the lazy dog"  # > max_words=4
    llm = _ScriptedLLM(
        [
            {
                "booked_screen": too_long,
                "cancel_cta": "Cancel",
                "home_greeting": "Welcome back, fighter.",
            },
            {"booked_screen": too_long},
            {"booked_screen": too_long},
        ]
    )
    out = asyncio.run(TextGenerationService(llm).resolve(ctx))

    # The two compliant slots come through; the doomed one is omitted.
    assert set(out.texts) == {"cancel_cta", "home_greeting"}
    assert "booked_screen" not in out.texts
    assert len(llm.calls) == MAX_RETRIES


def test_resolve_empty_text_slots_makes_no_llm_call(tmp_path: Path) -> None:
    """Defense-in-depth: a direct service call with no slots returns
    an empty TextSet and never touches the LLM (the registry's
    primary skip path is the empty-list check on app.texts)."""
    ctx = _run_ctx(tmp_path)
    ctx.app = ctx.app.model_copy(update={"texts": []})

    class _Boom:
        async def complete_structured(self, *a: Any, **k: Any) -> Any:
            raise AssertionError("must not be called for an empty slot list")

        async def complete(self, *a: Any, **k: Any) -> Any:
            raise AssertionError("must not be called")

    out = asyncio.run(TextGenerationService(_Boom()).resolve(ctx))
    assert out == TextSet(texts={})


# --- Prompt is data-driven ------------------------------------------------


def test_text_prompt_is_app_agnostic(tmp_path: Path) -> None:
    """The .md template carries no app-specific slot data — every
    placeholder is substituted from the run context at call time."""
    ctx = _run_ctx(tmp_path)
    template = TEXT_PROMPT_PATH.read_text(encoding="utf-8")

    # Slots are deferred to a placeholder; no slot description baked in.
    assert "$slots" in template
    for slot in ctx.app.texts:
        assert slot.description not in template

    prompt = TextGenerationService._build_prompt(
        ctx,
        list(ctx.app.texts),
        prior_attempts={},
        prior_violations={},
    )
    # Brand brief substituted; every slot's id+description+limits listed.
    assert ctx.cust.design_direction.name in prompt
    for slot in ctx.app.texts:
        assert slot.id in prompt
        assert slot.description in prompt
        assert f"{slot.min_words}-{slot.max_words} words" in prompt
        assert f"{slot.min_chars}-{slot.max_chars} chars" in prompt
    # No retry block on the first-call prompt.
    assert "Your previous attempt failed length validation" not in prompt


def test_text_prompt_includes_retry_block_on_retry(tmp_path: Path) -> None:
    """On a retry call, the rejected value and its specific violations
    are visible to the model."""
    ctx = _run_ctx(tmp_path)
    [violator] = [s for s in ctx.app.texts if s.id == "cancel_cta"]

    prompt = TextGenerationService._build_prompt(
        ctx,
        [violator],
        prior_attempts={"cancel_cta": "A wildly long cancel string"},
        prior_violations={"cancel_cta": ["too many characters (27; max 18)"]},
    )
    assert "Your previous attempt failed length validation" in prompt
    assert "A wildly long cancel string" in prompt
    assert "too many characters (27; max 18)" in prompt


# --- TextNode -------------------------------------------------------------


def test_text_node_run_returns_text_set(tmp_path: Path) -> None:
    """TextNode is a thin orchestrator over the generation service."""
    ctx = _run_ctx(tmp_path)
    llm = _ScriptedLLM(
        [
            {
                "booked_screen": "Locked in.",
                "cancel_cta": "Cancel",
                "home_greeting": "Welcome back, fighter.",
            }
        ]
    )
    node = TextNode(ctx, llm=llm)

    out = asyncio.run(node.run())

    assert isinstance(out, TextSet)
    assert set(out.texts) == {s.id for s in ctx.app.texts}
    # TextNode is a level-0 sibling of the colour and font roots.
    assert node.key == DependencyKind.TEXT.value
    assert node.deps == frozenset()
