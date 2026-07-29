"""studio.agent — the conversational brand-brief interviewer.

A Pydantic AI agent that interviews someone about their brand and proposes a
theme brief. It is the web-app counterpart of the `brand-brief` skill: the
same ≤10-question, one-at-a-time interview, but the skill is bound to
Claude Code's interactive tooling and cannot run from a browser, which is
exactly why this exists.

**The agent authors; code commits.** It has ZERO tools and writes nothing.
It converses to propose a brief; the accept path runs the studio's existing
deterministic `BriefService.commit` — the same one the plain form posts to —
and only then runs the agent again so it can acknowledge.
"""

from __future__ import annotations
