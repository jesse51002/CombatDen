// The run, folded out of its records — the one piece of this view with real
// branching, and the reason `__tests__/runFold.test.ts` exists.
//
// WHY A FOLD RATHER THAN A LIVE ACCUMULATOR: the stream REPLAYS FROM INDEX 0
// on every connect (`run_router.stream_run` ignores `Last-Event-ID` by design),
// so a tab that opens after the run finished, a tab that reconnects after a
// drop, and a tab that watched from the first second all receive the same list
// in the same order. Rendering has to be a pure function of that list — anything
// that assumed "I was here for the start" would show a different run depending
// on when it connected, and the demo's whole point is that it does not.
//
// It is also what makes the poll fallback free: `GET /runs/{id}` returns the
// same records as a snapshot, so the two transports feed one function.

import type { ProgressEvent, RunRecord, RunSnapshot, RunStatus } from './studioApi';

/**
 * The executor's five FROZEN root keys (`DependencyKind` in
 * `ThemeService/src/modules/base.py`): the colour, font, text, icon and
 * classification nodes. Every other node key in a run is an image slot id
 * (`ImageNode` is built with `key=slot.id`).
 *
 * This is a contract, not a guess. `AppFormat` REJECTS an image slot named
 * `color` / `font` / `text` / `icon` / `category` precisely so these keys can
 * never be shadowed — which is what lets the sheet lay out its plate grid the
 * moment a level starts, before any node has reported its `image_slot`.
 * A real `image_slot` on the wire still wins over this list; see `classify`.
 */
export const ROOT_NODE_KEYS = Object.freeze([
  'color',
  'font',
  'text',
  'icon',
  'category',
] as const);

/**
 * What each root node produces, in the reader's language. A run's node keys are
 * engine identifiers; "color" tells a buyer nothing that "Colour palette" does
 * not tell them better, and the raw key stays visible in the mono column.
 */
export const ROOT_LABELS: Readonly<Record<string, string>> = Object.freeze({
  color: 'Colour palette',
  font: 'Typefaces',
  text: 'Written copy',
  icon: 'Navigation icons',
  category: 'Classification',
});

export type NodeKind = 'root' | 'image';

/**
 * Where one node stands.
 *
 * `skipped` is never reported by the engine — it is what a node that is still
 * queued (or still running) when the run ends must be. The executor skips the
 * regenerating dependents of a failed node without emitting anything for them,
 * so without this state a failed `single_point` would leave `giftbox` and
 * `points_stars_image` spinning forever on a run that is over.
 */
export type NodeState = 'queued' | 'running' | 'done' | 'failed' | 'skipped';

export interface RunNode {
  readonly key: string;
  readonly kind: NodeKind;
  readonly state: NodeState;
  /** 0-based topological level, once its level has started. */
  readonly level: number | null;
  /** The `node_started` record's server timestamp — the live clock's origin. */
  readonly startedAt: string | null;
  /** The node's OWN work, from the moment it acquired the concurrency slot. */
  readonly elapsedSeconds: number | null;
  readonly error: string | null;
}

export interface RunTally {
  readonly done: number;
  readonly failed: number;
  readonly running: number;
  readonly queued: number;
  readonly skipped: number;
  readonly total: number;
}

export interface RunFinish {
  readonly elapsedSeconds: number | null;
  readonly cost: number | null;
  readonly generated: readonly string[];
}

export interface RunView {
  readonly runId: string | null;
  readonly appId: string | null;
  /** The folder under `apps/<app_id>/` — and the design id in the catalog. */
  readonly runName: string | null;
  readonly status: RunStatus;
  /** True once the terminal record has landed; the stream ends there. */
  readonly settled: boolean;
  readonly error: string | null;
  readonly startedAt: string | null;
  readonly settledAt: string | null;
  readonly totalNodes: number | null;
  readonly totalLevels: number | null;
  /** The five engine roots, in their canonical order, once each is known. */
  readonly roots: readonly RunNode[];
  /** The image slots, in the order the run first mentioned them. */
  readonly slots: readonly RunNode[];
  readonly nodes: RunTally;
  readonly images: RunTally;
  /**
   * How many images this run will produce in total, known long before their
   * slot ids are: `run_started` carries `total_nodes`, and the roots all queue
   * together in level 0, so the remainder is the image count. It is what lets
   * the sheet say "3 of 10 images" from the first few seconds instead of
   * counting up against a denominator that keeps growing.
   *
   * `null` until level 0 has started — never a guess.
   */
  readonly expectedImages: number | null;
  readonly finish: RunFinish | null;
}

/** A mutable node while the fold is running. */
interface Draft {
  key: string;
  kind: NodeKind;
  state: NodeState;
  level: number | null;
  startedAt: string | null;
  elapsedSeconds: number | null;
  error: string | null;
  /** First-seen order, so the plate grid never reshuffles under the reader. */
  seen: number;
}

const ROOT_SET: ReadonlySet<string> = new Set<string>(ROOT_NODE_KEYS);

function classify(key: string, imageSlot: string | null | undefined): NodeKind {
  // An explicit `image_slot` is the engine speaking about itself and outranks
  // the key list; the key list is what answers before any node has started.
  if (imageSlot !== null && imageSlot !== undefined && imageSlot === key) return 'image';
  return ROOT_SET.has(key) ? 'root' : 'image';
}

function tally(nodes: readonly RunNode[]): RunTally {
  let done = 0;
  let failed = 0;
  let running = 0;
  let queued = 0;
  let skipped = 0;
  for (const node of nodes) {
    if (node.state === 'done') done += 1;
    else if (node.state === 'failed') failed += 1;
    else if (node.state === 'running') running += 1;
    else if (node.state === 'queued') queued += 1;
    else skipped += 1;
  }
  return { done, failed, running, queued, skipped, total: nodes.length };
}

/**
 * Every record so far, as the run.
 *
 * Pure and total: an unknown event kind, a `progress` line with no event, and a
 * node event with no node name are all ignored rather than thrown on. A studio
 * that grows a sixth event kind must not blank the page of a demo.
 */
export function foldRecords(records: readonly RunRecord[]): RunView {
  const drafts = new Map<string, Draft>();
  let runId: string | null = null;
  let appId: string | null = null;
  let runName: string | null = null;
  let startedAt: string | null = null;
  let settledAt: string | null = null;
  let status: RunStatus = 'running';
  let settled = false;
  let error: string | null = null;
  let totalNodes: number | null = null;
  let totalLevels: number | null = null;
  let finish: RunFinish | null = null;
  let order = 0;

  const touch = (key: string, imageSlot: string | null | undefined): Draft => {
    const existing = drafts.get(key);
    if (existing !== undefined) {
      // A node classified from the key list is upgraded the moment the engine
      // names it an image slot; the reverse never happens.
      if (existing.kind === 'root' && classify(key, imageSlot) === 'image') {
        existing.kind = 'image';
      }
      return existing;
    }
    const draft: Draft = {
      key,
      kind: classify(key, imageSlot),
      state: 'queued',
      level: null,
      startedAt: null,
      elapsedSeconds: null,
      error: null,
      seen: order,
    };
    order += 1;
    drafts.set(key, draft);
    return draft;
  };

  const applyEvent = (event: ProgressEvent, at: string): void => {
    switch (event.kind) {
      case 'run_started':
        totalLevels = event.total_levels ?? totalLevels;
        totalNodes = event.total_nodes ?? totalNodes;
        appId = appId ?? event.app_id ?? null;
        break;
      case 'level_started':
        // The level's whole batch, queued at once. This is what lays the plate
        // grid out BEFORE the work lands, so progress is spatial rather than a
        // percentage: the reader can see how many frames are still empty.
        for (const key of event.level_nodes ?? []) {
          const draft = touch(key, null);
          draft.level = event.level ?? draft.level;
        }
        break;
      case 'node_started': {
        if (typeof event.node !== 'string') break;
        const draft = touch(event.node, event.image_slot);
        draft.state = 'running';
        draft.startedAt = at;
        draft.level = event.level ?? draft.level;
        break;
      }
      case 'node_finished': {
        if (typeof event.node !== 'string') break;
        const draft = touch(event.node, event.image_slot);
        draft.state = 'done';
        draft.elapsedSeconds = event.elapsed_seconds ?? draft.elapsedSeconds;
        draft.level = event.level ?? draft.level;
        break;
      }
      case 'node_failed': {
        if (typeof event.node !== 'string') break;
        const draft = touch(event.node, event.image_slot);
        draft.state = 'failed';
        draft.elapsedSeconds = event.elapsed_seconds ?? draft.elapsedSeconds;
        draft.error = event.error ?? draft.error;
        draft.level = event.level ?? draft.level;
        break;
      }
      case 'run_finished':
        finish = {
          elapsedSeconds: event.elapsed_seconds ?? null,
          cost: event.cost ?? null,
          generated: event.generated ?? [],
        };
        break;
    }
  };

  for (const record of records) {
    if (record.kind === 'launched') {
      runId = record.run_id ?? runId;
      appId = record.app_id ?? appId;
      runName = record.run_name ?? runName;
      startedAt = record.at;
    } else if (record.kind === 'progress') {
      if (record.event != null) applyEvent(record.event, record.at);
    } else {
      settled = true;
      settledAt = record.at;
      status = record.status ?? 'failed';
      error = record.error ?? null;
    }
  }

  // A run that is over cannot still have work pending. Whatever never reported
  // was skipped (a failed dependency) or lost with the process (a crash); both
  // read the same to a viewer — it was not produced.
  if (settled) {
    for (const draft of drafts.values()) {
      if (draft.state === 'queued' || draft.state === 'running') draft.state = 'skipped';
    }
  }

  const all = [...drafts.values()].map(freeze);
  const roots = ROOT_NODE_KEYS.map((key) => all.find((node) => node.key === key)).filter(
    (node): node is RunNode => node !== undefined && node.kind === 'root',
  );
  const slots = all.filter((node) => node.kind === 'image');
  const expectedImages =
    totalNodes !== null && roots.length > 0 ? Math.max(totalNodes - roots.length, slots.length) : null;

  return {
    runId,
    appId,
    runName,
    status,
    settled,
    error,
    startedAt,
    settledAt,
    totalNodes,
    totalLevels,
    roots,
    slots,
    nodes: tally(all),
    images: tally(slots),
    expectedImages,
    finish,
  };
}

function freeze(draft: Draft): RunNode {
  return Object.freeze({
    key: draft.key,
    kind: draft.kind,
    state: draft.state,
    level: draft.level,
    startedAt: draft.startedAt,
    elapsedSeconds: draft.elapsedSeconds,
    error: draft.error,
  });
}

/**
 * Fold one newly-arrived record into the list, or say the list is unusable.
 *
 * The stream replays from 0, so a reconnect re-delivers records already held —
 * those are dropped by index rather than appended twice. A record from BEYOND
 * the end means frames went missing, which the list cannot repair on its own:
 * the caller resynchronises from `GET /runs/{id}` instead. Returning `null` for
 * that case rather than appending a hole is what keeps `foldRecords`'s input
 * guaranteed contiguous.
 */
export function appendRecord(
  records: readonly RunRecord[],
  record: RunRecord,
): readonly RunRecord[] | null {
  if (record.index < records.length) return records;
  if (record.index > records.length) return null;
  return [...records, record];
}

/**
 * A polled snapshot's records, with the terminal record the poll path may be
 * missing.
 *
 * The STREAM synthesises one for a run whose log has no terminal line — a
 * studio process that died mid-run — so a subscriber can close instead of
 * reconnecting forever. `GET /runs/{id}` does NOT: it reports the crash on the
 * snapshot's own `status` field and returns the raw log lines. Reading that
 * status back into a record is what keeps this module the single authority on
 * whether a run is over, instead of giving the poll path rules of its own.
 */
export function withTerminal(snapshot: RunSnapshot): readonly RunRecord[] {
  const records = snapshot.records;
  if (snapshot.status === 'running' || records[records.length - 1]?.kind === 'settled') {
    return records;
  }
  return [
    ...records,
    {
      kind: 'settled',
      index: records.length,
      at: snapshot.finished_at ?? new Date().toISOString(),
      status: snapshot.status,
      error: snapshot.error ?? null,
    },
  ];
}

/**
 * The same close, for a run the studio no longer has at all.
 *
 * A 404 on the poll is an ANSWER — this run's log under `.studio/runs/` is
 * gone — not a failure to reach. Without a terminal record the sheet would go
 * on claiming a run is in flight, and poll for it forever.
 */
export function goneRecords(records: readonly RunRecord[]): readonly RunRecord[] {
  return [
    ...records,
    {
      kind: 'settled',
      index: records.length,
      at: new Date().toISOString(),
      status: 'crashed',
      error:
        'the studio no longer has this run — its log under .studio/runs/ is gone, so ' +
        'nothing more can be recovered about it',
    },
  ];
}

// ── Reading the numbers ─────────────────────────────────────────────────────

/**
 * Seconds as a demo reads them aloud: `41s`, `1m 04s`, `4m 12s`.
 *
 * Zero-padded seconds past the minute so a ticking clock does not jitter its
 * own width, which is the whole reason the figures are tabular in the sheet.
 */
export function formatElapsed(seconds: number | null): string {
  if (seconds === null || !Number.isFinite(seconds) || seconds < 0) return '—';
  const whole = Math.floor(seconds);
  if (whole < 60) return `${String(whole)}s`;
  const minutes = Math.floor(whole / 60);
  return `${String(minutes)}m ${String(whole % 60).padStart(2, '0')}s`;
}

/** A run's cost, to the cent — `1.0937` reads as `$1.09`. */
export function formatCost(cost: number | null): string {
  if (cost === null || !Number.isFinite(cost)) return '—';
  return `$${cost.toFixed(2)}`;
}

/**
 * Live seconds for a node that is still running.
 *
 * `startedAt` is the SERVER's stamp and `now` is the browser's, which would be
 * a clock-skew bug against a remote host. It is not one here by construction:
 * the studio binds 127.0.0.1 and is never deployed, so the two clocks are the
 * same clock. A negative result (a machine whose clock stepped) reads as 0
 * rather than as a run that started in the future.
 */
export function liveSeconds(startedAt: string | null, now: number): number | null {
  if (startedAt === null) return null;
  const started = Date.parse(startedAt);
  if (Number.isNaN(started)) return null;
  return Math.max(0, (now - started) / 1000);
}

/**
 * What one node reports, for the plate caption and the system row alike.
 *
 * A RUNNING node counts up from its own start — the moment it acquired the
 * engine's concurrency slot, which is exactly when the server started its own
 * clock — so five nodes running at once show five honest independent timers
 * rather than one shared elapsed. That is the difference between "the machine
 * is doing five things" and "something is happening".
 */
export function nodeTiming(node: RunNode, now: number): string {
  switch (node.state) {
    case 'queued':
      return 'queued';
    case 'running':
      return formatElapsed(liveSeconds(node.startedAt, now));
    case 'done':
      return formatElapsed(node.elapsedSeconds);
    case 'failed':
      return 'failed';
    case 'skipped':
      return 'not produced';
  }
}
