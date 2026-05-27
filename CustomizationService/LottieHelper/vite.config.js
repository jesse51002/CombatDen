import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Dev-only "Save to repo" endpoint. The helper is a browser page, so it can't
// write to disk on its own — this middleware lets the Save button drop a
// designed preset (config.yaml + its animation JSON) straight into the preset
// library where the pipeline reads it, with no manual copy step:
//   assets/lottie_animations/<id>/config.yaml
//   assets/lottie_animations/<id>/<file>
// It is registered only via configureServer (the dev server). `vite build` /
// `vite preview` have no backend, by design — the tool is run with `npm run
// dev` (`make run`).
function savePresetPlugin() {
  // Resolved from this file's dir (LottieHelper/) up to the package root.
  const LIBRARY = path.resolve(__dirname, '..', 'assets', 'lottie_animations');
  // A single path segment must be non-empty and contain no separator / `..`.
  const badSegment = (s) =>
    !s || s.includes('/') || s.includes('\\') || s === '.' || s === '..';

  return {
    name: 'save-preset',
    configureServer(server) {
      server.middlewares.use('/api/save-preset', (req, res) => {
        const reply = (code, obj) => {
          res.statusCode = code;
          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify(obj));
        };
        if (req.method !== 'POST') return reply(405, { error: 'POST only' });

        let body = '';
        req.on('data', (c) => { body += c; });
        req.on('end', () => {
          let payload;
          try { payload = JSON.parse(body); }
          catch { return reply(400, { error: 'invalid JSON body' }); }

          const { id, file, yaml, animation } = payload || {};
          if (badSegment(id) || id === 'preset_id')
            return reply(400, { error: 'invalid or placeholder id' });
          // `file` is the JSON name relative to the preset folder. It may carry
          // a subpath, but every segment must stay inside the folder and the
          // last must end in .json.
          if (typeof file !== 'string' || !file.trim() || file === 'file.json'
              || file.startsWith('/') || !file.endsWith('.json')
              || file.split(/[\\/]/).some(badSegment))
            return reply(400, { error: 'invalid or placeholder file' });
          if (typeof yaml !== 'string' || typeof animation !== 'string')
            return reply(400, { error: 'yaml and animation are required' });
          // animation is the Lottie source — it must be valid JSON.
          try { JSON.parse(animation); }
          catch { return reply(400, { error: 'animation is not valid JSON' }); }

          const dest = path.join(LIBRARY, id);
          const jsonPath = path.join(dest, file);
          const overwritten = fs.existsSync(dest);
          try {
            fs.mkdirSync(path.dirname(jsonPath), { recursive: true });
            fs.writeFileSync(path.join(dest, 'config.yaml'), yaml, 'utf8');
            fs.writeFileSync(jsonPath, animation, 'utf8');
          } catch (err) {
            return reply(500, { error: String((err && err.message) || err) });
          }
          reply(200, {
            ok: true,
            path: `assets/lottie_animations/${id}/`,
            file,
            overwritten,
          });
        });
      });
    },
  };
}

// Relative base so the built dist/ opens from any path (incl. file://).
export default defineConfig({
  base: './',
  plugins: [savePresetPlugin()],
  build: { outDir: 'dist', emptyOutDir: true },
});
