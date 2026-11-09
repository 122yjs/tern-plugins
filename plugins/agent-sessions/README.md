# Agent Sessions

A Tern canvas that turns the agent histories already on your machine into one searchable, resumable list.

<p align="center">
  <img src="docs/session-manager.png" alt="Agent Sessions list" height="460" />
  &nbsp;&nbsp;
  <img src="docs/session-detail.png" alt="Session detail" height="460" />
</p>

Claude Code, Codex, Antigravity, Pi and omp each keep conversations in their own format and directory. Finding the one you want means remembering which tool, which project and which UUID. This plugin reads those stores, groups the sessions by agent, folder or tag, and resumes one with a click.

## Features

- Five adapters: Claude Code, Codex, Antigravity (IDE and CLI), Pi and omp.
- Group by agent, folder or tag; filter by folder or tag; search titles, paths and tags.
- Collapsible groups, collapsed by default, with expand-all/collapse-all.
- Resume in a new Tern tab with the agent's own command, or copy the command.
- Aliases and tags live in the plugin's own SQLite database. Session files are never written.
- Hide noisy sessions, or delete a session from disk behind a two-step confirmation.
- Responsive layout: rows wrap and the action column stays aligned when the pane narrows.

## Where sessions come from

| Agent | Session files | Resume command |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/<project>/<id>.jsonl` | `claude --resume <id>` |
| Codex | `${CODEX_HOME:-~/.codex}/sessions/<year>/<month>/<day>/rollout-*.jsonl` (recursively scanned) | `codex resume <id>` |
| Antigravity | `~/.gemini/antigravity{,-cli}/conversation_summaries.db`, plus `brain/<id>/.system_generated/logs/transcript_full.jsonl` (IDE transcripts are chunked under `chunks/transcript_full/`) | `agy --conversation <id>` |
| Pi | `~/.pi/agent/sessions/<project>/<time>_<id>.jsonl` | `pi --session <id>` |
| omp | `~/.omp/agent/sessions/<project>/<time>_<id>.jsonl` | `omp --resume <id>` |

Scanning and transcript rendering never write to session files. Antigravity data is opened read-only through `node:sqlite` during scanning.

## Install

```sh
tern plugin install github.com/duzui300/tern-plugins/plugins/agent-sessions
```

Or from a checkout:

```sh
tern plugin link plugins/agent-sessions
tern plugin reload
```

Requires Tern 0.9+ and Node.js 22+ (for the built-in `node:sqlite` module).

## Use

Run **Agent sessions** from the palette (`plugin.agent-sessions.open`).

- **Toolbar**: filter by folder or tag, search, switch grouping (agent, folder, tag), expand/collapse all, show hidden sessions, rescan.
- **Groups**: collapsed by default. Click a group header to expand or collapse it; the badge counts its sessions.
- **Rows**: click a title to read the transcript. The icon buttons resume, copy the resume command, rename, edit tags, or hide/delete.
- **Detail**: Back, Resume, Copy, Rename, Tags; the transcript renders as Markdown.

### Aliases and tags

Stored in `<Tern state>/plugin-data/agent-sessions/tags.db`, keyed by `agent` and session id. They never touch the session files and do not appear in the agents' own pickers.

- **Rename** changes the display name only.
- **Tags** edits a comma-separated list; tags show as badges in the list and can be used as the grouping key or a filter.

### Hide and delete

- **Hide from this list** keeps the files. The eye button shows hidden sessions again, where they can be restored.
- **Delete from disk...** asks once more, then removes the agent's files for that session: the JSONL and its companion directory for Claude/omp, the JSONL for Pi, or the conversation database, brain folder and summary rows for Antigravity. This cannot be undone, and the agent must not be using the session.
- Codex sessions can be hidden but cannot be deleted from disk through this plugin.

## How it works

The plugin is a window-half Tern plugin. `window.luau` draws a `tern.canvas` panel and handles actions; file and SQLite work runs in small Node helpers through `tern.process.run`:

- `scan.js` walks the five stores and prints a JSON array of `{agent, id, title, cwd, path, time}`.
- `transcript.js` renders one session to Markdown (`--agent`, `--path`, `--id`).
- `tags.js` manages the SQLite sidecar for aliases, tags and hidden sessions (`get`, `set`, `hidden`, `hide`, `unhide`).
- `delete.js` removes one session's files after confirmation.

To develop, link the directory and reload:

```sh
tern plugin link plugins/agent-sessions
tern plugin reload
```

Run fixture-based tests from the repository root with `node --test plugins/agent-sessions/codex.test.js`.

Editing `window.luau` needs a reload; the Node helpers are read on the next scan or action.

## Limitations

- Session formats are the agents' own, not public APIs. A format change can break an adapter. Parsers tolerate missing fields and skip unreadable files.
- Codex scans active rollouts only, not archived sessions; titles come from the first user message and ordering uses file modification time. Tool calls and non-text content are not shown.
- Antigravity conversations without a transcript show their summary title and no messages.
- If `agents.auto_acp` intercepts `claude` or `agy`, `--resume` may not pass through. Add the id to `agents.keep_tui`, or use Copy, to resume in the native interface.
- omp companion files without `.jsonl` are not listed; some are access-restricted while omp is running.

## License

MIT. See the repository [LICENSE](../../LICENSE).
