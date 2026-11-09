#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

const home = process.env.USERPROFILE || process.env.HOME || os.homedir();
const out = [];

function readdir(d) {
  try { return fs.readdirSync(d, { withFileTypes: true }); } catch { return []; }
}
function stat(p) { try { return fs.statSync(p); } catch { return null; } }
function lines(p) { try { return fs.readFileSync(p, 'utf8').split('\n'); } catch { return []; } }
function headText(p, max) {
  let fd;
  try {
    fd = fs.openSync(p, 'r');
    const buf = Buffer.alloc(max || 65536);
    const n = fs.readSync(fd, buf, 0, buf.length, 0);
    return buf.toString('utf8', 0, n);
  } catch { return ''; }
  finally { if (fd !== undefined) try { fs.closeSync(fd); } catch {} }
}

function ompMeta(p) {
  let id = '', cwd = '', title = '';
  for (const line of headText(p, 65536).split('\n')) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (o.type === 'title' && o.title) title = clean(o.title);
    else if (o.type === 'session') {
      id = o.id || id;
      cwd = o.cwd || cwd;
      if (!title && o.title) title = clean(o.title);
    }
    if (id && cwd && title) break;
  }
  if (!title) {
    for (const line of headText(p, 262144).split('\n')) {
      let o; try { o = JSON.parse(line); } catch { continue; }
      if (o.type === 'message' && o.message && o.message.role === 'user') {
        const c = o.message.content;
        const text = typeof c === 'string' ? c : (Array.isArray(c) ? c.filter(x => x && x.type === 'text').map(x => x.text).join(' ') : '');
        const t = clean(text);
        if (t) { title = t; break; }
      }
    }
  }
  return { id, cwd, title };
}
function clean(s) {
  return String(s || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 160);
}
function isMetaPrompt(t) {
  return /^(\/|Set effort level to|Caveat: The messages below were generated|Name this chat from the user's first request|This session is being continued|<command-|<local-command|\[Request interrupted)/i.test(t);
}

function claudeMeta(p) {
  let title = '', cwd = '';
  for (const line of lines(p)) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (!cwd && typeof o.cwd === 'string') cwd = o.cwd;
    if (!title && o.type === 'user' && !o.isSidechain && o.message && typeof o.message.content === 'string') {
      const t = clean(o.message.content);
      if (t && !t.startsWith('<') && !isMetaPrompt(t)) title = t;
    }
    if (title && cwd) break;
  }
  return { title, cwd };
}

function piMeta(p) {
  let id = '', cwd = '', title = '';
  for (const line of lines(p)) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (o.type === 'session') { id = o.id || id; cwd = o.cwd || cwd; }
    if (!title && o.type === 'message' && o.message && o.message.role === 'user') {
      const c = o.message.content;
      const text = typeof c === 'string' ? c : (Array.isArray(c) ? c.filter(x => x && x.type === 'text').map(x => x.text).join(' ') : '');
      const t = clean(text);
      if (t) title = t;
    }
    if (id && cwd && title) break;
  }
  return { id, cwd, title };
}

function parseTime(s) {
  if (!s) return 0;
  const t = String(s).replace(' ', 'T').replace(/(\.\d{3})\d+/, '$1');
  const ms = Date.parse(t);
  return Number.isFinite(ms) ? ms : 0;
}

function firstWorkspace(s) {
  try {
    const arr = JSON.parse(s || '[]');
    if (!Array.isArray(arr) || !arr.length) return '';
    let u = String(arr[0]).replace(/^file:\/\//i, '');
    u = decodeURIComponent(u);
    if (/^\/[A-Za-z]:\//.test(u)) u = u.slice(1);
    u = u.replace(/\//g, '\\');
    return u ? u[0].toUpperCase() + u.slice(1) : u;
  } catch { return ''; }
}

function stripMeta(t) {
  return String(t || '')
    .replace(/<ADDITIONAL_METADATA>[\s\S]*?<\/ADDITIONAL_METADATA>/g, '')
    .replace(/<USER_SETTINGS_CHANGE>[\s\S]*?<\/USER_SETTINGS_CHANGE>/g, '')
    .replace(/<\/?USER_REQUEST>/g, '')
    .trim();
}

function agyTranscriptFiles(brain) {
  const single = path.join(brain, '.system_generated', 'logs', 'transcript_full.jsonl');
  if (fs.existsSync(single)) return [single];
  const dir = path.join(brain, '.system_generated', 'logs', 'chunks', 'transcript_full');
  try {
    return fs.readdirSync(dir).filter(f => f.endsWith('.jsonl')).sort().map(f => path.join(dir, f));
  } catch { return []; }
}

function agyFirstUser(brain) {
  for (const f of agyTranscriptFiles(brain)) {
    for (const line of lines(f)) {
      let o; try { o = JSON.parse(line); } catch { continue; }
      if (o.type === 'USER_INPUT') {
        const t = clean(stripMeta(o.content));
        if (t) return t;
      }
    }
  }
  return '';
}

// conversationId -> workspace, from the CLI prompt history.
const agyWorkspace = new Map();
for (const h of [path.join(home, '.gemini', 'antigravity-cli', 'history.jsonl'), path.join(home, '.gemini', 'antigravity', 'history.jsonl')]) {
  for (const line of lines(h)) {
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (o.conversationId && o.workspace && !agyWorkspace.has(o.conversationId)) agyWorkspace.set(o.conversationId, o.workspace);
  }
}

const claudeBase = path.join(home, '.claude', 'projects');
for (const proj of readdir(claudeBase)) {
  if (!proj.isDirectory()) continue;
  const dir = path.join(claudeBase, proj.name);
  for (const f of readdir(dir)) {
    if (!f.isFile() || !f.name.endsWith('.jsonl')) continue;
    const p = path.join(dir, f.name);
    const st = stat(p);
    if (!st) continue;
    const m = claudeMeta(p);
    if (!m.title) continue;
    out.push({
      agent: 'claude',
      id: f.name.slice(0, -6),
      title: m.title,
      cwd: m.cwd,
      path: p,
      time: st.mtimeMs,
      preview: m.title,
    });
  }
}

const piBase = path.join(home, '.pi', 'agent', 'sessions');
for (const proj of readdir(piBase)) {
  if (!proj.isDirectory()) continue;
  const dir = path.join(piBase, proj.name);
  for (const f of readdir(dir)) {
    if (!f.isFile() || !f.name.endsWith('.jsonl')) continue;
    const p = path.join(dir, f.name);
    const st = stat(p);
    if (!st) continue;
    const m = piMeta(p);
    out.push({
      agent: 'pi',
      id: m.id || f.name.replace(/^.*_/, '').replace(/\.jsonl$/, ''),
      title: m.title || '(untitled)',
      cwd: m.cwd,
      path: p,
      time: st.mtimeMs,
      preview: m.title || '',
    });
  }
}

// Walk directory entries without following symlinks; Codex nests rollouts by date.
const codexBase = path.join(process.env.CODEX_HOME || path.join(home, '.codex'), 'sessions');
const codexMessage = require('./codex').message;
const pendingCodexDirs = [codexBase];
while (pendingCodexDirs.length) {
  const dir = pendingCodexDirs.pop();
  for (const entry of readdir(dir)) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) { pendingCodexDirs.push(p); continue; }
    if (!entry.isFile() || !entry.name.endsWith('.jsonl')) continue;
    let id = '', cwd = '', title = '';
    for (const line of lines(p)) {
      let o; try { o = JSON.parse(line); } catch { continue; }
      if (!o || typeof o !== 'object') continue;
      if (o.type === 'session_meta' && o.payload && typeof o.payload.id === 'string') {
        id = o.payload.id;
        cwd = typeof o.payload.cwd === 'string' ? o.payload.cwd : '';
      }
      const msg = codexMessage(o);
      if (!title && msg && msg.role === 'user') title = clean(msg.text);
    }
    // The ID is passed to a shell resume command; accept only Codex UUIDs.
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) continue;
    const st = stat(p);
    if (st) out.push({ agent: 'codex', id, title: title || '(untitled)', cwd, path: p, time: st.mtimeMs, preview: title });
  }
}

const ompBase = path.join(home, '.omp', 'agent', 'sessions');
for (const proj of readdir(ompBase)) {
  if (!proj.isDirectory()) continue;
  const dir = path.join(ompBase, proj.name);
  for (const f of readdir(dir)) {
    if (!f.isFile() || !f.name.endsWith('.jsonl')) continue;
    const p = path.join(dir, f.name);
    const st = stat(p);
    if (!st) continue;
    const m = ompMeta(p);
    if (!m.id) continue;
    out.push({
      agent: 'omp',
      id: m.id,
      title: m.title || '(untitled)',
      cwd: m.cwd,
      path: p,
      time: st.mtimeMs,
      preview: m.title || '',
    });
  }
}

let sqlite = null;
try { sqlite = require('node:sqlite'); } catch {}
if (sqlite) {
  const seen = new Map();
  const roots = [
    path.join(home, '.gemini', 'antigravity'),
    path.join(home, '.gemini', 'antigravity-cli'),
  ];
  for (const root of roots) {
    const dbp = path.join(root, 'conversation_summaries.db');
    if (!fs.existsSync(dbp)) continue;
    let db, rows = [];
    try {
      db = new sqlite.DatabaseSync(dbp, { readOnly: true });
      rows = db.prepare('select conversation_id, title, preview, last_modified_time, workspace_uris, project_id from conversation_summaries').all();
    } catch { rows = []; }
    try { if (db) db.close(); } catch {}
    for (const r of rows) {
      const id = r.conversation_id;
      if (!id) continue;
      const brain = path.join(root, 'brain', id);
      const hasTranscript = fs.existsSync(path.join(brain, '.system_generated'));
      const prev = seen.get(id);
      if (prev && (prev.hasTranscript || !hasTranscript)) continue;
      let title = clean(r.title) || clean(r.preview);
      if (!title && hasTranscript) title = agyFirstUser(brain);
      let cwd = firstWorkspace(r.workspace_uris);
      if (!cwd) cwd = agyWorkspace.get(id) || '';
      seen.set(id, {
        agent: 'antigravity',
        id,
        title: title || (hasTranscript ? '(untitled)' : '(no transcript)'),
        preview: clean(r.preview),
        cwd,
        path: brain,
        time: parseTime(r.last_modified_time),
        project: r.project_id || '',
        hasTranscript,
      });
    }
  }
  for (const r of seen.values()) { delete r.hasTranscript; out.push(r); }
}

out.sort((a, b) => (b.time || 0) - (a.time || 0));
process.stdout.write(JSON.stringify(out));
