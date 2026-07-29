// The artifact inspector — everything one run of the ThemeService pipeline
// produced for the loaded design, on one sheet.
//
// ── DIRECTION CONTRACT ─────────────────────────────────────────────────────
// THESIS: a generated theme is a designed system, so it is presented the way a
//   foundry presents a release — one continuous specimen sheet where the
//   artifact supplies every colour, face and word and the page supplies only
//   the wall. It refuses the design-tokens grid this category always ships: a
//   swatch board with hex captions evidences a colour LIST, and has nowhere to
//   put the sentence the pipeline wrote about why each colour exists.
// OWN-WORLD: the CRM's daylit control desk unchanged (cool #F3F5F8 ground,
//   cool near-black ink, Geist, hairline rules, no boxed sections), with two
//   rules of its own — zero white cards and zero shadows, every specimen a
//   flat plate painted in the THEME's background under a chrome hairline; and
//   sapphire reserved for the two "you are here" marks, nothing else.
// STORY: a white-label platform buyer scrolls once and sees 28 computed
//   derivations as one instrument, four colours each with a written purpose,
//   35 tokens, two faces set live, five authored strings and fourteen
//   generated assets — and concludes the engine designs rather than recolours.
// FIRST VIEWPORT: kicker, the design name at 44–76px in the theme's OWN
//   display face, the identity line, the full-measure spectrum wiping in once,
//   then one sentence of live counts. Index rail from 1024px.
// FORM: specimen sheet fused with a colour-role dossier — first of the ordered
//   list (dossier · specimen sheet · colour-card deck · plate catalogue · data
//   plate · provenance ledger). Chosen directly rather than by concept seed:
//   the visual world is fixed by ../../../../CRM/DESIGN.md and the content is
//   fully enumerated, which is the "precisely specified request" case.
// ───────────────────────────────────────────────────────────────────────────
//
// THE TYPE RULE THE WHOLE SHEET OBEYS: anything the PIPELINE authored is set
// in the pipeline's own faces (the design name, the colour names, the colour
// prose, the copy strings); anything the PAGE says is Geist; every identifier
// and measured value is Geist Mono. That is what keeps a page about type from
// being a page of Geist describing type.
//
// No Dart counterpart — the Flutter side has no inspector. It reads only what
// ../showcase/ already reads, through the same hooks.

import { useEffect } from 'react';
import {
  fontStack,
  loadFontFamily,
  useActiveDesign,
  useThemeConfig,
  useThemeFontFamily,
} from 'theme-react';

import {
  SLOT_CELEBRATION_IMAGE,
  SLOT_FONT_BODY,
  SLOT_FONT_DISPLAY,
  SLOT_LOGO_PRIMARY,
} from '../showcase/showcaseSlots';
import { usePrefersReducedMotion } from '../widgets/usePrefersReducedMotion';

import type { FontView, ImageView, Inspection, SlotView } from './artifactModel';
import { buildInspection, spectrumBands } from './artifactModel';
import { IconPlate, ImagePlate } from './AssetPlates';
import { ColorRole } from './ColorRole';
import { IndexRail, type RailEntry } from './IndexRail';
import styles from './InspectView.module.css';
import { PaletteManifest } from './PaletteManifest';
import { SectionHead } from './SectionHead';
import { Spectrum } from './Spectrum';
import { TypeSpecimen } from './TypeSpecimen';

/**
 * Geist Mono is the design system's face for "tracked micro-labels"
 * (../../../../CRM/DESIGN.md §3) and this page is full of slot ids and hex.
 * ../App.tsx injects Geist at module scope for the whole app; the mono
 * companion is only ever needed here, so it is injected on mount instead of
 * costing every visitor a stylesheet they will not use.
 */
const MONO_FAMILY = 'Geist Mono';

/**
 * Where each generated string appears in the member app, quoted down from the
 * slot's own brief in `ThemeService/apps/combatden/app.yaml`. The strings are
 * 2–4 words; without the placement a reader cannot tell a button from a
 * headline, and the whole point of the section is that the engine wrote for a
 * specific moment.
 */
const TEXT_PLACEMENT: Readonly<Record<string, string>> = Object.freeze({
  class_booked_headline: 'Celebration headline, the moment a booking succeeds',
  reserve_cta: 'The commit button on a class',
  wins_title: 'Headline of the post-class recap',
  wins_subtitle: 'The line under it — the chattiest brand voice in the app',
  book_next_class_cta: 'The CTA back into booking, at the end of the recap',
});

/**
 * What each format slot governs, quoted down from the enum's own doc comment in
 * `MobileApp/lib/core/formats/layout_formats.dart`. Without it a reader sees
 * `rank_format → beltHero` and cannot tell which screen changed.
 *
 * A slot with no entry prints nothing rather than guessing: the vocabulary is
 * the app's, declared in its `app.yaml`, and this browser is a reader of it.
 */
const FORMAT_SURFACE: Readonly<Record<string, string>> = Object.freeze({
  app_shell_format: 'The chrome that frames every screen',
  home_format: 'The class schedule',
  videos_format: 'The video feed',
  rank_format: 'Rank and progress',
  rewards_format: 'The points store',
  class_format: 'Class detail and booking',
  celebration_format: 'The post-class cards',
});

export function InspectView() {
  const config = useThemeConfig();
  const activeDesign = useActiveDesign();
  const reducedMotion = usePrefersReducedMotion();
  // Empty fallbacks on purpose: `fontStack('')` is the system stack, so an
  // unproduced slot degrades to readable text instead of a named miss.
  const displayFont = useThemeFontFamily(SLOT_FONT_DISPLAY, '');
  const bodyFont = useThemeFontFamily(SLOT_FONT_BODY, '');

  useEffect(() => {
    loadFontFamily(MONO_FAMILY);
  }, []);

  // The arrival `?theme=` is applied once per page load by <DeepLinkTheme> in
  // ../App.tsx, above every view — this one no longer corrects it itself.

  if (config === null) return <NothingLoaded />;

  const artifact = buildInspection(config);
  const rail = railEntries(artifact);

  return (
    <div className={styles.view}>
      <div className={styles.railSlot}>
        <IndexRail entries={rail} reducedMotion={reducedMotion} />
      </div>

      <div className={styles.sheet}>
        <Masthead artifact={artifact} designId={activeDesign.id} displayFont={displayFont} />

        <section className={styles.section}>
          <SectionHead
            id="colours"
            title="Colour roles"
            count={`${String(artifact.counts.roles)} roles · ${String(artifact.counts.derivations)} derivations`}
          >
            Every role arrives with a name, a written purpose and seven computed
            derivations. Translucent values are shown composited over the theme&rsquo;s own
            background, because that is the surface the app paints them on.
          </SectionHead>
          <div className={styles.roles}>
            {artifact.roles.map((role) => (
              <ColorRole
                key={role.slot}
                role={role}
                background={artifact.background}
                displayFont={displayFont}
                bodyFont={bodyFont}
              />
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <SectionHead
            id="palette"
            title="Palette"
            count={`${String(artifact.counts.paletteTokens)} tokens`}
          >
            The flat map every client resolves against — each role, each of its
            derivations, and the surface tokens that belong to no role at all.
          </SectionHead>
          <PaletteManifest groups={artifact.paletteGroups} background={artifact.background} />
        </section>

        <section className={styles.section}>
          <SectionHead
            id="type"
            title="Typefaces"
            count={`${String(artifact.counts.fonts)} slots`}
          >
            A display face and a body face, picked for the brand and validated
            against Google Fonts during the run. Each is set in itself, under
            the name the run gave it and the reasoning it wrote for the pick.
          </SectionHead>
          <div className={styles.typeGrid}>
            {/* The display face is judged on a headline, so it gets one of the
                run's own generated strings at headline scale; the body face is
                judged on running copy, and its own description IS running copy
                the run wrote — so it needs no borrowed paragraph. */}
            <TypeSpecimen
              slot={SLOT_FONT_DISPLAY}
              face={fontFace(artifact, SLOT_FONT_DISPLAY)}
              sample={displaySample(artifact)}
            />
            <TypeSpecimen
              slot={SLOT_FONT_BODY}
              face={fontFace(artifact, SLOT_FONT_BODY)}
              sample={null}
            />
          </div>
        </section>

        <section className={styles.section}>
          <SectionHead
            id="voice"
            title="Written copy"
            count={`${String(artifact.counts.texts)} strings`}
          >
            The app&rsquo;s copy slots, rewritten in the brand&rsquo;s voice. These are the
            words a member reads, set here in the face they are read in.
          </SectionHead>
          <ol className={styles.strings}>
            {artifact.texts.map((text) => (
              <li key={text.slot} className={styles.string}>
                <div className={styles.stringMeta}>
                  <p className={styles.stringSlot}>{text.slot}</p>
                  <p className={styles.stringWhere}>{TEXT_PLACEMENT[text.slot] ?? ''}</p>
                </div>
                {text.value === null ? (
                  <p className={styles.stringMissing}>not produced</p>
                ) : (
                  <p
                    className={styles.stringValue}
                    style={{ fontFamily: fontStack(displayFont) }}
                  >
                    {text.value}
                  </p>
                )}
              </li>
            ))}
          </ol>
        </section>

        <section className={styles.section}>
          <SectionHead
            id="icons"
            title="Navigation icons"
            count={`${String(artifact.counts.icons)} slots`}
          >
            Monochrome SVGs the app recolours through a mask at runtime. Shown
            tinted with this theme&rsquo;s text colour, on its own background — the
            same two values the member app resolves.
          </SectionHead>
          <div className={styles.iconGrid}>
            {artifact.icons.map((icon) => (
              <IconPlate
                key={icon.slot}
                slot={icon.slot}
                present={icon.value !== null}
                background={artifact.background}
              />
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <SectionHead
            id="imagery"
            title="Imagery"
            count={`${String(artifact.counts.images)} slots`}
          >
            Transparent artwork generated for this theme and authored against
            its ground. Every plate below is painted in that ground, so what
            renders here is what renders on the phone. Each caption carries the
            complexity tier the run gave that prompt — the tier that chose how
            much compute the generator spent on it.
          </SectionHead>
          <div className={styles.featureGrid}>
            {featureImages(artifact.images).map((image) => (
              <ImagePlate
                key={image.slot}
                slot={image.slot}
                url={image.value?.url ?? null}
                complexity={image.value?.complexity ?? ''}
                background={artifact.background}
                wide
              />
            ))}
          </div>
          <div className={styles.imageGrid}>
            {restImages(artifact.images).map((image) => (
              <ImagePlate
                key={image.slot}
                slot={image.slot}
                url={image.value?.url ?? null}
                complexity={image.value?.complexity ?? ''}
                background={artifact.background}
              />
            ))}
          </div>
        </section>

        {/*
          Rendered only when the run HAS arrangements. Every other section
          declares its slots up front and prints "not produced" for a miss,
          which is honest because this browser knows what it expects. It does
          not know an app's format vocabulary, so an empty section here would
          claim a hole rather than report one.
        */}
        {artifact.formats.length > 0 && (
          <section className={styles.section}>
            <SectionHead
              id="arrangement"
              title="Arrangement"
              count={`${String(artifact.counts.formats)} surfaces`}
            >
              The engine also chose the SHAPE of each surface, not only what
              fills it. Each value names one complete, reviewed arrangement in
              the app&rsquo;s own vocabulary. Arrangement only: no screen gains or
              loses anything, so the app a member gets is rearranged, never
              reduced.
            </SectionHead>
            <ol className={styles.strings}>
              {artifact.formats.map((format) => (
                <li key={format.slot} className={styles.string}>
                  <div className={styles.stringMeta}>
                    <p className={styles.stringSlot}>{format.slot}</p>
                    <p className={styles.stringWhere}>{FORMAT_SURFACE[format.slot] ?? ''}</p>
                  </div>
                  {format.value === null ? (
                    <p className={styles.stringMissing}>not produced</p>
                  ) : (
                    <p className={styles.stringSlot}>{format.value}</p>
                  )}
                </li>
              ))}
            </ol>
          </section>
        )}

        <footer className={styles.colophon}>
          <p className={styles.colophonId}>
            {artifact.appId} · {activeDesign.id ?? '—'} · {artifact.colorMode}
          </p>
          <p className={styles.colophonNote}>
            Resolved live from ThemeService. Every client that loads this design — the
            member app, the admin console and this page — reads these same values.
          </p>
        </footer>
      </div>
    </div>
  );
}

function Masthead({
  artifact,
  designId,
  displayFont,
}: {
  artifact: Inspection;
  designId: string | null;
  displayFont: string;
}) {
  const assets = artifact.counts.images + artifact.counts.icons;
  return (
    <header className={styles.masthead}>
      <p className={styles.kicker}>Generated artifact</p>
      {/* Set in the theme's own display face: the first thing on the sheet is
          already a specimen, before a word of the page's own voice. */}
      <h1 className={styles.designName} style={{ fontFamily: fontStack(displayFont) }}>
        {artifact.designName === '' ? (designId ?? 'Untitled design') : artifact.designName}
      </h1>
      {/*
        The identity line is the sheet's address, and the run's CATEGORY is one
        of its coordinates: it is the bucket the library filtered on to reach
        this design, so a reader who arrived from there sees the same word they
        picked. It sits here rather than in the colophon because the colophon
        answers "where do these values come from", not "what is this".
        Omitted when the run carries none — the styles list refuses to list an
        uncategorised run, so an address with a blank coordinate can only be
        reached by a hand-typed `?theme=`.
      */}
      <p className={styles.identity}>
        {artifact.appId} · {designId ?? '—'}
        {artifact.category === '' ? '' : ` · ${artifact.category}`} ·{' '}
        {artifact.colorMode} mode
      </p>
      <Spectrum bands={spectrumBands(artifact.roles, artifact.background)} />
      <p className={styles.inventory}>
        One run of the pipeline produced all of it:{' '}
        <b>{artifact.counts.roles} colour roles</b> with{' '}
        <b>{artifact.counts.derivations} computed derivations</b>,{' '}
        <b>{artifact.counts.paletteTokens} palette tokens</b>,{' '}
        <b>{artifact.counts.fonts} typefaces</b>,{' '}
        <b>{artifact.counts.texts} written strings</b> and{' '}
        <b>{assets} generated assets</b>.
      </p>
    </header>
  );
}

function NothingLoaded() {
  return (
    <div className={styles.empty}>
      <p className={styles.emptyTitle}>No design is loaded.</p>
      <p className={styles.emptyNote}>
        The inspector reads whatever the runtime has resolved. Pick a design in the
        Library, or reload once ThemeService is reachable — the last good copy is
        restored from this browser when it is not.
      </p>
    </div>
  );
}

/** The rail's contents, built from the same counts the section heads print. */
function railEntries(artifact: Inspection): readonly RailEntry[] {
  return [
    { id: 'colours', label: 'Colour roles', count: `${String(artifact.counts.roles)} roles` },
    {
      id: 'palette',
      label: 'Palette',
      count: `${String(artifact.counts.paletteTokens)} tokens`,
    },
    { id: 'type', label: 'Typefaces', count: `${String(artifact.counts.fonts)} slots` },
    { id: 'voice', label: 'Written copy', count: `${String(artifact.counts.texts)} strings` },
    { id: 'icons', label: 'Navigation icons', count: `${String(artifact.counts.icons)} slots` },
    { id: 'imagery', label: 'Imagery', count: `${String(artifact.counts.images)} slots` },
    // Omitted, not zeroed, when the run predates the format node — the rail
    // indexes what the sheet actually renders.
    ...(artifact.formats.length > 0
      ? [
          {
            id: 'arrangement',
            label: 'Arrangement',
            count: `${String(artifact.counts.formats)} surfaces`,
          },
        ]
      : []),
  ];
}

/**
 * One font slot's record, or `null` when the run produced no family for it.
 *
 * Read off the artifact rather than through `useThemeFontFamily`, because the
 * specimen is reporting what THIS run carries — the resolvers exist to hand a
 * live value to a surface that must render regardless, which is the opposite
 * job. The two agree on the family; only the artifact has the prose.
 */
function fontFace(artifact: Inspection, slot: string): FontView | null {
  return artifact.fonts.find((font) => font.slot === slot)?.value ?? null;
}

/**
 * The two artworks that carry the theme at full size — the brand mark and the
 * celebration illustration — as opposed to the eight glyph-scale objects.
 * Split so the section has a shape: a uniform grid of ten would render a
 * 512px illustration at the size of a star.
 */
function featureImages(images: readonly SlotView<ImageView>[]): readonly SlotView<ImageView>[] {
  const featured = [SLOT_LOGO_PRIMARY, SLOT_CELEBRATION_IMAGE];
  return images.filter((image) => featured.includes(image.slot));
}

function restImages(images: readonly SlotView<ImageView>[]): readonly SlotView<ImageView>[] {
  const featured = [SLOT_LOGO_PRIMARY, SLOT_CELEBRATION_IMAGE];
  return images.filter((image) => !featured.includes(image.slot));
}

/**
 * A generated line for the display specimen.
 *
 * The LAST produced string, for the same reason `bodySample` takes the last
 * description: the first is `class_booked_headline`, which opens the Written
 * copy list directly below, and the same three words twice in one screen reads
 * as a bug. Last in slot order is `wins_subtitle` — also the longest of the
 * five, which is what a display face wants to be judged on.
 */
function displaySample(artifact: Inspection): string {
  const produced = artifact.texts.filter((text) => text.value !== null).at(-1);
  return produced?.value ?? 'Handgloves & Jiu-jitsu';
}
