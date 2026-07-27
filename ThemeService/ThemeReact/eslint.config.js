import js from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import globals from 'globals';
import tseslint from 'typescript-eslint';

// The import gates below are not style rules — they are the enforcement for
// two architectural invariants that are otherwise invisible until something
// has already drifted. Both mirror rules the Flutter side states in prose and
// enforces with grep (see ../ThemeFlutter/CLAUDE.md, "Hard rules").
//
//  1. THE LIBRARY IS APP-AGNOSTIC. src/lib/ must never reach into src/app/.
//     Flutter's version: `grep -rn 'package:crm' lib` must be empty.
//
//  2. THE TWO TOKEN SYSTEMS NEVER MEET. The app chrome (GW + the CRM's light
//     DesignConstants) and the showcase island (ShowcaseTokens) share token
//     NAMES with different VALUES — radiusBig is 12 in one and 32 in the
//     other. They are separate modules, separate CSS-variable namespaces
//     (--gw-*/--adm-* vs --sc-*), and neither may import the other.
export default tseslint.config(
  { ignores: ['dist', 'node_modules', 'coverage'] },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: { 'react-hooks': reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
    },
  },

  // Gate 1 — the library stays app-agnostic.
  {
    files: ['src/lib/**/*.{ts,tsx}'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['**/app/**', '../app/*', '../../app/*'],
              message:
                'src/lib is app-agnostic. App-specific values arrive as arguments to initializeTheme / <ThemeProvider>, never as an import. See ../ThemeFlutter/CLAUDE.md "Hard rules".',
            },
          ],
        },
      ],
    },
  },

  // Gate 2a — the showcase island never sees the app-chrome tokens.
  {
    files: ['src/app/showcase/**/*.{ts,tsx}'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                '**/tokens/gw',
                '**/tokens/admin-tokens',
                '**/chrome/**',
                '**/browser/**',
                '**/widgets/**',
              ],
              message:
                'The showcase renders the MEMBER app and resolves only ShowcaseTokens (--sc-*). GW / DesignConstants are the surrounding admin chrome and use the same token names with different values.',
            },
          ],
        },
      ],
    },
  },

  // Gate 2b — the app chrome never reaches into the showcase's tokens.
  {
    files: ['src/app/**/*.{ts,tsx}'],
    ignores: ['src/app/showcase/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['**/showcase/showcase-tokens'],
              message:
                'ShowcaseTokens belong to the phone-frame island. Chrome uses GW / admin-tokens; the values behind the shared names differ.',
            },
          ],
        },
      ],
    },
  },
);
