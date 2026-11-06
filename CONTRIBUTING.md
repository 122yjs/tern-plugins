# Contributing

## Adding a plugin

1. Create a directory under `plugins/` named after the plugin id (lowercase letters, digits and hyphens).
2. Add `plugin.toml` with `schema = 1`, a unique `id`, a name, a version and the entry files.
3. Keep the plugin self-contained: its Luau entry, helper scripts, README and screenshots live in that directory.
4. Write the plugin README in English. Say what it does, where its data comes from, how to install it, how to use it, and what its limitations are.
5. Put screenshots in `docs/` and reference them from the README.
6. Link it and verify before committing:

```sh
tern plugin link plugins/<id>
tern plugin reload
tern plugin list
```

Open the palette command the plugin registers and exercise its main paths. For plugins with helper scripts, run `node --check` on every `.js` file.

## Conventions

- One plugin per directory. Shared code is copied, not imported, unless a real library is warranted.
- Docs, comments and commit messages are in English.
- Never commit credentials, session data, plugin databases (`*.db`), logs or machine-specific paths. Use the environment and `tern.plugin.data`.
- If the plugin writes files, keep them under `tern.plugin.data` or the user's project; never rewrite another tool's session files unless the feature explicitly asks for it and confirms first.
- Keep helper processes small and bounded; window-half handlers have a 50 ms budget.

## Release checks

- `plugin.toml` version is bumped for behavior changes.
- `README.md` matches the current commands and screenshots.
- `tern plugin reload` reports no problems and `tern plugin list` shows the plugin as ready.
- No file in the diff contains a token, email or absolute path of a contributor's machine.

## License

By contributing you agree that your work is licensed under the repository's MIT license.
