#!/usr/bin/env node
'use strict';
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const data = process.env.TERN_PLUGIN_DATA || process.cwd();
const db = new DatabaseSync(path.join(data, 'tags.db'));
db.exec('create table if not exists tags (agent text not null, id text not null, alias text, tags text, primary key (agent, id))');
db.exec('create table if not exists hidden (agent text not null, id text not null, primary key (agent, id))');

const [cmd, agent, id, alias, tags] = process.argv.slice(2);

if (cmd === 'get') {
  const o = {};
  for (const r of db.prepare('select agent, id, alias, tags from tags').all()) {
    let t = [];
    try { t = JSON.parse(r.tags || '[]'); } catch {}
    o[r.agent + ':' + r.id] = { alias: r.alias || '', tags: t };
  }
  process.stdout.write(JSON.stringify(o));
} else if (cmd === 'set') {
  if (String(alias || '').trim() === '' && (!tags || tags === '[]')) {
    db.prepare('delete from tags where agent = ? and id = ?').run(agent, id);
  } else {
    db.prepare('insert into tags (agent, id, alias, tags) values (?, ?, ?, ?) on conflict(agent, id) do update set alias = excluded.alias, tags = excluded.tags')
      .run(agent, id, alias || '', tags || '[]');
  }
  process.stdout.write('ok');
} else if (cmd === 'hidden') {
  const list = db.prepare('select agent, id from hidden').all().map(r => r.agent + ':' + r.id);
  process.stdout.write(JSON.stringify(list));
} else if (cmd === 'hide') {
  db.prepare('insert or ignore into hidden (agent, id) values (?, ?)').run(agent, id);
  process.stdout.write('ok');
} else if (cmd === 'unhide') {
  db.prepare('delete from hidden where agent = ? and id = ?').run(agent, id);
  process.stdout.write('ok');
} else {
  process.stderr.write('usage:  tags.js get | set <agent> <id> <alias> <tags-json>');
  process.exit(2);
}
