// One run's records, live — the browser's own `EventSource` with the poll
// endpoint behind it.
//
// NO LIBRARY. `EventSource` is built into every browser this app runs in, and
// this package's dependency count is near zero on purpose (../../../CLAUDE.md);
// the studio serves a plain `StreamingResponse` rather than reaching for
// `sse-starlette` for the same reason on its own side.
//
// THREE THINGS THIS HOOK HAS TO GET RIGHT:
//
//  1. **Close on the terminal record.** The server ENDS the stream after the
//     `settled` frame. An `EventSource` still open when that happens reconnects
//     automatically — and is replayed from index 0 again, forever. Closing on
//     the terminal record is the difference between a finished demo and a
//     silent request loop against a laptop.
//  2. **Survive a replay.** Every connect replays from 0, so a reconnect
//     re-delivers records already held. `appendRecord` drops those by index; a
//     record from beyond the end means frames went missing and is repaired from
//     the snapshot, never appended as a hole.
//  3. **Keep going when the stream does not.** `GET /runs/{id}` returns the
//     same records as one snapshot, so a dropped stream degrades to a 2s poll
//     rather than to a frozen page.
//
// The records list is held in an effect-LOCAL variable as well as in state:
// a callback closing over the state value would read whatever was current when
// the effect ran. This package cannot answer that with a ref written during
// render (the React Compiler's `refs` rule is an error here), and does not need
// to — the effect owns the subscription, so it can own its own mirror.

import { useEffect, useState } from 'react';

import { appendRecord, goneRecords, withTerminal } from './runFold';
import type { RunRecord } from './studioApi';
import { fetchRunSnapshot, runEventsUrl, StudioError } from './studioApi';

/** How the records are currently arriving. */
export type Transport = 'live' | 'polling' | 'closed';

export interface RunStream {
  readonly records: readonly RunRecord[];
  readonly transport: Transport;
}

/** Stable empty reference: a fresh literal would re-render every consumer. */
const NO_RECORDS: readonly RunRecord[] = Object.freeze([]);

/** Slow enough not to hammer a laptop, fast enough that a demo still moves. */
const POLL_INTERVAL_MS = 2000;

/**
 * Subscribe to one run.
 *
 * **Mount this under a `key={runId}`.** Resetting the accumulated records when
 * the id changes would mean setting state from an effect, which is an error in
 * this package (`set-state-in-effect`); a `key` remount is the replacement it
 * uses everywhere else (../../CLAUDE.md, "Things that will bite").
 */
export function useRunStream(runId: string): RunStream {
  const [records, setRecords] = useState<readonly RunRecord[]>(NO_RECORDS);
  const [transport, setTransport] = useState<Transport>('live');

  useEffect(() => {
    let stopped = false;
    let source: EventSource | null = null;
    let pollTimer: number | undefined;
    // The effect's own view of the list — see the file header.
    let current: readonly RunRecord[] = NO_RECORDS;

    const publish = (next: readonly RunRecord[]): void => {
      current = next;
      setRecords(next);
    };

    const isSettled = (list: readonly RunRecord[]): boolean =>
      list.length > 0 && list[list.length - 1]?.kind === 'settled';

    const stopPolling = (): void => {
      if (pollTimer !== undefined) {
        window.clearInterval(pollTimer);
        pollTimer = undefined;
      }
    };

    const finish = (): void => {
      stopPolling();
      source?.close();
      source = null;
      setTransport('closed');
    };

    const resync = (): void => {
      void fetchRunSnapshot(runId)
        .then((snapshot) => {
          if (stopped) return;
          const records = withTerminal(snapshot);
          // The snapshot is the whole list by construction, so it is only ever
          // adopted when it carries at least as much as we already hold —
          // a shorter answer would be a race, never a correction.
          if (records.length >= current.length) publish(records);
          if (isSettled(current)) finish();
        })
        .catch((error: unknown) => {
          if (stopped) return;
          // A 404 is an ANSWER, not a failure to reach: this run is gone, and
          // polling for it forever would leave the sheet claiming a run is
          // still going. Anything else is the studio being down — the next
          // tick tries again and the sheet keeps what already arrived.
          if (error instanceof StudioError && error.status === 404) {
            publish(goneRecords(current));
            finish();
          }
        });
    };

    const startPolling = (): void => {
      if (pollTimer !== undefined || stopped) return;
      setTransport('polling');
      resync();
      pollTimer = window.setInterval(resync, POLL_INTERVAL_MS);
    };

    if (typeof EventSource === 'undefined') {
      // No streaming here (a test runner, an exotic client). The poll answers
      // exactly the same question, just less often.
      startPolling();
      return () => {
        stopped = true;
        stopPolling();
      };
    }

    source = new EventSource(runEventsUrl(runId));

    // Every frame is a default (unnamed) `message` whose data is one RunRecord
    // as JSON — one frame shape, so `onmessage` is the whole client.
    source.onmessage = (event: MessageEvent<string>) => {
      if (stopped) return;
      let record: RunRecord;
      try {
        record = JSON.parse(event.data) as RunRecord;
      } catch {
        return;
      }
      const next = appendRecord(current, record);
      if (next === null) {
        // A gap: frames went missing. The list cannot repair itself.
        resync();
        return;
      }
      if (next !== current) publish(next);
      // A live frame means the stream is carrying again.
      stopPolling();
      if (record.kind === 'settled') finish();
      else setTransport('live');
    };

    source.onerror = () => {
      if (stopped) return;
      // `EventSource` reports both a transient drop (it reconnects itself) and
      // a dead server this way, and does not say which. Polling covers both,
      // and the next live frame cancels it.
      if (isSettled(current)) finish();
      else startPolling();
    };

    return () => {
      stopped = true;
      stopPolling();
      // A leaked stream against a local server is a slow leak nobody notices
      // until the demo, so this close is not optional.
      source?.close();
      source = null;
    };
  }, [runId]);

  return { records, transport };
}
