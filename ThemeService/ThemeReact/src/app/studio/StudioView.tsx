// The generation studio — write a brief, press Launch, and watch a whole
// branded app get made from those words.
//
// ── DIRECTION CONTRACT ─────────────────────────────────────────────────────
// THESIS: a generation run is a PRESS RUN, so the wait is a sheet developing —
//   every frame laid out empty before the work lands, each filling as its node
//   finishes. It refuses the progress bar this category always ships: nobody
//   has measured what a run takes, so a bar would invent its own denominator
//   and spend four minutes proving nothing.
// OWN-WORLD: the sibling inspector's daylit control desk unchanged (cool
//   #F3F5F8 ground, cool near-black ink, Geist with Geist Mono for every
//   identifier and measurement, hairline rules, no cards, no shadows), with one
//   rule of its own — the ONLY saturated colour on the page is the colour the
//   engine made, arriving when the finished theme is loaded and the plates
//   repaint in its ground.
// STORY: a platform buyer watches ten images arrive one at a time out of five
//   fields of prose, then reads "$1.09, four minutes" and concludes the engine
//   generates rather than recolours.
// FIRST VIEWPORT: the brand name at display scale as the first input, the
//   editable `app · run · mode` identity line under it, then the brief's three
//   prose fields down a document measure with Launch at the foot.
// FORM: specimen sheet being made — first of the ordered list (plate catalogue
//   developing · specimen sheet built live · split desk · job log · DAG
//   tracks), taken directly rather than by concept seed: the visual world is
//   fixed by the sibling views and the content is fully enumerated.
// ───────────────────────────────────────────────────────────────────────────
//
// It talks to a LOCAL-ONLY FastAPI app (`ThemeService/src/studio/`, 127.0.0.1
// :8002), deliberately separate from the read API on :8001 — the read API is
// deployed and boots without any provider keys, which is a property importing
// the pipeline into it would destroy. Progress arrives over server-sent events
// that REPLAY FROM THE FIRST EVENT on connect, so opening this view late still
// shows the whole run.

import { useEffect, useState } from 'react';

import { APP_ID } from '../config';
import { ADM } from '../tokens/adminTokens';
import { AppSpinner } from '../widgets/AppSpinner';

import { BriefForm } from './BriefForm';
import { RunSheet } from './RunSheet';
import type { ActiveRunConflict, BriefInput } from './studioApi';
import { fetchActiveRun, launchRun } from './studioApi';
import styles from './StudioView.module.css';

/**
 * `attaching` exists because the studio serializes runs GLOBALLY: a page that
 * loads while one is in flight should re-attach to it rather than offer to
 * start a second that would only be refused. It is also what makes a reload
 * in the middle of a demo free.
 */
type Phase =
  | { readonly kind: 'attaching' }
  | { readonly kind: 'idle' }
  | { readonly kind: 'watching'; readonly runId: string; readonly brief: BriefInput | null };

export function StudioView() {
  const [phase, setPhase] = useState<Phase>({ kind: 'attaching' });

  useEffect(() => {
    let cancelled = false;
    void fetchActiveRun()
      .then((active) => {
        if (cancelled) return;
        setPhase(
          active === null
            ? { kind: 'idle' }
            : // A run this tab did not launch: its brief is not ours to show,
              // and the sheet says so rather than inventing one.
              { kind: 'watching', runId: active.run_id, brief: null },
        );
      })
      .catch(() => {
        // The studio is not running. The form is still the right thing to
        // show — pressing Launch is what surfaces the reason, together with
        // the command that fixes it.
        if (!cancelled) setPhase({ kind: 'idle' });
      });
    return () => {
      cancelled = true;
    };
  }, []);

  /**
   * Posts the launch and hands the run over to the sheet. Every refusal
   * propagates to the form, which owns the vocabulary for answering them.
   */
  const launch = async (input: { runName: string; brief: BriefInput }): Promise<void> => {
    const accepted = await launchRun({
      appId: APP_ID,
      runName: input.runName,
      brief: input.brief,
    });
    setPhase({ kind: 'watching', runId: accepted.run_id, brief: input.brief });
  };

  const watchActive = (conflict: ActiveRunConflict) => {
    setPhase({ kind: 'watching', runId: conflict.active_run_id, brief: null });
  };

  if (phase.kind === 'attaching') {
    return (
      <div className={styles.attaching}>
        <AppSpinner size={ADM.spinnerSizeLarge} strokeWidth={2} />
      </div>
    );
  }

  if (phase.kind === 'watching') {
    return (
      // KEYED ON THE RUN ID. `useRunStream` accumulates records in state, and
      // resetting them when the id changed would mean setting state from an
      // effect — an error in this package. A `key` remount is the replacement
      // it uses everywhere else (../../CLAUDE.md, "Things that will bite").
      <RunSheet
        key={phase.runId}
        runId={phase.runId}
        brief={phase.brief}
        onStartAnother={() => {
          setPhase({ kind: 'idle' });
        }}
      />
    );
  }

  return <BriefForm appId={APP_ID} onLaunch={launch} onWatchActive={watchActive} />;
}
