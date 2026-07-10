#!/usr/bin/env bash
#
# Supervises the two processes this image runs: the FastApiBackend uvicorn
# API and the VideoService background worker. Deliberately NOT `set -e` —
# we need to inspect `wait`'s exit code ourselves rather than let the shell
# die on it.
set -uo pipefail

BACKEND_DIR=/app/FastApiBackend
WORKER_DIR=/app/VideoService

# Each app has its own poetry venv (see Dockerfile). Run each process from
# its own project directory using its own venv's python, so `python -m ...`
# resolves that project's `src` package via cwd (same pattern the local
# Makefiles use: `poetry run python -m uvicorn ...` / `python -m scripts...`).
cd "$BACKEND_DIR"
"$BACKEND_DIR/.venv/bin/python" -m uvicorn src.main:app --host 0.0.0.0 --port 8000 &
BACKEND_PID=$!

cd "$WORKER_DIR"
"$WORKER_DIR/.venv/bin/python" -m src.worker.run &
WORKER_PID=$!

# Forward SIGTERM/SIGINT (container stop) to both children so they can shut
# down cleanly (uvicorn finishing in-flight requests, the worker finishing its
# current job) instead of being SIGKILLed by the platform's grace-period timeout.
_shutdown() {
    kill -TERM "$BACKEND_PID" "$WORKER_PID" 2>/dev/null
    wait "$BACKEND_PID" "$WORKER_PID" 2>/dev/null
}
trap _shutdown SIGTERM SIGINT

# Block until EITHER process exits, then propagate its exit code. This is the
# whole point of the supervisor: a container running "API up, worker crashed"
# (or vice versa) is a silent half-outage. Exiting nonzero here lets the
# platform (ECS) see the task as unhealthy and restart it, rather than us
# quietly limping along on whichever process is still alive.
wait -n
EXIT_CODE=$?

_shutdown
exit "$EXIT_CODE"
