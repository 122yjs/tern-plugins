# AGENTS.md

Repository conventions for coding agents.

## Scope

`plugins/<id>/` is one Tern plugin. `plugin.toml` and the Luau entry define it; helper scripts sit beside them. There is no build step and no package manager.

## Rules

- Documentation and comments in English.
- Read Tern's plugin SDK before changing a view: the installed SDK writes `tern.d.luau` via `tern plugin types .`, and the book is at <https://docs.stencil.so/tern/>.
- Never commit secrets, tokens, session files, `*.db` sidecars or absolute paths from a developer machine.
- Keep window-half handlers inside the 50 ms budget. Move file and SQLite work into a `node` helper started with `tern.process.run`.
- The plugin reads the agents' data stores. Treat them as read-only unless the task is explicitly a delete feature, and confirm destructive actions twice.
- Use `tern plugin link plugins/<id>` and `tern plugin reload` to test. Watch for `plugin window entry failed to load` in Tern's log after syntax errors.
- Run `node --check` on changed JavaScript helpers before finishing.

## Pull requests

Keep one plugin per change when possible, update that plugin's README and screenshots, and bump its `plugin.toml` version for behavior changes.
