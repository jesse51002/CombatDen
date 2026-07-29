// The studio's wire contract, transcribed from the Python that serves it.
//
// SOURCE OF TRUTH, file by file — every type below is a transcription, not an
// invention, and a change there is a change here:
//
//   ProgressEvent        ThemeService/src/executor/progress_event.py
//   RunRecord            ThemeService/src/studio/schema/run_record.py
//   RunStatus            ThemeService/src/studio/schema/run_status.py
//   RunSnapshot          ThemeService/src/studio/schema/run_snapshot.py
//   LaunchRequest        ThemeService/src/studio/schema/launch_request.py
//   Customization        ThemeService/schema/customization.py  (the FIVE fields)
//   the refusals         ThemeService/src/studio/errors.py + run_router.py
//
// Nothing here talks to the READ API (`src/lib/api/client.ts`, :8001). The two
// are separate apps on purpose: the read API serves FINISHED runs and boots
// without any provider keys, and importing the pipeline into it would destroy
// that property (ThemeService/CLAUDE.md, "Two FastAPI apps").

import { resolveStudioBaseUrl } from './studioConfig';

// ── The brief ───────────────────────────────────────────────────────────────

/** `schema/customization.py`'s `ColorMode`. */
export type ColorModeInput = 'light' | 'dark';

/**
 * The brand brief: EXACTLY five fields, and there is never a sixth.
 * `Customization` sets `extra="forbid"`, so an invented field is a 422 rather
 * than a silently-ignored one.
 */
export interface BriefInput {
  readonly design_direction: {
    readonly name: string;
    readonly short_desc: string;
    readonly long_desc: string;
  };
  readonly colors_direction: {
    readonly description: string;
    readonly mode: ColorModeInput;
  };
}

// ── The event stream ────────────────────────────────────────────────────────

/** `ProgressEventKind` — the six things a watched run reports. */
export type ProgressEventKind =
  | 'run_started'
  | 'level_started'
  | 'node_started'
  | 'node_finished'
  | 'node_failed'
  | 'run_finished';

/**
 * One observation from an in-flight run. Every field but `kind` is optional
 * because one model covers all six kinds; which kind carries what is in the
 * Python's own module docstring.
 */
export interface ProgressEvent {
  readonly kind: ProgressEventKind;
  readonly app_id?: string | null;
  readonly run_id?: string | null;
  readonly total_levels?: number | null;
  readonly total_nodes?: number | null;
  /** Raw, unrounded sum of every paid service's cost. `run_finished` only. */
  readonly cost?: number | null;
  readonly generated?: readonly string[] | null;
  readonly level?: number | null;
  readonly level_nodes?: readonly string[] | null;
  readonly node?: string | null;
  /**
   * Set ONLY on a per-slot image node's events, and then it is that slot's id.
   * It is what makes a live gallery possible: it says `final_images/<slot>.png`
   * has just landed and can be fetched from `runImageUrl` immediately.
   */
  readonly image_slot?: string | null;
  readonly ok?: boolean | null;
  /** perf_counter seconds — the node's own work, or the whole run. */
  readonly elapsed_seconds?: number | null;
  readonly error?: string | null;
}

export type RunStatus = 'running' | 'succeeded' | 'failed' | 'crashed';

export type RunRecordKind = 'launched' | 'progress' | 'settled';

/**
 * One line of a run's append-only log — and one SSE frame's payload.
 *
 * A log reads as three phases: one `launched` header, zero or more `progress`
 * lines each wrapping a `ProgressEvent` verbatim, and one `settled` terminal
 * line. `index` is the 0-based position, and it is also the SSE frame's `id:`.
 */
export interface RunRecord {
  readonly kind: RunRecordKind;
  readonly index: number;
  /** UTC ISO-8601, stamped by the server on append. */
  readonly at: string;
  readonly run_id?: string | null;
  readonly app_id?: string | null;
  readonly run_name?: string | null;
  readonly event?: ProgressEvent | null;
  readonly status?: RunStatus | null;
  readonly error?: string | null;
}

/** `GET /runs/{id}` — the same records the stream carries, as one snapshot. */
export interface RunSnapshot {
  readonly run_id: string;
  readonly app_id: string;
  /** The folder under `apps/<app_id>/` — and the design id in the catalog. */
  readonly run_name: string;
  readonly status: RunStatus;
  readonly started_at: string;
  readonly finished_at?: string | null;
  readonly error?: string | null;
  readonly records: readonly RunRecord[];
}

/** `POST /runs` — the immediate 202. */
export interface LaunchAccepted {
  readonly run_id: string;
  readonly app_id: string;
  readonly run_name: string;
  readonly status: RunStatus;
  readonly started_at: string;
}

// ── Refusals ────────────────────────────────────────────────────────────────

/** The 409 the registry raises when a run is already going. */
export interface ActiveRunConflict {
  readonly message: string;
  readonly active_run_id: string;
  readonly active_app_id: string;
  readonly active_run_name: string;
}

/** One entry of FastAPI's 422 body: `exc.errors(include_url=False, …)`. */
interface FieldError {
  readonly loc?: readonly (string | number)[];
  readonly msg?: string;
}

/**
 * Any refusal the studio can make, carrying the status so a caller maps a
 * CAUSE to a message instead of reading prose. `status === 0` is the one that
 * is not an HTTP answer at all: nothing was listening.
 */
export class StudioError extends Error {
  readonly status: number;

  readonly detail: unknown;

  constructor(status: number, message: string, detail: unknown = null) {
    super(message);
    this.name = 'StudioError';
    this.status = status;
    this.detail = detail;
  }

  /** True when the studio process itself is not reachable. */
  get offline(): boolean {
    return this.status === 0;
  }

  /**
   * The run already in flight, when this is THAT 409. `null` for the other
   * 409 (a run name that already exists), which carries a plain string.
   */
  get activeRun(): ActiveRunConflict | null {
    const detail = this.detail;
    if (detail === null || typeof detail !== 'object') return null;
    const candidate = detail as Partial<ActiveRunConflict>;
    return typeof candidate.active_run_id === 'string' &&
      typeof candidate.active_app_id === 'string' &&
      typeof candidate.active_run_name === 'string'
      ? {
          message: candidate.message ?? 'A run is already in flight.',
          active_run_id: candidate.active_run_id,
          active_app_id: candidate.active_app_id,
          active_run_name: candidate.active_run_name,
        }
      : null;
  }

  /**
   * A 422's per-field messages, keyed by the LAST string in each `loc`.
   *
   * The last segment rather than the first because the brief nests: a blank
   * long description arrives as `["body", "brief", "design_direction",
   * "long_desc"]`, and `long_desc` is the field the form can actually put a
   * message under. `run_name` and `app_id` land at the same depth, so one rule
   * covers every field the form owns.
   */
  get fieldErrors(): Readonly<Record<string, string>> {
    if (!Array.isArray(this.detail)) return {};
    const out: Record<string, string> = {};
    for (const entry of this.detail as readonly FieldError[]) {
      const loc = entry.loc ?? [];
      const field = [...loc].reverse().find((part) => typeof part === 'string');
      if (typeof field === 'string' && entry.msg !== undefined && !(field in out)) {
        out[field] = entry.msg;
      }
    }
    return out;
  }
}

/** A refusal's human sentence: the plain-string detail, else the message. */
export function studioErrorText(error: unknown): string {
  if (error instanceof StudioError) {
    if (typeof error.detail === 'string') return error.detail;
    const active = error.activeRun;
    if (active !== null) return active.message;
    return error.message;
  }
  return error instanceof Error ? error.message : String(error);
}

// ── Calls ───────────────────────────────────────────────────────────────────

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const url = `${resolveStudioBaseUrl()}${path}`;
  let response: Response;
  try {
    response = await fetch(url, init);
  } catch {
    // A CORS rejection and a dead port are indistinguishable from here — the
    // browser reports both as a generic TypeError. The studio's CORS
    // allowlist already contains this dev server's two origins, so "not
    // running" is the answer worth putting in front of a reader.
    throw new StudioError(0, `The studio is not answering on ${resolveStudioBaseUrl()}.`);
  }
  if (!response.ok) {
    // FastAPI wraps every refusal as `{"detail": …}`; the detail is a plain
    // string for most, an object for the in-flight 409, and a list for a 422.
    // A body that is not JSON at all is not a refusal this code can read.
    let detail: unknown;
    try {
      const body: unknown = await response.json();
      detail =
        body !== null && typeof body === 'object' && 'detail' in body
          ? (body as { detail: unknown }).detail
          : body;
    } catch {
      detail = null;
    }
    throw new StudioError(response.status, `${path} failed (${String(response.status)})`, detail);
  }
  return (await response.json()) as T;
}

/**
 * Start a run. Returns as soon as it is registered — a full run is minutes and
 * real money, so nothing waits on it. Watch the returned `run_id`.
 */
export function launchRun(input: {
  appId: string;
  runName: string;
  brief: BriefInput;
}): Promise<LaunchAccepted> {
  return request<LaunchAccepted>('/runs', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      app_id: input.appId,
      run_name: input.runName,
      brief: input.brief,
    }),
  });
}

/** One run's full state — the fallback when the stream is not carrying. */
export function fetchRunSnapshot(runId: string): Promise<RunSnapshot> {
  return request<RunSnapshot>(`/runs/${encodeURIComponent(runId)}`);
}

/**
 * The run currently in flight, or `null`.
 *
 * This is what lets a tab that loads fresh RE-ATTACH to a run already going
 * instead of offering to start a second one that would be refused anyway — so
 * a reload in the middle of a demo costs nothing.
 */
export function fetchActiveRun(): Promise<RunSnapshot | null> {
  return request<RunSnapshot | null>('/runs/active');
}

/**
 * The PNG one image node just wrote, servable WHILE THE RUN IS STILL GOING.
 *
 * The read API cannot answer this: it loads the run's `output.yaml` first, and
 * that file is written only when the whole run finishes — so mid-run it 404s
 * there, and it 307-redirects to the CDN besides, where a run made thirty
 * seconds ago on a laptop does not exist. This endpoint reads the local file.
 */
export function runImageUrl(runId: string, slotId: string): string {
  return `${resolveStudioBaseUrl()}/runs/${encodeURIComponent(runId)}/images/${encodeURIComponent(slotId)}`;
}

/** `GET /runs/{id}/events` — subscribed with the browser's own `EventSource`. */
export function runEventsUrl(runId: string): string {
  return `${resolveStudioBaseUrl()}/runs/${encodeURIComponent(runId)}/events`;
}
