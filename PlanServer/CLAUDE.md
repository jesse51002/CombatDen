# PlanServer

A self-hosted **agent-native "Plans" app** (`BuilderIO/agent-native`, npm
`@agent-native/core`, MIT) running as an always-on, **loopback-only, single-user,
offline** Docker container. It serves BOTH:

- the **web UI** at `http://localhost:3939/` (loopback is trusted; the first visit may prompt a one-time **local** account — it is stored in `./data` and never sent anywhere), and
- a local **MCP endpoint** at `http://localhost:3939/_agent-native/mcp`.

It backs the `/visual-plan` and `/visual-recap` skills privately/offline: those
skills author and read structured plans through this MCP endpoint instead of a
hosted service. "Offline" refers to RUNTIME — the running container needs no
external network. (Image BUILD does need npm + GitHub to scaffold the app.)

This is a "thin" system: the repo carries only this `CLAUDE.md`, `Dockerfile`,
`compose.yaml`, `.env.example`, `planserver.service`, a one-line `README.md`, and
`.gitignore`. The actual Node app is scaffolded AND built INSIDE the image at
build time — its generated source is deliberately NOT vendored here.

## This file is a living document
Keep it in sync with reality. If the pinned version, the run commands, the
networking model, or a gotcha changes, update this file in the same change. A
stale rule here misleads the next operator/agent.

## Operate it

```bash
cd PlanServer
docker compose up -d --build     # build (first time / after an upgrade) + start
docker compose up -d             # start (image already built)
docker compose ps                # status
docker compose logs -f           # follow logs
docker compose down              # stop + remove the container
docker compose restart           # restart
docker stats --no-stream planserver   # RAM/CPU snapshot
```

State lives in the gitignored `./data` (SQLite `app.db` + uploads) and `./plans`
(exported MDX). Deleting the container does not lose plans; deleting those
folders does.

## Connect Claude Code

The MCP server is registered in the repo-root `.mcp.json`:

```json
{
  "mcpServers": {
    "plans": {
      "type": "http",
      "url": "http://localhost:3939/_agent-native/mcp"
    }
  }
}
```

- Transport is **`http`** (MCP streamable HTTP — the server uses
  `StreamableHTTPServerTransport`; it is NOT SSE).
- **No token/headers** — loopback requests are auto-authenticated (see gotcha b).
- A **new Claude Code session may need to approve the `plans` MCP server** (and a
  running session must be **restarted** to pick up a new `.mcp.json` entry).
  Confirm with `/mcp` inside Claude Code once the container is up.

## Version pin + upgrade

The ONLY pinned thing is `@agent-native/core`, via the `AGENT_NATIVE_VERSION`
build ARG in the `Dockerfile` (currently **`0.92.12`**; pnpm `10.29.1`, Node
`24.14.0`). To upgrade:

1. Bump `AGENT_NATIVE_VERSION` in the `Dockerfile` (resolve a concrete version:
   `npm view @agent-native/core version`).
2. `docker compose up -d --build`.

**Reproducibility caveat:** because the app is scaffolded at build time and the
scaffold ships no lockfile, only `@agent-native/core` is fixed — **everything
else floats**, including sibling `@agent-native/*` packages (e.g.
`@agent-native/toolkit`, which is versioned independently at ~0.4.x and must stay
on `latest` to stay compatible with the pinned core) and all transitive deps.
They resolve fresh on each `--build`, so two builds days apart can pull different
versions. This is inherent to the "don't vendor the app" design; pin harder only
by vendoring, which we deliberately don't.

## GOTCHAS (read before touching anything)

**(a) NEVER set `NODE_ENV=production`.** The app's `isLocalPlanRuntime()`
hard-refuses local single-user mode when `NODE_ENV` is `production`/`prod`,
flipping into hosted multi-tenant auth that REQUIRES a login + `BETTER_AUTH_SECRET`.
Leave `NODE_ENV` UNSET. Local mode is on when `NODE_ENV` is unset AND `AUTH_MODE`
is unset or `local` (optionally force it with `PLAN_LOCAL_MODE=1`). Set NO
`BETTER_AUTH_SECRET` / `ACCESS_TOKEN` / `A2A_SECRET` — each would switch on an
auth path and defeat the no-login model.

**(b) Bind loopback-only — this is load-bearing for the no-auth model, AND it is
why we use `network_mode: host`.** The MCP endpoint's dev-open auth grants an
unauthenticated request ONLY when the request's **socket peer is loopback**
(`isLoopbackRequest`, read from the real socket — `X-Forwarded-For` is
deliberately ignored, and there is NO env override). With Docker **bridge**
networking + a published port, the container sees the **docker gateway IP, not
loopback**, so the MCP endpoint returns **401**. So compose uses
`network_mode: host` and the image binds `HOST=127.0.0.1` — that makes a
host-loopback request actually arrive as loopback inside the container, enabling
the no-token MCP dev-open and the local (single-user) browser session (which may
still ask you to create a one-time local account on first visit). Because the app binds
`127.0.0.1` only, host networking still exposes it on **loopback only**. Do NOT
change `HOST` to `0.0.0.0`: with host networking that would expose an
**unauthenticated** instance on every interface. (The web UI also relies on local
mode, which is `NODE_ENV`-gated, not loopback-gated — but the MCP endpoint's
dev-open is strictly loopback-gated.)

**(c) `better-sqlite3` / `node-pty` / `esbuild` are native.** They compile in the
BUILD stage, which installs `python3 make g++`. Build and runtime share the same
Debian base (`bookworm` / `bookworm-slim`) so the native ABI matches. The runtime
carries the Nitro `.output` PLUS the app's full `node_modules` — because Nitro's
dependency trace does NOT bundle every runtime dep (e.g. `yjs`, a transitive
tiptap dep, is missed), so without `/app/node_modules` the web UI SSR of `/`
throws `ERR_MODULE_NOT_FOUND`. Node resolves bundled deps from
`.output/server/node_modules` first and falls back to `/app/node_modules`. This
makes the image ~1.3 GB; correctness over slimness. (The MCP endpoint alone does
not hit the SSR path, so it worked even before node_modules was carried — the web
UI is what needs it.)

**(d) Telemetry is off.** The Dockerfile sets `DO_NOT_TRACK=1` and
`AGENT_NATIVE_TELEMETRY_DISABLED=1` for the scaffold/CLI ping. Analytics, Sentry,
and Amplitude are all off-by-default (they need keys that are never set).

**(e) Persistence.** DB = `file:./data/app.db` (cwd `/app`), bind-mounted
`./data:/app/data`. Exported MDX = `PLAN_LOCAL_DIR` default `<cwd>/plans`,
bind-mounted `./plans:/app/plans`. Both are gitignored.

**(f) `create` flags.** Scaffold is `create app --template plan` — a SINGLE
explicit `--template` (no `--headless`). `--headless` OVERRIDES `--template` and
scaffolds an empty "hello" app instead of Plans. `--mode` / `--mcp-url` are NOT
`create` flags in 0.92.x — do not add them.

## Autostart on boot

Requirement: the container must come up on boot with no manual step.

- **In effect already:** `restart: always` in `compose.yaml` (survives crashes;
  and reboots too, but ONLY if the Docker daemon starts at boot).
- **Requires the operator (needs root — cannot be run non-interactively):** the
  Docker daemon on this box is currently **NOT enabled at boot**. Run ONE of:

  ```bash
  # Option 1 — enable Docker at boot (simplest; restart: always then handles it):
  sudo systemctl enable --now docker

  # Option 2 — the belt-and-suspenders systemd unit (brings the project
  # explicitly up at boot, down at shutdown; works even without Option 1):
  sudo cp PlanServer/planserver.service /etc/systemd/system/planserver.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now planserver.service
  ```

  Either option is sufficient; you do not need both. Verify Docker's boot state
  with `systemctl is-enabled docker`.
