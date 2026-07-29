// The brand brief, as the document it actually is.
//
// THE BRIEF IS FIVE FIELDS AND THERE IS NEVER A SIXTH: `design_direction`'s
// name / short_desc / long_desc and `colors_direction`'s description / mode
// (`ThemeService/schema/customization.py`, `extra="forbid"`). Everything the
// form collects beyond them is the RUN NAME, which is not part of the brief at
// all — it is the folder the run is written into, and afterwards the design's
// id in the catalog.
//
// The composition is deliberately the INSPECTOR's masthead turned into inputs:
// the design name at display scale, then the `app · id · mode` identity line
// underneath. That is the exact line `inspect/InspectView.tsx` prints over a
// finished artifact, so writing a brief is filling in the sheet the inspector
// will later read back. A boxed form on a card would have said "settings".
//
// Nothing here is disabled to enforce validity: a disabled Launch button hides
// its own reason. Submit always runs, and the refusals — this form's, and the
// four the studio can return — land where the problem is.

import { useState } from 'react';
import { toCss } from 'theme-react';

import { AppPrimaryButton } from '../widgets/AppPrimaryButton';

import styles from './BriefForm.module.css';
import { EXAMPLE_BRIEF, EXAMPLE_RUN_NAME } from './exampleBrief';
import { DARK_GROUND, LIGHT_GROUND } from './groundColors';
import type { ActiveRunConflict, BriefInput, ColorModeInput } from './studioApi';
import { StudioError, studioErrorText } from './studioApi';

export interface BriefDraft {
  name: string;
  shortDesc: string;
  longDesc: string;
  colorsDescription: string;
  mode: ColorModeInput;
  runName: string;
  /** Whether the author has edited the run name away from the suggestion. */
  runNameTouched: boolean;
}

const EMPTY_DRAFT: BriefDraft = Object.freeze({
  name: '',
  shortDesc: '',
  longDesc: '',
  colorsDescription: '',
  mode: 'dark',
  runName: '',
  runNameTouched: false,
});

export interface BriefFormProps {
  appId: string;
  /** Posts the launch. Rejects with `StudioError` on every refusal. */
  onLaunch: (input: { runName: string; brief: BriefInput }) => Promise<void>;
  /** Attach to the run a 409 says is already going, instead of starting one. */
  onWatchActive: (conflict: ActiveRunConflict) => void;
}

/**
 * A run folder's name, suggested from the brand name.
 *
 * The catalog's own convention (`ApexMMA`, `ZenBJJ`, `KillerMuayThai`): the
 * words joined, capitals kept. It is only a suggestion — the moment the author
 * types in the field it stops following.
 */
export function suggestRunName(name: string): string {
  return name
    .split(/[^A-Za-z0-9]+/)
    .filter((part) => part !== '')
    .map((part) => (part[0] ?? '').toUpperCase() + part.slice(1))
    .join('');
}

/**
 * `PathSegment` (`ThemeService/schema/primitives.py`), client-side: exactly one
 * safe folder segment. Checked here so the author is told at the field rather
 * than by a 422 after a round trip — the server still enforces it.
 */
function runNameProblem(runName: string): string | null {
  if (runName.trim() === '') return 'The run needs a name — it becomes the folder and the design id.';
  if (runName === '.' || runName === '..') return 'A run cannot be named “.” or “..”.';
  if (/[/\\]/.test(runName) || runName.includes('..')) {
    return 'One folder name only — no “/”, “\\” or “..”.';
  }
  return null;
}

/**
 * Autosizes a prose field to its content.
 *
 * A ref callback fires at COMMIT with the node in hand, which is how this
 * package measures without writing a ref during render or setting state from an
 * effect (../../CLAUDE.md, "Things that will bite").
 *
 * Every call site passes it as an INLINE arrow on purpose. React re-invokes a
 * ref callback whenever its identity changes, so an inline one runs after every
 * render — which is the only way the field also grows when its value is set
 * PROGRAMMATICALLY (loading the example brief), where no `input` event fires.
 * Two style writes per render on two fields is not a cost worth a `useEffect`
 * and a ref to avoid.
 */
function autosize(element: HTMLTextAreaElement | null): void {
  if (element === null) return;
  element.style.height = 'auto';
  element.style.height = `${String(element.scrollHeight)}px`;
}

export function BriefForm({ appId, onLaunch, onWatchActive }: BriefFormProps) {
  const [draft, setDraft] = useState<BriefDraft>(EMPTY_DRAFT);
  const [problems, setProblems] = useState<Readonly<Record<string, string>>>({});
  const [refusal, setRefusal] = useState<StudioError | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Derived during render, never mirrored into state: the suggestion follows
  // the brand name until the author takes the field over.
  const runName = draft.runNameTouched ? draft.runName : suggestRunName(draft.name);
  const patch = (next: Partial<BriefDraft>) => {
    setDraft((current) => ({ ...current, ...next }));
  };

  const loadExample = () => {
    setDraft({
      name: EXAMPLE_BRIEF.design_direction.name,
      shortDesc: EXAMPLE_BRIEF.design_direction.short_desc,
      longDesc: EXAMPLE_BRIEF.design_direction.long_desc,
      colorsDescription: EXAMPLE_BRIEF.colors_direction.description,
      mode: EXAMPLE_BRIEF.colors_direction.mode,
      runName: EXAMPLE_RUN_NAME,
      runNameTouched: true,
    });
    setProblems({});
    setRefusal(null);
  };

  const submit = () => {
    const found: Record<string, string> = {};
    // The same non-empty rule `Customization`'s validators carry, asked here
    // first so a blank field is answered at the field.
    if (draft.name.trim() === '') found.name = 'Every agent prompt opens with this name.';
    if (draft.shortDesc.trim() === '') found.short_desc = 'One sentence, and it cannot be blank.';
    if (draft.longDesc.trim() === '') {
      found.long_desc = 'This is the field the whole run is generated from.';
    }
    if (draft.colorsDescription.trim() === '') {
      found.description = 'Say what the four colour roles have to do.';
    }
    const nameProblem = runNameProblem(runName);
    if (nameProblem !== null) found.run_name = nameProblem;

    setProblems(found);
    setRefusal(null);
    if (Object.keys(found).length > 0) return;

    setSubmitting(true);
    void onLaunch({
      runName,
      brief: {
        design_direction: {
          name: draft.name,
          short_desc: draft.shortDesc,
          long_desc: draft.longDesc,
        },
        colors_direction: { description: draft.colorsDescription, mode: draft.mode },
      },
    })
      .catch((error: unknown) => {
        const studio = error instanceof StudioError ? error : new StudioError(0, String(error));
        setRefusal(studio);
        // A 422 that got past the checks above is answered at its own field.
        const fields = studio.fieldErrors;
        if (Object.keys(fields).length > 0) setProblems(fields);
      })
      .finally(() => {
        setSubmitting(false);
      });
  };

  return (
    <form
      className={styles.sheet}
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
    >
      <header className={styles.masthead}>
        <div className={styles.kickerRow}>
          <p className={styles.kicker}>New generation run</p>
          <button type="button" className={styles.textAction} onClick={loadExample}>
            Load an example brief
          </button>
        </div>

        <input
          className={styles.nameInput}
          value={draft.name}
          onChange={(event) => {
            patch({ name: event.target.value });
          }}
          placeholder="Name the brand"
          aria-label="Design name"
          autoComplete="off"
          spellCheck={false}
        />
        <FieldProblem problem={problems.name} />

        {/*
          The inspector's identity line, made editable. `combatden` is fixed —
          this browser shows one app's catalog, and a run made for another app
          could not be selected here afterwards.
        */}
        <div className={styles.identity}>
          <span className={styles.identityFixed}>{appId}</span>
          <span className={styles.identityDot}>·</span>
          <input
            className={styles.runNameInput}
            value={runName}
            onChange={(event) => {
              patch({ runName: event.target.value, runNameTouched: true });
            }}
            placeholder="run-name"
            aria-label="Run name"
            autoComplete="off"
            spellCheck={false}
            size={18}
          />
          <span className={styles.identityDot}>·</span>
          <ModeChoice
            mode={draft.mode}
            onChange={(mode) => {
              patch({ mode });
            }}
          />
        </div>
        <FieldProblem problem={problems.run_name} />
        <p className={styles.identityNote}>
          The run name becomes the folder under <code>apps/{appId}/</code> and the design&rsquo;s
          id in the catalog. It must be new — the studio only ever creates runs, it never
          overwrites one.
        </p>
      </header>

      <Field
        label="One-line identity"
        slot="short_desc"
        note="A single sentence naming who this gym is and who trains there. It opens every prompt in the run — the colour agent, the image agents, the copywriter and the classifier all read it."
        problem={problems.short_desc}
      >
        {/* A textarea, not an input: the real ones run a full sentence or two
            and an input would hide the end of what was typed. */}
        <textarea
          className={styles.lineInput}
          ref={(element) => {
            autosize(element);
          }}
          value={draft.shortDesc}
          onChange={(event) => {
            patch({ shortDesc: event.target.value });
          }}
          rows={2}
          placeholder="Focused and powerful — a jiu-jitsu academy built on control."
        />
      </Field>

      <Field
        label="The brand document"
        slot="long_desc"
        note="The longest and most load-bearing field: every image, colour and word in the finished theme is generated from it. The briefs that work read as a document — who trains here and why, how the brand speaks and how it must never speak, then the visual system every generated asset has to wear: feel, medium and materials, finish and light, energy by role, and the hard nos."
        problem={problems.long_desc}
      >
        <textarea
          className={styles.proseInput}
          ref={(element) => {
            autosize(element);
          }}
          value={draft.longDesc}
          onChange={(event) => {
            patch({ longDesc: event.target.value });
          }}
          rows={12}
          placeholder={
            'Who trains here, what the brand is and is not, how it speaks…\n\n' +
            'Visual system — the shared look every generated asset must wear:\n' +
            '- Feel:\n- Medium & materials:\n- Finish & light:\n- Energy by role:\n- Hard nos:'
          }
        />
      </Field>

      <Field
        label="Colour direction"
        slot="colors_direction.description"
        note="The four roles the app resolves — primary, background, text and accent — and the job each has to do. The engine derives the rest of the palette from them and holds the pair to WCAG AA, so describe intent and material rather than naming hex."
        problem={problems.description}
      >
        <textarea
          className={styles.proseInput}
          ref={(element) => {
            autosize(element);
          }}
          value={draft.colorsDescription}
          onChange={(event) => {
            patch({ colorsDescription: event.target.value });
          }}
          rows={7}
          placeholder={'- Primary:\n- Background:\n- Text:\n- Accent:'}
        />
      </Field>

      <footer className={styles.launch}>
        <p className={styles.cost}>
          A full run generates the whole theme from this brief alone — the palette, the
          typefaces, the copy, the icons and every image. It spends about a dollar of provider
          credit and takes several minutes, and only one run may be in flight at a time.
        </p>
        <div className={styles.launchRow}>
          <AppPrimaryButton
            text={submitting ? 'Launching…' : 'Launch the run'}
            onPressed={submit}
            isLoading={submitting}
          />
          {refusal !== null && <Refusal error={refusal} onWatchActive={onWatchActive} />}
        </div>
      </footer>
    </form>
  );
}

function Field({
  label,
  slot,
  note,
  problem,
  children,
}: {
  label: string;
  slot: string;
  note: string;
  problem: string | undefined;
  children: React.ReactNode;
}) {
  return (
    <section className={styles.field}>
      <div className={styles.fieldHead}>
        <h2 className={styles.fieldLabel}>{label}</h2>
        {/* The wire name, so what is typed here is traceable to the contract. */}
        <p className={styles.fieldSlot}>{slot}</p>
        <p className={styles.fieldNote}>{note}</p>
      </div>
      {children}
      <FieldProblem problem={problem} />
    </section>
  );
}

function FieldProblem({ problem }: { problem: string | undefined }) {
  if (problem === undefined) return null;
  return (
    <p className={styles.problem} role="alert">
      {problem}
    </p>
  );
}

/**
 * Light or dark, shown rather than named: each option carries the ground it
 * stands for. The choice decides what every generated image is authored
 * against, so a `<select>` would be the weakest possible way to ask it.
 */
function ModeChoice({
  mode,
  onChange,
}: {
  mode: ColorModeInput;
  onChange: (mode: ColorModeInput) => void;
}) {
  return (
    <span className={styles.modes} role="group" aria-label="Colour mode">
      {(['light', 'dark'] as const).map((option) => (
        <button
          key={option}
          type="button"
          className={styles.mode}
          aria-pressed={mode === option}
          onClick={() => {
            onChange(option);
          }}
        >
          {/* The same two colours every plate on the run sheet is painted in
              until the finished theme supplies its real background — one
              definition, in ./groundColors.ts. */}
          <span
            className={styles.ground}
            style={{ background: toCss(option === 'light' ? LIGHT_GROUND : DARK_GROUND) }}
          />
          {option}
        </button>
      ))}
    </span>
  );
}

/**
 * A refusal, in the words that name the recovery.
 *
 * The 409 that matters most gets an ACTION rather than a sentence: a run is
 * already going, and the useful answer is to watch that one — the studio
 * serializes runs because the providers rate-limit, so waiting is the only
 * other option anyway.
 */
function Refusal({
  error,
  onWatchActive,
}: {
  error: StudioError;
  onWatchActive: (conflict: ActiveRunConflict) => void;
}) {
  const active = error.activeRun;
  if (active !== null) {
    return (
      <p className={styles.refusal} role="alert">
        <span className={styles.refusalSlug}>
          {active.active_app_id}/{active.active_run_name}
        </span>{' '}
        is already generating. The studio runs one at a time because the providers
        rate-limit.{' '}
        <button
          type="button"
          className={styles.textAction}
          onClick={() => {
            onWatchActive(active);
          }}
        >
          Watch it instead
        </button>
      </p>
    );
  }
  if (error.offline) {
    return (
      <p className={styles.refusal} role="alert">
        The studio is not running. Start it with <code>cd ThemeService &amp;&amp; make studio</code>
        {' '}— it binds 127.0.0.1:8002 and is never deployed, because every launch spends real
        money.
      </p>
    );
  }
  return (
    <p className={styles.refusal} role="alert">
      {studioErrorText(error)}
    </p>
  );
}
