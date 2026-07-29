import { describe, expect, it } from 'vitest';

import { DEFAULTS, resolveBackendBaseUrl, resolveThemeBaseUrl } from '../config';

describe('base URL resolution', () => {
  it('falls back to the localhost defaults, so the dev loop needs no .env', () => {
    expect(resolveThemeBaseUrl()).toBe('http://localhost:8001');
    expect(resolveBackendBaseUrl()).toBe('http://localhost:8000');
  });

  it('prefers an explicit override, which is how a UMD consumer configures it', () => {
    expect(resolveThemeBaseUrl('https://theme.combatden.net')).toBe('https://theme.combatden.net');
    expect(resolveBackendBaseUrl('https://api.combatden.net')).toBe('https://api.combatden.net');
  });

  it('strips trailing slashes, so joined paths are never double-slashed', () => {
    expect(resolveThemeBaseUrl('https://theme.combatden.net/')).toBe('https://theme.combatden.net');
    expect(resolveThemeBaseUrl('https://theme.combatden.net///')).toBe(
      'https://theme.combatden.net',
    );
  });

  it('treats an empty override as absent rather than as an empty base URL', () => {
    expect(resolveThemeBaseUrl('')).toBe(DEFAULTS.themeBaseUrl);
  });
});
