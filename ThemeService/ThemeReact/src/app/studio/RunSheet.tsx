// The run, as it happens.
//
// THE PROBLEM THIS SOLVES: a full run is minutes of provider calls with long
// silences in them, and it is watched by a buyer who is deciding whether the
// engine is real. A progress bar over that is a dead demo — and a dishonest one,
// because nobody has measured what a run takes, so the bar would be inventing
// its own denominator. Four things carry the wait instead:
//
//  1. THE SHEET IS LAID OUT BEFORE THE WORK ARRIVES. Every node in a level is
//     queued the instant that level starts, so progress is spatial: ten frames,
//     three filled, and the reader can see what is left.
//  2. EVERY RUNNING NODE COUNTS ITS OWN SECONDS. Five plates working means five
//     independent timers climbing, which is information, not decoration — so it
//     survives `prefers-reduced-motion`.
//  3. THE MACHINE IS LEGIBLE. Only five nodes run at once (the executor's
//     `MAX_CONCURRENT_MODULES`), and the plate grid is five wide, so a wave of
//     work fills exactly one row and the queue behind it reads as a queue.
//  4. THE ARRIVAL IS THE EVENT. An image develops up out of a frame that was
//     already there. That is the page's one authored motion, and it fires ten
//     times over the minutes rather than once at the top.
//
// Everything rendered here is a fold over the record list (./runFold.ts) — the
// stream replays from index 0 on connect, so a tab that opened late shows the
// same run as one that watched from the first second.

import { useState } from 'react';
import { selectDesign, toCss, useActiveDesign, useThemeToken } from 'theme-react';
import type { Rgba } from 'theme-react';

import { syncThemeUrl } from '../browser/themeUrl';
// `readableInk` picks black or white against a generated colour by WCAG
// contrast. Reused rather than re-derived: the inspector answers exactly this
// question about exactly these plates, and two copies of a contrast rule is
// how they drift.
import { readableInk } from '../inspect/artifactModel';
import { SectionHead } from '../inspect/SectionHead';
import { AppOutlineButton } from '../widgets/AppOutlineButton';
import { AppPrimaryButton } from '../widgets/AppPrimaryButton';

import { groundForMode } from './groundColors';
import type { RunNode, RunView } from './runFold';
import { foldRecords, formatCost, formatElapsed, liveSeconds, nodeTiming, ROOT_LABELS } from './runFold';
import styles from './RunSheet.module.css';
import { SlotPlate } from './SlotPlate';
import type { BriefInput } from './studioApi';
import { useNowTick } from './useNowTick';
import type { Transport } from './useRunStream';
import { useRunStream } from './useRunStream';

/** The chrome's own ground, for plates whose mode is not known. */
const CHROME_GROUND: Rgba = Object.freeze({ r: 243, g: 245, b: 248, a: 1 });

export interface RunSheetProps {
  runId: string;
  /**
   * The brief that produced this run — known when THIS tab launched it, `null`
   * when the page re-attached to a run already in flight (a reload, or the
   * "watch it instead" that a 409 offers). The sheet degrades honestly: the
   * masthead falls back to the run name and the plates to a neutral ground.
   */
  brief: BriefInput | null;
  onStartAnother: () => void;
}

export function RunSheet({ runId, brief, onStartAnother }: RunSheetProps) {
  const { records, transport } = useRunStream(runId);
  const run = foldRecords(records);
  // The clock stops when the run does — a finished run costs no renders, and
  // the numbers it settled on stay put.
  const now = useNowTick(!run.settled);

  const activeDesign = useActiveDesign();
  const themeBackground = useThemeToken('background', CHROME_GROUND);
  // Three steps of honesty about what ground these assets were made for: the
  // brief's own light/dark choice while the run goes, the theme's REAL
  // background once it is loaded, and the chrome's ground when neither is
  // known (a run this tab did not launch).
  const loaded = run.runName !== null && activeDesign.id === run.runName;
  const ground = loaded
    ? themeBackground
    : (groundForMode(brief?.colors_direction.mode ?? null) ?? CHROME_GROUND);
  const groundCss = toCss(ground);
  const inkCss = toCss(readableInk(ground));

  return (
    <div className={styles.sheet}>
      <Masthead run={run} brief={brief} now={now} transport={transport} />

      <Finish run={run} loaded={loaded} onStartAnother={onStartAnother} />

      <section className={styles.section}>
        <SectionHead
          id="studio-system"
          title="The system"
          count={systemCount(run)}
        >
          The palette, the two typefaces, the app&rsquo;s copy, the navigation icons and the
          gym-type classification. They all spring from the brief and none depends on the
          others, so the engine resolves them together, first — every image below is
          generated against the colours this level decides.
        </SectionHead>
        {run.roots.length === 0 ? (
          <p className={styles.pending}>Waiting for the run to open its first level.</p>
        ) : (
          <ol className={styles.system}>
            {run.roots.map((node) => (
              <SystemRow key={node.key} node={node} now={now} />
            ))}
          </ol>
        )}
      </section>

      <section className={styles.section}>
        <SectionHead id="studio-imagery" title="Imagery" count={imageCount(run)}>
          One node per image slot, each a separate generation and background removal. The
          engine runs five at a time because the providers rate-limit, so the plates fill in
          waves — a frame is drawn for every slot the moment its level opens, and the art
          arrives into it.
        </SectionHead>
        {run.slots.length === 0 ? (
          <p className={styles.pending}>
            No image node has been queued yet. They open once the colours land.
          </p>
        ) : (
          <div className={styles.plates}>
            {run.slots.map((slot) => (
              <SlotPlate
                key={slot.key}
                runId={runId}
                slot={slot}
                now={now}
                ground={groundCss}
                ink={inkCss}
              />
            ))}
          </div>
        )}
      </section>

      {brief !== null && <BriefRecord brief={brief} />}
    </div>
  );
}

// ── Masthead ────────────────────────────────────────────────────────────────

function Masthead({
  run,
  brief,
  now,
  transport,
}: {
  run: RunView;
  brief: BriefInput | null;
  now: number;
  transport: Transport;
}) {
  const title = brief?.design_direction.name ?? run.runName ?? 'Opening the run';
  return (
    <header className={styles.masthead}>
      <p className={styles.kicker}>{kicker(run)}</p>
      <h1 className={styles.title}>{title}</h1>
      <p className={styles.identity}>
        {run.appId ?? '—'} · {run.runName ?? '—'}
        {brief !== null ? ` · ${brief.colors_direction.mode} mode` : ''}
      </p>
      <StatusLine run={run} now={now} />
      {transport === 'polling' && !run.settled && (
        <p className={styles.transport}>
          The live stream dropped. Polling the studio every 2s — the run itself is
          unaffected.
        </p>
      )}
      {/* Not on a CRASH: the status line above already says it in the page's
          own words, and the log's message says the same thing again. */}
      {run.error !== null && run.status !== 'crashed' && (
        <p className={styles.failure}>{run.error}</p>
      )}
    </header>
  );
}

function kicker(run: RunView): string {
  if (!run.settled) return 'Generating';
  switch (run.status) {
    case 'succeeded':
      return 'Generated';
    case 'failed':
      return 'Run failed';
    case 'crashed':
      return 'Run lost';
    default:
      return 'Run';
  }
}

/**
 * The one live sentence. Figures are bold and tabular, exactly as the
 * inspector's inventory line sets them — a row of big numbers over small
 * labels would be the stat-block template this page has no use for.
 */
function StatusLine({ run, now }: { run: RunView; now: number }) {
  if (run.startedAt === null) {
    return <p className={styles.status}>Connecting to the studio&hellip;</p>;
  }

  if (run.settled) {
    const elapsed = run.finish?.elapsedSeconds ?? liveSeconds(run.startedAt, Date.parse(run.settledAt ?? '') || now);
    if (run.status === 'succeeded') {
      return (
        <p className={styles.status}>
          The whole theme was generated from that brief in{' '}
          <b>{formatElapsed(elapsed)}</b> for <b>{formatCost(run.finish?.cost ?? null)}</b> of
          provider spend — <b>{run.images.done}</b> images,{' '}
          <b>{run.nodes.done}</b> of <b>{run.nodes.total}</b> steps.
          {run.nodes.failed + run.nodes.skipped > 0 && (
            <>
              {' '}
              <b>{run.nodes.failed + run.nodes.skipped}</b> did not produce.
            </>
          )}
        </p>
      );
    }
    if (run.status === 'crashed') {
      return (
        <p className={styles.status}>
          The studio process died while this run was in flight. Everything below is what its
          log had recorded by then.
        </p>
      );
    }
    return (
      <p className={styles.status}>
        The run stopped after <b>{formatElapsed(elapsed)}</b>, with <b>{run.nodes.done}</b> of{' '}
        <b>{run.nodes.total}</b> steps finished.
      </p>
    );
  }

  const total = run.totalNodes ?? run.nodes.total;
  return (
    <p className={styles.status}>
      <b>{run.nodes.done}</b> of <b>{total}</b> steps done, <b>{run.nodes.running}</b> running —{' '}
      <b>{formatElapsed(liveSeconds(run.startedAt, now))}</b> so far.
      {run.expectedImages !== null && (
        <>
          {' '}
          <b>{run.images.done}</b> of <b>{run.expectedImages}</b> images have landed.
        </>
      )}
    </p>
  );
}

function systemCount(run: RunView): string {
  if (run.roots.length === 0) return 'not opened yet';
  return `${String(run.roots.filter((node) => node.state === 'done').length)} of ${String(run.roots.length)} resolved`;
}

function imageCount(run: RunView): string {
  const total = run.expectedImages ?? run.slots.length;
  if (total === 0) return 'not opened yet';
  return `${String(run.images.done)} of ${String(total)} produced`;
}

// ── The system strip ────────────────────────────────────────────────────────

/**
 * One root node. Label, engine key, state — the same three columns the plates
 * carry, laid flat, because these five produce values rather than pictures and
 * a square frame around "the palette resolved in 8.2s" would be a frame around
 * nothing.
 */
function SystemRow({ node, now }: { node: RunNode; now: number }) {
  return (
    <li className={styles.row} data-state={node.state}>
      <span className={styles.rowLabel}>{ROOT_LABELS[node.key] ?? node.key}</span>
      <span className={styles.rowKey}>{node.key}</span>
      <span className={styles.rowTiming} title={node.error ?? undefined}>
        {nodeTiming(node, now)}
      </span>
    </li>
  );
}

// ── The finish ──────────────────────────────────────────────────────────────

/**
 * The payoff, directly under the sentence that names the cost and the time.
 *
 * A finished run is a design in the catalog like any of the other seventy-six,
 * so the action is to LOAD it: the whole app re-brands onto it, this page's
 * plates repaint in the generated background, and the Library and Inspect tabs
 * open on it. Nothing about that is special-cased for a fresh run — which is
 * the point worth making to a buyer.
 *
 * WHILE THE RUN IS STILL GOING it carries only the way out, and quietly: being
 * unable to leave a view for four minutes is a trap, and leaving costs nothing
 * — the run is server-side, `GET /runs/active` re-attaches on the next load,
 * and a Launch pressed meanwhile is refused with an offer to come back.
 */
function Finish({
  run,
  loaded,
  onStartAnother,
}: {
  run: RunView;
  loaded: boolean;
  onStartAnother: () => void;
}) {
  const [state, setState] = useState<'idle' | 'loading' | 'failed'>('idle');
  const runName = run.runName;
  const selectable = run.settled && run.status === 'succeeded' && runName !== null;

  const load = () => {
    if (runName === null) return;
    setState('loading');
    void selectDesign(runName).then((ok) => {
      setState(ok ? 'idle' : 'failed');
      // The address bar follows, so the Library and Inspect tabs open on this
      // design too. `syncThemeUrl` MERGES rather than rebuilding the query, so
      // the `?view=` this page is on survives (../appUrl.ts states that rule).
      if (ok) syncThemeUrl(runName);
    });
  };

  if (!run.settled) {
    return (
      <div className={styles.finish}>
        <button type="button" className={styles.textAction} onClick={onStartAnother}>
          Write another brief
        </button>
        <span className={styles.leaveNote}>the run keeps going without this tab</span>
      </div>
    );
  }

  return (
    <div className={styles.finish}>
      {selectable &&
        (loaded ? (
          <p className={styles.loaded}>
            <b>{runName}</b> is the app&rsquo;s live theme now — the plates below are painted
            in its own background, and the Library and Inspect tabs open on it.
          </p>
        ) : (
          <AppPrimaryButton
            text={state === 'loading' ? 'Loading…' : 'Load this theme'}
            onPressed={load}
            isLoading={state === 'loading'}
          />
        ))}
      <AppOutlineButton text="Write another brief" onPressed={onStartAnother} />
      {state === 'failed' && (
        <p className={styles.loadFailed}>
          The read API did not serve <b>{runName}</b>. It is a separate app on :8001 —
          start it with <code>make api</code>, and note it only lists a run once the run has
          a classification and a celebration image.
        </p>
      )}
    </div>
  );
}

// ── The brief, kept at the foot ─────────────────────────────────────────────

/**
 * What all of this was generated from, in full, at the bottom of the sheet.
 *
 * At the FOOT rather than the head because of what a reader wants when: during
 * the wait the question is "what is happening", and afterwards it is "and that
 * came from *this*?". Prose that long above the plates would also push the one
 * thing worth watching off the first screen.
 */
function BriefRecord({ brief }: { brief: BriefInput }) {
  return (
    <section className={styles.section}>
      <SectionHead id="studio-brief" title="The brief" count="5 fields">
        Everything above was generated from these words and nothing else. There is no asset
        library behind it, no template, and no per-tenant hand-off — five fields in, a whole
        branded app out.
      </SectionHead>
      <dl className={styles.brief}>
        <dt className={styles.briefKey}>short_desc</dt>
        <dd className={styles.briefValue}>{brief.design_direction.short_desc}</dd>
        <dt className={styles.briefKey}>long_desc</dt>
        <dd className={styles.briefProse}>{brief.design_direction.long_desc}</dd>
        <dt className={styles.briefKey}>colors_direction</dt>
        <dd className={styles.briefProse}>{brief.colors_direction.description}</dd>
      </dl>
    </section>
  );
}
