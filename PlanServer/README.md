# PlanServer

Self-hosted, loopback-only agent-native "Plans" app + local MCP endpoint
(`http://localhost:3939`, MCP at `/_agent-native/mcp`) backing the `/visual-plan`
and `/visual-recap` skills offline.

Quick start: `cd PlanServer && docker compose up -d --build`.

All operator instructions, the connect-Claude-Code steps, the upgrade flow, the
autostart-on-boot setup, and the gotchas live in **[CLAUDE.md](./CLAUDE.md)** —
the single authoritative doc for this directory. Read it before changing anything.
