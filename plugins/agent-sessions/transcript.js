#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
function arg(name, def) {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
}

const agent = arg('agent', '');
const file = arg('path', '');
const out = [];
let role = null;
let buf = [];
let total = 0;

function flush() {
  if (!buf.length) return;
  out.push('### ' + role + '\n\n' + buf.join('\n\n') + '\n');
  buf = [];
}
function add(r, text) {
  let t = String(text || '').replace(/\r/g, '').trim();
  if (!t) return;
  if (t.length > 12000) t = t.slice(0, 12000) + '\n\n… (truncated)';
  if (r !== role) { flush(); role = r; }
  buf.push(t);
  total += t.length;
}
function lines(p) { try { return fs.readFileSync(p, 'utf8').split('\n'); } catch { return []; } }

function claude() {
  for (const line of lines(file)) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (o.isSidechain) continue;
    if (o.type === 'user' && o.message) {
      const c = o.message.content;
      if (typeof c === 'string') {
        const s = c.trim();
        if (s && !s.startsWith('<') && !/^(Caveat: The messages below|Name this chat from the user's first request)/i.test(s)) add('You', s);
      }
    } else if (o.type === 'assistant' && o.message) {
      const c = o.message.content;
      const t = typeof c === 'string' ? c : (Array.isArray(c) ? c.filter(x => x && x.type === 'text').map(x => x.text).join('\n\n') : '');
      add('Assistant', t);
    }
  }
}

function codex() {
  const message = require('./codex').message;
  for (const line of lines(file)) {
    let record; try { record = JSON.parse(line); } catch { continue; }
    const msg = message(record);
    if (msg) add(msg.role === 'user' ? 'You' : 'Assistant', msg.text);
  }
}

function pi() {
  for (const line of lines(file)) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (o.type !== 'message' || !o.message) continue;
    const r = o.message.role;
    if (r !== 'user' && r !== 'assistant') continue;
    const c = o.message.content;
    const t = typeof c === 'string' ? c : (Array.isArray(c) ? c.filter(x => x && x.type === 'text').map(x => x.text).join('\n\n') : '');
    add(r === 'user' ? 'You' : 'Assistant', t);
  }
}

function stripMeta(t) {
  return String(t || '')
    .replace(/<ADDITIONAL_METADATA>[\s\S]*?<\/ADDITIONAL_METADATA>/g, '')
    .replace(/<USER_SETTINGS_CHANGE>[\s\S]*?<\/USER_SETTINGS_CHANGE>/g, '')
    .replace(/<\/?USER_REQUEST>/g, '')
    .trim();
}

function agy() {
  let files = [];
  const single = path.join(file, '.system_generated', 'logs', 'transcript_full.jsonl');
  if (fs.existsSync(single)) {
    files = [single];
  } else {
    const dir = path.join(file, '.system_generated', 'logs', 'chunks', 'transcript_full');
    try {
      files = fs.readdirSync(dir).filter(f => f.endsWith('.jsonl')).sort().map(f => path.join(dir, f));
    } catch { files = []; }
  }
  for (const f of files) {
    for (const line of lines(f)) {
      if (!line) continue;
      let o; try { o = JSON.parse(line); } catch { continue; }
      if (o.type === 'USER_INPUT') add('You', stripMeta(o.content));
      else if (o.type === 'PLANNER_RESPONSE') add('Assistant', o.content || '');
    }
  }
}

try {
  if (agent === 'claude') claude();
  else if (agent === 'codex') codex();
  else if (agent === 'pi' || agent === 'omp') pi();
  else if (agent === 'antigravity') agy();
  flush();
  if (!out.length) out.push('_No messages found._');
  let text = out.join('\n\n');
  if (text.length > 400000) text = text.slice(0, 400000) + '\n\n… (transcript truncated)';
  process.stdout.write(text);
} catch (e) {
  process.stderr.write(String((e && e.stack) || e));
  process.exit(1);
}
