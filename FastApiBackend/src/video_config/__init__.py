"""Video-config domain package.

The LLM authoring surface for a gym's video *configuration* — the append-only
versioned ``gym_video_spec`` (its keep/avoid criteria + JSONB search queries).
Three writers mint versions: the conversational agent (``admin_update``), the
preset import (``system_update``, in the presets domain), and the feed-learning
refiner (``feed_update``). Readers take the latest via ``gym_video_spec_latest``.
"""

from pathlib import Path

# Register the Database schema package on sys.path before any submodule does a
# ``from schema.* import ...`` (this domain reuses ``GymVideoSpecSource``).
import src.shared.db_schema_path  # noqa: F401, E402

SQL_DIR = Path(__file__).resolve().parent / "sql"
PROMPTS_DIR = Path(__file__).resolve().parent / "prompts"
