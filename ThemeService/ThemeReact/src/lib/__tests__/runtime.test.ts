// Covers ../runtime.ts — the port of
// ../../../../ThemeFlutter/lib/customization_runtime.dart.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  ThemeRuntime,
  activeDesignId,
  initializeTheme,
  resetThemeRuntime,
  themeIsReady,
} from '../runtime';
import { themeDesignName } from '../theme/resolvers';

import { APEX_MMA_PAYLOAD } from './fixtures/apexmma';

const BASE_URL = 'http://theme.test';

function jsonResponse(body: unknown): Response {
  return { ok: true, status: 200, json: () => Promise.resolve(body) } as unknown as Response;
}

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  window.localStorage.clear();
  resetThemeRuntime();
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  fetchMock = vi.fn().mockResolvedValue(jsonResponse(APEX_MMA_PAYLOAD));
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  resetThemeRuntime();
});

const OPTIONS = { appId: 'combatden', designId: 'ApexMMA', themeBaseUrl: BASE_URL };

describe('initializeTheme', () => {
  it('wires the runtime so the context-free resolvers are branded', async () => {
    expect(themeIsReady()).toBe(false);
    expect(themeDesignName('none')).toBe('none');

    await initializeTheme(OPTIONS);

    expect(themeIsReady()).toBe(true);
    expect(themeDesignName('none')).toBe('Apex MMA');
    expect(activeDesignId()).toBe('ApexMMA');
  });

  it('is memoised, so a StrictMode double-mount boots once', async () => {
    const first = initializeTheme(OPTIONS);
    const second = initializeTheme(OPTIONS);
    expect(second).toBe(first);
    await first;
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('never throws, even with nothing reachable', async () => {
    fetchMock.mockRejectedValue(new TypeError('offline'));
    await expect(initializeTheme(OPTIONS)).resolves.toBeUndefined();
    expect(themeIsReady()).toBe(true);
    expect(themeDesignName('none')).toBe('none');
  });
});

describe('resetThemeRuntime', () => {
  it('clears the store AND the memoised bootstrap, so a re-init really re-boots', async () => {
    await initializeTheme(OPTIONS);
    resetThemeRuntime();

    expect(themeIsReady()).toBe(false);
    expect(themeDesignName('none')).toBe('none');

    await initializeTheme(OPTIONS);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(themeDesignName('none')).toBe('Apex MMA');
  });
});

describe('the ThemeRuntime facade', () => {
  it('exposes the same functions under the Dart names', async () => {
    await ThemeRuntime.initialize(OPTIONS);
    expect(ThemeRuntime.isReady()).toBe(true);
    expect(ThemeRuntime.activeDesignId()).toBe('ApexMMA');
    ThemeRuntime.reset();
    expect(ThemeRuntime.isReady()).toBe(false);
  });

  it('selectDesign resolves false rather than throwing before bootstrap', async () => {
    await expect(ThemeRuntime.selectDesign('ZenBJJ')).resolves.toBe(false);
  });
});