// The fold is the one part of the studio with real branching, and it has to be
// right for a REPLAYED stream as well as a live one — the server replays from
// index 0 on every connect, so the same list has to produce the same run
// whether a tab watched from the first second or opened after it finished.
//
// The records below are shaped exactly as the studio emits them; the stub
// pipeline in `ThemeService/tests/test_studio.py` writes the same sequence.

import { describe, expect, it } from 'vitest';

import {
  appendRecord,
  foldRecords,
  formatCost,
  formatElapsed,
  goneRecords,
  liveSeconds,
  nodeTiming,
  ROOT_NODE_KEYS,
  withTerminal,
} from '../runFold';
import type { ProgressEvent, RunRecord, RunSnapshot } from '../studioApi';

const T0 = '2026-07-27T12:00:00+00:00';

let cursor = 0;

function reset(): void {
  cursor = 0;
}

function launched(runName = 'NorthgateBoxing'): RunRecord {
  return {
    kind: 'launched',
    index: cursor++,
    at: T0,
    run_id: 'a'.repeat(32),
    app_id: 'combatden',
    run_name: runName,
  };
}

function progress(event: ProgressEvent, at = T0): RunRecord {
  return { kind: 'progress', index: cursor++, at, event };
}

function settled(status: 'succeeded' | 'failed' | 'crashed', error: string | null = null): RunRecord {
  return { kind: 'settled', index: cursor++, at: T0, status, error };
}

/** The shape a real combatden run takes: five roots, then images in two levels. */
function fullRun(): RunRecord[] {
  reset();
  return [
    launched(),
    progress({
      kind: 'run_started',
      app_id: 'combatden',
      run_id: 'NorthgateBoxing',
      total_levels: 3,
      total_nodes: 8,
    }),
    progress({
      kind: 'level_started',
      level: 0,
      level_nodes: ['category', 'color', 'font', 'icon', 'text'],
      total_levels: 3,
    }),
    progress({ kind: 'node_started', node: 'color', level: 0 }),
    progress({ kind: 'node_finished', node: 'color', level: 0, ok: true, elapsed_seconds: 8.2 }),
    progress({ kind: 'level_started', level: 1, level_nodes: ['logo_primary', 'single_point'] }),
    progress({ kind: 'node_started', node: 'logo_primary', image_slot: 'logo_primary', level: 1 }),
    progress({
      kind: 'node_finished',
      node: 'logo_primary',
      image_slot: 'logo_primary',
      level: 1,
      ok: true,
      elapsed_seconds: 41.8,
    }),
  ];
}

describe('foldRecords', () => {
  it('reads the run identity off the launch header', () => {
    const run = foldRecords(fullRun());

    expect(run.runId).toBe('a'.repeat(32));
    expect(run.appId).toBe('combatden');
    expect(run.runName).toBe('NorthgateBoxing');
    expect(run.startedAt).toBe(T0);
    expect(run.settled).toBe(false);
    expect(run.status).toBe('running');
  });

  it('is EMPTY-SAFE — nothing has arrived is a state, not a crash', () => {
    const run = foldRecords([]);

    expect(run.runId).toBeNull();
    expect(run.roots).toEqual([]);
    expect(run.slots).toEqual([]);
    expect(run.nodes.total).toBe(0);
    expect(run.expectedImages).toBeNull();
  });

  it('splits the engine roots from the image slots', () => {
    const run = foldRecords(fullRun());

    // The five frozen `DependencyKind` keys, in their canonical order — not the
    // alphabetical order `level_nodes` delivered them in.
    expect(run.roots.map((node) => node.key)).toEqual([...ROOT_NODE_KEYS]);
    expect(run.slots.map((node) => node.key)).toEqual(['logo_primary', 'single_point']);
  });

  it('queues a whole level the moment it starts, so the sheet lays out first', () => {
    const run = foldRecords(fullRun());

    // `single_point` has not started; it must still be on the sheet.
    const pending = run.slots.find((node) => node.key === 'single_point');
    expect(pending?.state).toBe('queued');
    expect(pending?.level).toBe(1);
  });

  it('tracks each node through started → finished with its own elapsed', () => {
    const run = foldRecords(fullRun());

    const color = run.roots.find((node) => node.key === 'color');
    expect(color?.state).toBe('done');
    expect(color?.elapsedSeconds).toBe(8.2);

    const logo = run.slots.find((node) => node.key === 'logo_primary');
    expect(logo?.state).toBe('done');
    expect(logo?.elapsedSeconds).toBe(41.8);
    expect(logo?.startedAt).toBe(T0);
  });

  it('derives the total image count from total_nodes minus the roots', () => {
    // The denominator the status line needs ("3 of 10 images") is available
    // seconds into the run, long before the last slot id is known.
    const run = foldRecords(fullRun());

    expect(run.totalNodes).toBe(8);
    expect(run.expectedImages).toBe(3);
  });

  it('never reports fewer expected images than it has already seen', () => {
    reset();
    const run = foldRecords([
      launched(),
      progress({ kind: 'run_started', total_levels: 1, total_nodes: 1 }),
      progress({ kind: 'level_started', level: 0, level_nodes: ['color'] }),
      progress({ kind: 'level_started', level: 1, level_nodes: ['a', 'b', 'c'] }),
    ]);

    // total_nodes (1) is nonsense against four observed nodes; the floor is
    // what was actually seen, never a negative denominator.
    expect(run.expectedImages).toBe(3);
  });

  it('counts a failed node as failed and keeps its error', () => {
    reset();
    const run = foldRecords([
      launched(),
      progress({ kind: 'level_started', level: 1, level_nodes: ['giftbox'] }),
      progress({ kind: 'node_started', node: 'giftbox', image_slot: 'giftbox', level: 1 }),
      progress({
        kind: 'node_failed',
        node: 'giftbox',
        image_slot: 'giftbox',
        level: 1,
        ok: false,
        elapsed_seconds: 3.4,
        error: 'RuntimeError: provider melted',
      }),
    ]);

    const giftbox = run.slots[0];
    expect(giftbox?.state).toBe('failed');
    expect(giftbox?.error).toBe('RuntimeError: provider melted');
    expect(run.images.failed).toBe(1);
  });

  it('marks work still pending at settle as NOT PRODUCED, never as running', () => {
    // The executor skips the regenerating dependents of a failed node without
    // emitting anything for them. Without this, a failed `single_point` would
    // leave `giftbox` spinning forever on a run that is over.
    reset();
    const run = foldRecords([
      launched(),
      progress({ kind: 'level_started', level: 1, level_nodes: ['single_point'] }),
      progress({ kind: 'node_started', node: 'single_point', image_slot: 'single_point', level: 1 }),
      progress({
        kind: 'node_failed',
        node: 'single_point',
        image_slot: 'single_point',
        ok: false,
        error: 'boom',
      }),
      progress({ kind: 'level_started', level: 2, level_nodes: ['giftbox'] }),
      progress({ kind: 'run_finished', elapsed_seconds: 12, cost: 0.4, generated: [] }),
      settled('succeeded'),
    ]);

    expect(run.slots.find((node) => node.key === 'giftbox')?.state).toBe('skipped');
    expect(run.images.running).toBe(0);
    expect(run.images.queued).toBe(0);
  });

  it('carries the cost and the elapsed off run_finished', () => {
    reset();
    const run = foldRecords([
      launched(),
      progress({
        kind: 'run_finished',
        elapsed_seconds: 252.4,
        cost: 1.0937,
        generated: ['color', 'logo_primary'],
      }),
      settled('succeeded'),
    ]);

    expect(run.settled).toBe(true);
    expect(run.status).toBe('succeeded');
    expect(run.finish?.cost).toBeCloseTo(1.0937);
    expect(run.finish?.elapsedSeconds).toBe(252.4);
    expect(run.finish?.generated).toEqual(['color', 'logo_primary']);
  });

  it('reads a crashed log — a log whose last line is not terminal', () => {
    // The registry synthesises this terminal record so a subscriber can close
    // instead of reconnecting forever.
    reset();
    const run = foldRecords([
      launched(),
      progress({ kind: 'run_started', total_nodes: 8, total_levels: 3 }),
      settled('crashed', 'the run log has no terminal record'),
    ]);

    expect(run.status).toBe('crashed');
    expect(run.error).toBe('the run log has no terminal record');
    expect(run.settled).toBe(true);
  });

  it('folds a REPLAY to exactly the same run as the live stream did', () => {
    // The whole reason the rendering is a fold: a tab that opens after the run
    // finished receives every record from index 0 and must show the same sheet.
    const records = fullRun();
    const live = foldRecords(records);
    const replayed = foldRecords([...records]);

    expect(replayed).toEqual(live);
  });

  it('lets an explicit image_slot outrank the key list', () => {
    // Belt and braces on the `DependencyKind` invariant: if the engine ever
    // named a node an image slot, the engine wins.
    reset();
    const run = foldRecords([
      launched(),
      progress({ kind: 'level_started', level: 0, level_nodes: ['icon'] }),
      progress({ kind: 'node_started', node: 'icon', image_slot: 'icon', level: 0 }),
    ]);

    expect(run.roots).toEqual([]);
    expect(run.slots.map((node) => node.key)).toEqual(['icon']);
  });

  it('ignores a progress line with no event and an unnamed node', () => {
    reset();
    const run = foldRecords([
      launched(),
      { kind: 'progress', index: cursor++, at: T0, event: null },
      progress({ kind: 'node_finished', ok: true, elapsed_seconds: 1 }),
    ]);

    expect(run.nodes.total).toBe(0);
    expect(run.settled).toBe(false);
  });
});

describe('appendRecord', () => {
  it('appends the next record in sequence', () => {
    reset();
    const first = launched();
    const next = appendRecord([], first);

    expect(next).toEqual([first]);
  });

  it('DROPS a record already held, because every connect replays from 0', () => {
    reset();
    const held = [launched(), progress({ kind: 'run_started', total_nodes: 8 })];

    // A reconnect re-delivers index 0. Appending it again would double the log.
    expect(appendRecord(held, held[0] as RunRecord)).toBe(held);
    expect(appendRecord(held, held[1] as RunRecord)).toBe(held);
  });

  it('refuses a record from beyond the end so the list stays contiguous', () => {
    reset();
    const held = [launched()];
    const gapped: RunRecord = { kind: 'settled', index: 7, at: T0, status: 'succeeded' };

    // `null` is the caller's signal to resynchronise from `GET /runs/{id}` —
    // a hole in the list would silently mis-fold every node after it.
    expect(appendRecord(held, gapped)).toBeNull();
  });
});

describe('closing a polled run', () => {
  function snapshot(
    status: RunSnapshot['status'],
    records: readonly RunRecord[],
    error: string | null = null,
  ): RunSnapshot {
    return {
      run_id: 'a'.repeat(32),
      app_id: 'combatden',
      run_name: 'NorthgateBoxing',
      status,
      started_at: T0,
      finished_at: status === 'running' ? null : T0,
      error,
      records,
    };
  }

  it('leaves a running snapshot exactly as it came', () => {
    reset();
    const records = [launched()];

    expect(withTerminal(snapshot('running', records))).toBe(records);
  });

  it('leaves a snapshot that already ends on a terminal record alone', () => {
    reset();
    const records = [launched(), settled('succeeded')];

    expect(withTerminal(snapshot('succeeded', records))).toBe(records);
  });

  it('CLOSES a crashed run the poll would otherwise never end', () => {
    // The stream synthesises this record; `GET /runs/{id}` reports the crash on
    // `status` and returns the raw log lines. Without reading that back, a
    // polled crashed run would show "still generating" forever.
    reset();
    const records = [launched(), progress({ kind: 'run_started', total_nodes: 8 })];

    const closed = withTerminal(snapshot('crashed', records, 'the studio process died'));

    expect(closed).toHaveLength(3);
    expect(closed[2]?.kind).toBe('settled');
    expect(foldRecords(closed).status).toBe('crashed');
    expect(foldRecords(closed).settled).toBe(true);
  });

  it('closes a run the studio no longer has at all', () => {
    reset();
    const closed = goneRecords([launched()]);
    const run = foldRecords(closed);

    expect(run.settled).toBe(true);
    expect(run.status).toBe('crashed');
    expect(run.error).toContain('.studio/runs/');
  });
});

describe('reading the numbers', () => {
  it('formats elapsed the way a demo says it out loud', () => {
    expect(formatElapsed(0)).toBe('0s');
    expect(formatElapsed(41.8)).toBe('41s');
    expect(formatElapsed(64)).toBe('1m 04s');
    expect(formatElapsed(252.4)).toBe('4m 12s');
    expect(formatElapsed(null)).toBe('—');
  });

  it('formats the cost to the cent — the number this page exists to show', () => {
    expect(formatCost(1.0937)).toBe('$1.09');
    expect(formatCost(0)).toBe('$0.00');
    expect(formatCost(null)).toBe('—');
  });

  it('counts a running node from its own start, and never backwards', () => {
    const started = Date.parse(T0);

    expect(liveSeconds(T0, started + 4200)).toBeCloseTo(4.2);
    // A machine whose clock stepped reads as 0, not as a run in the future.
    expect(liveSeconds(T0, started - 9000)).toBe(0);
    expect(liveSeconds(null, started)).toBeNull();
    expect(liveSeconds('not a date', started)).toBeNull();
  });

  it('reports each node state in the caption vocabulary', () => {
    const base = { key: 'giftbox', kind: 'image' as const, level: 1, error: null };
    const now = Date.parse(T0) + 12_000;

    expect(nodeTiming({ ...base, state: 'queued', startedAt: null, elapsedSeconds: null }, now)).toBe(
      'queued',
    );
    expect(nodeTiming({ ...base, state: 'running', startedAt: T0, elapsedSeconds: null }, now)).toBe(
      '12s',
    );
    expect(nodeTiming({ ...base, state: 'done', startedAt: T0, elapsedSeconds: 41.8 }, now)).toBe(
      '41s',
    );
    expect(nodeTiming({ ...base, state: 'failed', startedAt: T0, elapsedSeconds: 3 }, now)).toBe(
      'failed',
    );
    expect(nodeTiming({ ...base, state: 'skipped', startedAt: null, elapsedSeconds: null }, now)).toBe(
      'not produced',
    );
  });
});
