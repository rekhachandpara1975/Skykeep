// Quick local check without Docker: applies migrations + pgTAP tests on PGlite with
// a minimal stub of Supabase's auth/storage/cron schemas. CI uses the real `supabase test db`.
// usage: node supabase/local-check/run.mjs   (needs: npm i @electric-sql/pglite)
import { PGlite } from '@electric-sql/pglite';
import { pgtap } from '@electric-sql/pglite/pgtap';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const db = new PGlite({ extensions: { pgtap } });

await db.exec(readFileSync(join(root, 'local-check/stub.sql'), 'utf8'));
for (const f of readdirSync(join(root, 'migrations')).sort()) {
  const sql = readFileSync(join(root, 'migrations', f), 'utf8')
    .replace(/create extension if not exists pg_cron;/i, '');
  try { await db.exec(sql); console.log('migration ok', f); }
  catch (e) { console.error('MIGRATION FAILED', f, e.message, e.position ?? ''); process.exit(1); }
}

await db.exec(readFileSync(join(root, 'seed.sql'), 'utf8'));
let failed = 0;
for (const f of readdirSync(join(root, 'tests')).filter((f) => f.endsWith('.sql')).sort()) {
  await db.exec('rollback').catch(() => {}); await db.exec('reset role');
  try {
    const res = await db.exec(readFileSync(join(root, 'tests', f), 'utf8'));
    for (const r of res) for (const row of r.rows) {
      const line = String(Object.values(row)[0] ?? '');
      if (/^(not ok|ok|#|1\.\.)/.test(line)) {
        if (line.startsWith('not ok') || /# Looks like you failed/.test(line)) { failed++; console.log('  ' + line); }
        else if (process.env.VERBOSE) console.log('  ' + line);
      }
    }
    console.log('tests ran', f);
  } catch (e) { failed++; const sql = readFileSync(join(root, 'tests', f), 'utf8'); console.error('TEST ERROR', f, e.message, e.position ? '\n  near: ' + sql.slice(Math.max(0, e.position - 200), e.position + 80) : ''); }
}
console.log(failed ? `FAILED (${failed})` : 'ALL PASSED');
process.exit(failed ? 1 : 0);
