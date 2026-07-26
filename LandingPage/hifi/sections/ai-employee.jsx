// ai-employee.jsx — AI page §5. A day in the life, dealt as a deck.
//
// The headline is set into opposite corners with the deck working between them, so
// the section reads as one sentence wrapped around the thing it describes.
//
// Two entries are legible at once (the newest in front, the previous still readable
// above it) so the deck never demands a read-and-forget pace. Cards further back are
// blank paper: their text is hidden, so an exposed edge can never leak half a line.
//
// The deck's stacking geometry lives in ai.html's <style> block, because absolute
// stacking, transitions and the hue ramp cannot be expressed as inline styles. This
// file owns the copy, the timing and which card is active.
//
// The @<tag> hues come from AGENT_HUES in ds.jsx, shared with the §4 cards so the
// same channel is the same colour in both places.
//
// Carries [data-motif-section]. Exports AiEmployeeSection to window.

const AI_DECK_HOLD = 3500;      // ms a card stays in front
const AI_DECK_HOLD_FIRST = 2500; // the first deal is quicker, so the idea lands fast

function AiEmployeeSection() {
  const isMobile = useIsMobile();
  const c = COPY.ai.employee;
  const ref = React.useRef(null);
  const [deck, setDeck] = React.useState(false);
  const [active, setActive] = React.useState(0);

  // Deck mode is opt-in: without JS, or under reduced motion, the markup below
  // renders as a plain complete list that says everything the deck would say.
  React.useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    setDeck(true);
  }, []);

  // Runs only while the section is on screen, so a page left open in a background
  // tab is not dealing cards to nobody.
  React.useEffect(() => {
    if (!deck) return;
    const el = ref.current;
    if (!el) return;
    let timer = 0;
    let visible = false;

    const step = () => {
      setActive((i) => (i + 1) % c.log.length);
      timer = setTimeout(step, AI_DECK_HOLD);
    };
    const io = new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      clearTimeout(timer);
      if (visible) timer = setTimeout(step, AI_DECK_HOLD_FIRST);
    }, { rootMargin: IN_VIEW_MARGIN, threshold: 0 });

    io.observe(el);
    return () => { io.disconnect(); clearTimeout(timer); };
  }, [deck, c.log.length]);

  const half = {
    display: 'block', fontFamily: GW.sans, fontWeight: 600,
    fontSize: 'clamp(32px, 3.6vw + 14px, 78px)', lineHeight: 0.95,
    letterSpacing: '-0.035em', color: GW.ink, whiteSpace: 'nowrap',
  };

  return (
    <section
      ref={ref}
      data-motif-section
      data-screen-label="AI 05 Employee"
      className={deck ? 'cd-employee is-deck' : 'cd-employee'}
      style={{ position: 'relative', background: 'transparent', padding: isMobile ? '92px 0 96px' : '128px 0 132px' }}
    >
      <div style={{ position: 'relative', zIndex: 1, maxWidth: GW.maxW, margin: '0 auto', padding: isMobile ? '0 20px' : '0 32px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr)' }}>
          {/* display:contents keeps this one <h2> for semantics while letting the
              two halves sit in different grid rows */}
          <h2 style={{ display: 'contents', margin: 0 }}>
            <span data-reveal style={{ ...half, gridRow: 1, justifySelf: 'start' }}>{c.lede}</span>
            <span className="cd-log-trail" data-reveal style={{ '--rd': '90ms', ...half, gridRow: 4, justifySelf: 'end' }}>{c.trail}</span>
          </h2>

          <ol className="cd-log" style={{ gridRow: 2, listStyle: 'none', margin: '34px auto', padding: 0, maxWidth: 720, width: '100%' }}>
            {c.log.map((entry, i) => {
              const d = active - i;
              const cls =
                d < 0 ? '' :
                d === 0 ? ' is-active' :
                d === 1 ? ' is-prev' :
                ` is-back is-back-${Math.min(3, d - 1)}`;
              return (
                <li
                  key={entry.time + entry.tag}
                  className={`cd-log__card${deck ? cls : ''}`}
                  style={{ '--hue': AGENT_HUES[entry.tag] ?? 258 }}
                >
                  <div className="cd-log__meta">
                    <span className="cd-log__time">{entry.time}</span>
                    <span className="cd-log__tag">@{entry.tag}</span>
                  </div>
                  <p className="cd-log__text">{entry.text}</p>
                </li>
              );
            })}
          </ol>
        </div>
      </div>
    </section>
  );
}

window.AiEmployeeSection = AiEmployeeSection;
