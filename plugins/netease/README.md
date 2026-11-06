# NetEase for Tern

Control the [NetEase Cloud Music](https://music.163.com/) (网易云音乐) desktop app from
[Tern](https://stencil.so/tern): cover art, the song and artist, play/pause, next and
previous, plus the app's own volume. No account, no login, no API token.

## Install

```sh
tern plugin install https://github.com/duzui300/tern-plugins
tern plugin link ~/src/tern-plugins/plugins/netease   # when developing
tern plugin reload
```

Then run **NetEase: Open player** from the palette. The block opens as a picture in
picture in the corner, like a small always-on-top player.

Windows only for now: the helper drives `cloudmusic.exe` through its global hotkeys and
the Windows audio mixer. macOS and Linux would need their own helper (see
[Limitations](#limitations)).

## Controls

With the player focused:

| Key | Action |
| --- | --- |
| `space`, `k` | Play / pause |
| `n`, `.` | Next track |
| `p`, `,` | Previous track |
| `+`, `-` | Volume ±5% |
| `m` | Mute |
| `o` | Open the NetEase window |

Every control is also a palette command under **NetEase**, so it can be bound to a key.

## How it works

The desktop client ships no local control API and does not publish a Windows media
session, so the plugin reads and drives it the way the app itself allows:

- **Now playing** — the title of the client's shell window (`OrpheusBrowserHost`) is
  `<song> - <artist>`; the helper reads it as the track.
- **Playing or paused** — the peak of the app's own audio streams in the Windows mixer.
  The client keeps its session alive while paused but goes silent, so the level tells them apart.
- **Transport** — the app's global hotkeys, `Ctrl+Alt+P` (play/pause), `Ctrl+Alt+Right`
  (next) and `Ctrl+Alt+Left` (previous). They must be enabled in the client's settings,
  which they are by default.
- **Volume and mute** — the app's own mixer session, so Tern changes NetEase's volume
  without touching the rest of the system.
- **Cover, album and length** — the public NetEase catalogue (`music.163.com` search and
  song detail) matched against the title and artist, cached for six hours.

The helper is a hidden PowerShell process; it stops on its own a minute after the last
Tern window closes.

## Limitations

- **No seek bar and no position.** The client exposes neither, and the hotkeys offer no
  seeking, so the player shows the track length instead of pretending to know where it is.
- **Volume needs audio.** The mixer session exists only after the app has played
  something; before that the volume controls say so.
- **A few seconds of silence can read as paused.** The state follows the audio level, so a
  gap longer than 2.5 seconds in a track shows the player as paused until sound returns.
- **Song matching is textual.** Remixes, covers and local files may show no cover or the
  wrong album; the title and artist are always the client's own.
- **Windows only.** A macOS helper would need AppleScript (which NetEase does not expose)
  or a screen reader; on Linux the client's MPRIS interface would be the way in.
- The title splits at the first ` - `, so a song whose own title contains ` - ` shows the
  rest as the artist.

## Development

```sh
tern plugin link plugins/netease
tern plugin reload
tern plugin list      # shows "netease … ready"
```

The helper writes `state.txt`, `helper.log` and its command queue into the plugin's data
directory (`%LOCALAPPDATA%\Tern\plugins\netease` on Windows). Delete that folder to reset.
