# syntax=docker/dockerfile:1
#
# PlanServer — self-hosted agent-native "Plans" app + local MCP endpoint.
# The plan app is scaffolded AND built INSIDE this image at build time; its
# generated source is never vendored into the repo. Only the @agent-native/core
# version is pinned (ARG below) — transitive deps float (the scaffold ships no
# lockfile). See PlanServer/CLAUDE.md for the full rationale + gotchas.

##############################################################################
# BUILD STAGE — scaffold the plan template, install, and build the server.
# Full Debian base so apt can install the native toolchain the compiled deps
# (better-sqlite3, node-pty, esbuild) need.
##############################################################################
FROM node:24.14.0-bookworm AS build

# The one pin that matters: the @agent-native/core CLI + runtime version.
ARG AGENT_NATIVE_VERSION=0.92.12
ARG PNPM_VERSION=10.29.1
ENV AGENT_NATIVE_VERSION=${AGENT_NATIVE_VERSION}

# Suppress the scaffolder/CLI one-time telemetry ping (belt-and-suspenders:
# analytics/Sentry are already off-by-default without keys).
ENV DO_NOT_TRACK=1 \
    AGENT_NATIVE_TELEMETRY_DISABLED=1

# Native toolchain for the compiled dependencies.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm@${PNPM_VERSION}

WORKDIR /build

# Scaffold the plan template non-interactively.
# IMPORTANT: a SINGLE explicit `--template plan` (WITHOUT `--headless`) is the
# script-friendly standalone path. `--headless` OVERRIDES `--template` and would
# scaffold an empty "hello" primitive app instead of the Plans app. `--mode` /
# `--mcp-url` are NOT flags of this CLI's `create` command (0.92.x) — omit them.
RUN npx -y @agent-native/core@${AGENT_NATIVE_VERSION} create app --template plan

WORKDIR /build/app

# The scaffold pins @agent-native/core to the floating "latest". Rewrite it to
# the pinned version so the runtime core actually matches the CLI/template.
# NOTE: pin ONLY @agent-native/core here. Sibling packages like
# @agent-native/toolkit are versioned INDEPENDENTLY (its latest is ~0.4.x, not
# 0.92.x), so they must stay on "latest" to resolve a version compatible with
# the pinned core.
RUN node -e "const fs=require('fs');const f='package.json';const p=JSON.parse(fs.readFileSync(f));const v=process.env.AGENT_NATIVE_VERSION;let hit=false;for(const k of ['dependencies','devDependencies']){const d=p[k]||{};if(d['@agent-native/core']){d['@agent-native/core']=v;hit=true;}}fs.writeFileSync(f,JSON.stringify(p,null,2)+'\n');console.log('pinned @agent-native/core ->',v,'(found:'+hit+')');"

# node-linker=hoisted produces a FLAT (npm-style) node_modules where every dep —
# including transitive ones like `yjs` — is a real folder at the top level. This
# is required so the runtime fallback resolution (see runtime stage) can find the
# deps Nitro's trace misses. pnpm's default non-flat layout hides transitive deps
# under node_modules/.pnpm/, where Node's walk-up resolution can't reach them.
RUN pnpm install --no-frozen-lockfile --config.node-linker=hoisted

RUN pnpm build

##############################################################################
# RUNTIME STAGE — carries the Nitro output + the app's node_modules (see the
# COPY note below for why node_modules is needed). Drops the build toolchain,
# pnpm store, and app source, so it stays slimmer than the build stage.
##############################################################################
FROM node:24.14.0-bookworm-slim AS runtime

# CRITICAL GOTCHA: do NOT set NODE_ENV=production (or "prod"). The plan app's
# isLocalPlanRuntime() hard-refuses local single-user mode in production and
# flips into hosted multi-tenant auth (login + BETTER_AUTH_SECRET REQUIRED).
# Leave NODE_ENV UNSET. AUTH_MODE unset (or "local") keeps local mode on.
#
# HOST/NITRO_HOST=127.0.0.1 binds the server to loopback ONLY. Combined with
# `network_mode: host` in compose, that is what makes the request socket peer
# appear as loopback inside the container — which is required for the MCP
# endpoint's no-token "dev-open" auth AND the browser's no-login dev session.
ENV PORT=3939 \
    NITRO_PORT=3939 \
    HOST=127.0.0.1 \
    NITRO_HOST=127.0.0.1 \
    DO_NOT_TRACK=1 \
    AGENT_NATIVE_TELEMETRY_DISABLED=1

WORKDIR /app

# Nitro's node-server output. NOTE: its trace does NOT bundle every runtime dep
# (e.g. `yjs`, pulled in transitively by the tiptap editor, is missed) — so
# `.output` is NOT fully self-contained and SSR of `/` would throw
# ERR_MODULE_NOT_FOUND. We therefore also carry the app's full (hoisted, flat)
# node_modules: Node resolves bundled deps from .output/server/node_modules first
# (closest) and falls back to /app/node_modules for the ones the trace missed.
# The flat layout (node-linker=hoisted, set in the build stage) is what makes
# those transitive deps resolvable at /app/node_modules/<pkg>. This is the robust
# fix (vs. whack-a-mole adding individual missed packages). We still drop the
# build toolchain, pnpm store, and app source, so the runtime stays slimmer than
# the build stage.
COPY --from=build /build/app/.output ./.output
COPY --from=build /build/app/node_modules ./node_modules

# SQLite DB lives at file:./data/app.db (cwd=/app). Local MDX mirror lives at
# PLAN_LOCAL_DIR default <cwd>/plans. Both are bind-mounted in compose so state
# survives container recreation.
RUN mkdir -p /app/data /app/plans

EXPOSE 3939

CMD ["node", ".output/server/index.mjs"]
