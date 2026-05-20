"""Writer — serializes a run's YAML artifacts in one call."""

from __future__ import annotations

import logging
from pathlib import Path

import yaml
from pydantic import BaseModel

from src.core.run_context import RunContext
from src.executor.orchestrator import PipelineResult
from schema import RunCost

logger = logging.getLogger(__name__)

APP_PROVENANCE_NAME = "app.yaml"
CUSTOMIZATION_PROVENANCE_NAME = "customization.yaml"

# Cost is an estimate (litellm pricing + a flat PhotoRoom rate), so a
# fixed business precision — not float noise — lands in output.yaml.
COST_PRECISION = 6


class Writer:
    """Writes provenance + output for one run, together."""

    def write(self, result: PipelineResult, run_ctx: RunContext) -> None:
        """Serialize provenance, then ``output.yaml`` with the run cost.

        The writer already owns assembly, so it also aggregates cost:
        each paid service tracked its own running total during the run;
        here we sum them into an optional ``RunCost`` and stamp it onto
        the output before the dump.
        """
        app_path = run_ctx.run_dir / APP_PROVENANCE_NAME
        cust_path = run_ctx.run_dir / CUSTOMIZATION_PROVENANCE_NAME
        output_path = run_ctx.output_path()

        run_cost = self._run_cost(result)
        output = result.output.model_copy(update={"cost": run_cost})

        self._dump_model(run_ctx.app, app_path)
        self._dump_model(run_ctx.cust, cust_path)
        self._dump_model(output, output_path)

        logger.debug(
            "wrote provenance + output (cost $%.6f: llm $%.6f, "
            "image $%.6f, bg $%.6f): %s, %s, %s",
            run_cost.total,
            run_cost.llm,
            run_cost.image_generation,
            run_cost.background_removal,
            app_path,
            cust_path,
            output_path,
        )

    @staticmethod
    def _run_cost(result: PipelineResult) -> RunCost:
        """Sum the run's paid services into the total + per-service breakdown,
        and the same spend split per model id.

        ``llm`` = every structured LLM call; ``image_generation`` =
        generate + any corrective edit (one service);
        ``background_removal`` = the flat PhotoRoom per-call rate.
        ``by_model`` merges the three services' per-model-id buckets:
        LLM ids only ever appear on the LLM client, image ids only on the
        image generator, and ``"photoroom"`` only on the remover, so the
        buckets are disjoint and a plain merge cannot double-count.
        """
        llm = round(result.llm.cost, COST_PRECISION)
        image_generation = round(result.image_gen.cost, COST_PRECISION)
        background_removal = round(result.bg_remover.cost, COST_PRECISION)
        by_model = {
            model: round(amount, COST_PRECISION)
            for service in (
                result.llm,
                result.image_gen,
                result.bg_remover,
            )
            for model, amount in service.cost_by_model.items()
        }
        return RunCost(
            total=round(
                llm + image_generation + background_removal, COST_PRECISION
            ),
            llm=llm,
            image_generation=image_generation,
            background_removal=background_removal,
            by_model=by_model,
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
