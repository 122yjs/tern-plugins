'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = __dirname;
const id = '01900000-1234-7000-8000-123456789abc';
function withHome(fn) {
  const home = fs.mkdtempSync(path.join(root, '.test-home-'));
  try { fn(home); } finally { fs.rmSync(home, { recursive: true, force: true }); }
}
function writeRollout(base, relative, records) {
  const file = path.join(base, 'sessions', relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, records.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join('\n') + '\n');
  return file;
}
function run(script, args, home, codexHome) {
  return execFileSync(process.execPath, [path.join(root, script), ...args], {
    encoding: 'utf8', env: { ...process.env, HOME: home, USERPROFILE: home, CODEX_HOME: codexHome || path.join(home, '.codex') },
  });
}

test('discovers a nested Codex rollout using metadata and first user message', () => withHome(home => {
  const codexHome = path.join(home, 'custom-codex');
  const file = writeRollout(codexHome, '2025/07/03/rollout-fixture.jsonl', [
    { timestamp: '2025-07-03T12:00:00Z', type: 'session_meta', payload: { id, cwd: '/project' } },
    { timestamp: '2025-07-03T12:01:00Z', type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'Build a feature' }] } },
  ]);
  const rows = JSON.parse(run('scan.js', [], home, codexHome));
  assert.equal(rows.length, 1);
  assert.deepEqual({ agent: rows[0].agent, id: rows[0].id, cwd: rows[0].cwd, title: rows[0].title, path: rows[0].path },
    { agent: 'codex', id, cwd: '/project', title: 'Build a feature', path: file });
}));


test('renders conversational text while excluding tools, context, and malformed records', () => withHome(home => {
  const file = writeRollout(path.join(home, '.codex'), '2025/07/04/rollout.jsonl', [
    { type: 'session_meta', payload: { id, cwd: '/project' } },
    'not json', 'null',
    { type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text: '<environment_context>private context</environment_context>' }] } },
    { type: 'response_item', payload: { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'Hello' }, { type: 'input_image', image_url: 'hidden' }] } },
    { type: 'response_item', payload: { type: 'function_call', name: 'shell', arguments: 'SECRET TOOL' } },
    { type: 'event_msg', payload: { type: 'agent_message', message: 'duplicate' } },
    { type: 'response_item', payload: { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Hi there' }] } },
  ]);
  const text = run('transcript.js', ['--agent', 'codex', '--path', file], home);
  assert.match(text, /### You\n\nHello/);
  assert.match(text, /### Assistant\n\nHi there/);
  assert.doesNotMatch(text, /private context|hidden|SECRET TOOL|duplicate/);
  const rows = JSON.parse(run('scan.js', [], home));
  assert.equal(rows[0].title, 'Hello');
}));


test('walks all nested files, sorts by mtime, and skips invalid metadata', () => withHome(home => {
  const base = path.join(home, '.codex');
  for (let i = 0; i < 105; i++) {
    const sessionId = `01900000-1234-7000-8000-${String(i).padStart(12, '0')}`;
    const file = writeRollout(base, `2025/07/${String(i % 28 + 1).padStart(2, '0')}/rollout-${i}.jsonl`, [
      'null', '{broken', { type: 'session_meta', payload: { id: sessionId } },
    ]);
    fs.utimesSync(file, 1000000 + i, 1000000 + i);
  }
  writeRollout(base, 'bad.jsonl', ['null', '{broken', { type: 'session_meta', payload: { id: 'id;danger' } }]);
  const rows = JSON.parse(run('scan.js', [], home));
  assert.equal(rows.length, 105);
  assert.equal(rows[0].id, '01900000-1234-7000-8000-000000000104');
  assert.equal(rows[104].id, '01900000-1234-7000-8000-000000000000');
  assert.equal(rows[0].title, '(untitled)');
  assert.equal(rows[0].time, 1000104 * 1000);
}));

test('Codex delete helper refuses deletion', () => withHome(home => {
  const file = writeRollout(path.join(home, '.codex'), 'rollout.jsonl', [{ type: 'session_meta', payload: { id } }]);
  const result = JSON.parse(run('delete.js', ['--agent', 'codex', '--id', id, '--path', file], home));
  assert.equal(result.ok, false);
  assert.equal(fs.existsSync(file), true);
}));

test('empty or missing Codex session store returns no rows', () => withHome(home => {
  assert.deepEqual(JSON.parse(run('scan.js', [], home)), []);
}));
