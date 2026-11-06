# Tern Plugins

A small collection of plugins for [Tern](https://stencil.so/tern), Stencil's Rust-native neoterminal. Each plugin lives in its own directory under `plugins/`, with its own README, installation notes and screenshots.

## Plugins

| Plugin | What it does | Status |
| --- | --- | --- |
| [Agent Sessions](plugins/agent-sessions/README.md) | Browse local Claude Code, Antigravity, Pi and omp session histories in a native canvas, resume them in one click, and tag them without touching the session files. | Available |
| [NetEase](plugins/netease/README.md) | Now playing, cover art, play/pause, next and previous, and the app's own volume for the NetEase Cloud Music desktop client. No login. | Available (Windows) |

## Install

From GitHub:

```sh
tern plugin install github.com/duzui300/tern-plugins/plugins/agent-sessions
```

From a local checkout:

```sh
tern plugin link plugins/agent-sessions
tern plugin reload
```

`tern plugin install` copies the folder into Tern's plugin directory. `tern plugin link` keeps a checkout live for development. Run `tern plugin reload` after changes.

## Repository layout

```
plugins/
  agent-sessions/     one self-contained plugin per directory
    plugin.toml
    window.luau
    scan.js
    transcript.js
    tags.js
    delete.js
    README.md
    docs/
```

Every plugin directory holds its manifest, Luau entry, helper scripts and documentation. Helper scripts are plain Node.js files beside the entry: no build step and no package manager.

## Development

- [CONTRIBUTING.md](CONTRIBUTING.md): adding a plugin, local linking and release checks.
- [AGENTS.md](AGENTS.md): conventions for coding agents working in this repository.
- Tern's plugin SDK ships with Tern (`tern plugin types DIR` writes `tern.d.luau`), and the SDK book is at <https://docs.stencil.so/tern/>.

## License

MIT. See [LICENSE](LICENSE).
