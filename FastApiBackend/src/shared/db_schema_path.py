"""Register the Database/python_data package on sys.path.

Import this module before any `from schema.xxx import ...` to
make the shared Database schema package available.
"""

import sys
from pathlib import Path

_DB_SCHEMA_PATH = str(
    Path(__file__).resolve().parent.parent.parent.parent / "Database" / "python_data"
)
if _DB_SCHEMA_PATH not in sys.path:
    sys.path.insert(0, _DB_SCHEMA_PATH)
