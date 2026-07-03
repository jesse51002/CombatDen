"""Writer — serializes a run's YAML artifacts in one call."""

from __future__ import annotations

import hashlib
import logging
from datetime import datetime, timezone
from pathlib import Path

import yaml
from pydantic import BaseModel

from src.core.asset_uploader import upload_run_assets
from src.core.config import settings
from src.core.run_context import RUN_ID_FORMAT, RunContext
from src.executor.orchestrator import PipelineResult
from schema import (
    ExpansionCostLog,
    ExpansionEntry,
    ExpansionKind,
    Output,
    RunCost,
)

logger = logging.getLogger(__name__)

APP_PROVENANCE_NAME = "app.yaml"
CUSTOMIZATION_PROVENANCE_NAME = "customization.yaml"

# Cost is an estimate (litellm pricing + a flat Recraft removeBackground
# rate), so a fixed business precision — not float noise — lands in output.yaml.
COST_PRECISION = 6


class Writer:
    """Writes provenance + output for one run, together."""

    def write(
        self,
        result: PipelineResult,
        run_ctx: RunContext,
        *,
        prior_category: str | None = None,
    ) -> None:
        """Serialize provenance, then ``output.yaml`` with the run cost.

        The writer already owns assembly, so it also aggregates cost:
        each paid service tracked its own running total during the run;
        here we sum them into an optional ``RunCost`` and stamp it onto
        the output before the dump.

        ``prior_category`` is the classification of a run this write
        *overwrites*: the assembled ``Output`` carries no ``category`` (the
        pipeline classification step is a README TODO — categories are
        hand-stamped today), so a full in-place re-run must carry the prior
        run's stamp forward or the theme silently drops out of the picker.
        The caller (``src/cli.py``) captures it from the existing
        ``output.yaml`` *before* the pipeline clears that file, and passes it
        here. A fresh run has no prior file → ``None`` → the run stays
        uncategorised, which is correct until the classification step exists.
        """
        app_path = run_ctx.run_dir / APP_PROVENANCE_NAME
        cust_path = run_ctx.run_dir / CUSTOMIZATION_PROVENANCE_NAME
        output_path = run_ctx.output_path()

        run_cost = self._run_cost(result)
        output = result.output.model_copy(
            update={"cost": run_cost, "category": prior_category}
        )
        self._stamp_versions(output, run_ctx)

        self._dump_model(run_ctx.app, app_path)
        self._dump_model(run_ctx.cust, cust_path)
        self._dump_model(output, output_path)

        self._upload_assets(
            run_ctx,
            list(output.image_set.images),
            list(output.icon_set.icons),
        )

        logger.debug(
            "wrote provenance + output (cost $%.6f: llm $%.6f, "
            "image $%.6f, bg $%.6f, icon $%.6f): %s, %s, %s",
            run_cost.total,
            run_cost.llm,
            run_cost.image_generation,
            run_cost.background_removal,
            run_cost.icon_generation,
            app_path,
            cust_path,
            output_path,
        )

    def write_expansion(
        self,
        result: PipelineResult,
        run_ctx: RunContext,
        *,
        original_cost: RunCost | None,
        original_category: str | None,
        kind: ExpansionKind,
    ) -> None:
        """Write a reopen-time pass (expand or regenerate) back in place.

        Two files change, no others:

        - ``output.yaml`` is re-dumped from the merged ``Output`` (the seeded
          done nodes plus whatever this pass (re)generated), but its ``cost``
          block is set to ``original_cost`` and its ``category`` to
          ``original_category`` — both carried forward from the file we loaded
          — so a partial pass never overwrites the original full-run cost, nor
          drops the run's (today hand-stamped) classification. The assembled
          ``Output`` carries neither, so without this carry-forward every
          regen/expand would silently un-list the theme from the picker.
        - ``expansion_cost.yaml`` gains one appended ``ExpansionEntry``
          recording *this* pass: its ``kind`` (expand vs regenerate), when it
          ran, which node keys it (re)generated, the per-slot
          ``overwrite_specs`` applied, and what those calls cost (the fresh
          paid services accumulated only this pass's spend).

        The dir's ``app.yaml`` / ``customization.yaml`` are left alone — they
        are the inputs the caller curated, not artifacts this writer owns.
        """
        output = result.output.model_copy(
            update={"cost": original_cost, "category": original_category}
        )
        self._stamp_versions(output, run_ctx)
        self._dump_model(output, run_ctx.output_path())

        self._upload_assets(
            run_ctx,
            [s for s in result.generated if s in output.image_set.images],
            [s for s in result.generated if s in output.icon_set.icons],
        )

        ledger_path = run_ctx.expansion_cost_path()
        log = self._load_expansion_log(ledger_path)
        pass_cost = self._run_cost(result)
        log.expansions.append(
            ExpansionEntry(
                kind=kind,
                expanded_at=datetime.now(timezone.utc).strftime(
                    RUN_ID_FORMAT
                ),
                generated=sorted(result.generated),
                overwrite_specs=run_ctx.overwrite_specs,
                cost=pass_cost,
            )
        )
        self._dump_model(log, ledger_path)

        logger.debug(
            "%s %s: generated %s (pass cost $%.6f); ledger now %d entr%s",
            kind.value,
            run_ctx.run_dir,
            sorted(result.generated),
            pass_cost.total,
            len(log.expansions),
            "y" if len(log.expansions) == 1 else "ies",
        )

    @staticmethod
    def _load_expansion_log(path: Path) -> ExpansionCostLog:
        """The run's existing spend ledger, or an empty one if never expanded.

        An empty/whitespace ``expansion_cost.yaml`` parses to ``None``; treat
        that the same as absent — a fresh, empty log to append to.
        """
        if not path.is_file():
            return ExpansionCostLog()
        return ExpansionCostLog.model_validate(
            yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        )

    @staticmethod
    def _run_cost(result: PipelineResult) -> RunCost:
        """Sum the run's paid services into the total + per-service breakdown,
        and the same spend split per model id.

        ``llm`` = every structured LLM call; ``image_generation`` =
        generate + any corrective edit (one service);
        ``background_removal`` = the flat Recraft removeBackground per-call
        rate; ``icon_generation`` = the published Recraft per-image price for
        any icon slot a curated set couldn't cover. ``by_model`` merges the
        four services' per-model-id buckets: LLM ids only ever appear on
        the LLM client, image ids only on the image generator,
        ``"recraft_remove_bg"`` only on the remover, and the Recraft icon
        model ids only on the icon generator, so the buckets are disjoint and
        a plain merge cannot double-count.
        """
        llm = round(result.llm.cost, COST_PRECISION)
        image_generation = round(result.image_gen.cost, COST_PRECISION)
        background_removal = round(result.bg_remover.cost, COST_PRECISION)
        icon_generation = round(result.icon_gen.cost, COST_PRECISION)
        by_model = {
            model: round(amount, COST_PRECISION)
            for service in (
                result.llm,
                result.image_gen,
                result.bg_remover,
                result.icon_gen,
            )
            for model, amount in service.cost_by_model.items()
        }
        return RunCost(
            total=round(
                llm + image_generation + background_removal + icon_generation,
                COST_PRECISION,
            ),
            llm=llm,
            image_generation=image_generation,
            background_removal=background_removal,
            icon_generation=icon_generation,
            by_model=by_model,
        )

    def _stamp_versions(self, output: Output, run_ctx: RunContext) -> None:
        """Stamp each asset slot with a content fingerprint of the bytes the
        API will serve, so an edited asset gets a changed ``?v=`` URL.

        Hashes the *served* file by slot id — ``final_images/<slot>.png``,
        ``icons/<slot>.svg`` (the same paths the API
        streams) — not the recorded ``path``, so a moved run dir still hashes
        correctly. Identical bytes hash identically, so an unchanged slot keeps
        a stable URL and only genuinely-changed assets bust their cache.
        """
        for slot_id, image in output.image_set.images.items():
            image.version = self._content_version(
                Path(str(run_ctx.image_path(slot_id)))
            )
        for slot_id, icon in output.icon_set.icons.items():
            icon.version = self._content_version(
                Path(str(run_ctx.icon_path(slot_id)))
            )

    @staticmethod
    def _content_version(path: Path) -> str:
        """A short sha256 of the file's bytes, or "" if it's absent."""
        if not path.is_file():
            return ""
        return hashlib.sha256(path.read_bytes()).hexdigest()[:12]

    @staticmethod
    def _upload_assets(
        run_ctx: RunContext, image_slots: list[str], icon_slots: list[str]
    ) -> None:
        """Opt-in on-generation mirror of the run's image/icon bytes to S3
        (gated by ``ASSET_UPLOAD_ENABLED``). Best-effort — a failure here never
        fails the run; ``make sync-assets`` is the always-available backstop."""
        if not settings.asset_upload_enabled:
            return
        try:
            n = upload_run_assets(
                run_ctx.app_id,
                run_ctx.run_id,
                image_slots,
                icon_slots,
                run_ctx.final_image_dir,
                run_ctx.icon_dir,
            )
            logger.info(
                "mirrored %d asset(s) to S3 for %s/%s",
                n,
                run_ctx.app_id,
                run_ctx.run_id,
            )
        except Exception:  # noqa: BLE001 - best-effort; sync-assets backstops
            logger.warning(
                "asset upload failed for %s/%s (continuing)",
                run_ctx.app_id,
                run_ctx.run_id,
                exc_info=True,
            )

    @staticmethod
    def _dump_model(model: BaseModel, path: Path) -> None:
        """Serialize one validated model to readable YAML at ``path``."""
        path.write_text(
            yaml.safe_dump(
                model.model_dump(mode="json"),
                sort_keys=False,
                allow_unicode=True,
                default_flow_style=False,
            ),
            encoding="utf-8",
        )
