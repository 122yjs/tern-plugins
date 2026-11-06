#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

const args = process.argv.slice(2);
function arg(name, def) {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
}

const agent = arg('agent', '');
const id = arg('id', '');
const file = arg('path', '');
const errors = [];

function rm(x) {
  if (!x) return;
  try { fs.rmSync(x, { recursive: true, force: true }); }
  catch (e) { errors.push(x + ': ' + e.message); }
}

if (!id || !file) {
  process.stdout.write(JSON.stringify({ ok: false, errors: ['missing id or path'] }));
  process.exit(0);
}

if (agent === 'claude') {
  rm(file);
  rm(file.replace(/\.jsonl$/i, ''));
} else if (agent === 'pi') {
  rm(file);
} else if (agent === 'omp') {
  rm(file);
  rm(file.replace(/\.jsonl$/i, ''));
} else if (agent === 'antigravity') {
  rm(file);
  const home = process.env.USERPROFILE || os.homedir();
  for (const root of [path.join(home, '.gemini', 'antigravity'), path.join(home, '.gemini', 'antigravity-cli')]) {
    rm(path.join(root, 'conversations', id + '.db'));
    const dbp = path.join(root, 'conversation_summaries.db');
    if (fs.existsSync(dbp)) {
      try {
        const { DatabaseSync } = require('node:sqlite');
        const db = new DatabaseSync(dbp);
        db.prepare('delete from conversation_summaries where conversation_id = ?').run(id);
        db.close();
      } catch (e) {
        errors.push(dbp + ': ' + e.message);
      }
    }
  }
} else {
  errors.push('unknown agent ' + agent);
}

process.stdout.write(JSON.stringify({ ok: errors.length === 0, errors }));
