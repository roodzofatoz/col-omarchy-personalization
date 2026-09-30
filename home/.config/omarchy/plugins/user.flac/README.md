# user.flac — bit-perfect, gapless FLAC player for the Omarchy bar

A bar widget (right section, next to Audio) whose popup shows now-playing,
transport, an **Exclusive mode** switch and your album library. Playback is
done by a single `mpv` process the plugin owns; the widget only renders state.

```
manifest.json     kinds ["service","bar-widget"]
Engine.qml        the service: launches/attaches mpv, JSON IPC, device hand-off, library
Player.qml        the bar button + KeyboardPanel (one per monitor)
Model.js          formatting, library flattening, bit-perfect rule
bin/omarchy-flac-device   release | restore | status  (PipeWire ↔ mpv hand-off, hw_params probe)
bin/omarchy-flac-scan     recursive .flac indexer (pure python, cached in ~/.cache/omarchy-flac/)
```

## Using it

- **Bar icon**: left = open/close panel, middle = play/pause, right = next, scroll = prev/next.
- **Panel keys**: `↑/↓` or `j/k` move, `Enter` on a track plays it (its whole album is queued so
  gapless spans the album) / on an album opens or closes its track list / on a genre or artist
  header plays the group, `a` play the highlighted album or group, `S` shuffle the highlighted
  album/group (or everything shown when on a track / nothing highlighted), `Space` play/pause,
  `←/→` seek ±5 s, `/` jump to search (`Esc` clears and returns, `↓`/`Enter` returns to the list),
  `g` cycle grouping, `o` toggle group order (A→Z / most tracks first), `e` toggle exclusive, `r` rescan, `n`/`p` next/previous, `s` stop (pause + rewind; the playlist is kept),
  `Esc` close, `Tab` next panel.
- **Tabs**: **Playlist** (`1`) is the queue mpv is playing — Enter plays a row, `x` removes it,
  header buttons shuffle or clear the queue (clearing stops playback and releases the DAC).
  **Library** (`2`) browses albums: search matches title, artist, album, album artist, genre and
  year (all words must match; a search expands everything). Group by **Album**, **Genre** or
  **Artist**; in Genre/Artist view only the group names are listed — Enter/click opens one to show
  its albums. Albums are collapsed by default with a cover thumbnail and three actions —
  **+** add to the playlist (`+` key), ▶ play now, 🔀 shuffle — and the header 🔀 shuffles all
  songs (or all matches while searching). Adding to an empty playlist starts playback. The
  folder button opens a directory chooser (zenity) — the pick is saved to `shell.json` as
  `libraryDir` and rescanned immediately. Albums and groups expand/collapse in place with a short
  slide. If the library drive is not mounted, the panel says so and the cached index is kept.
- **Up next**: the small ♪ button in the panel's top-right corner — hover it to preview the
  following queue entry, click it to skip there.
- **Album art** comes from a `cover/folder/front.*` image next to the tracks or the FLAC's own
  embedded picture, extracted once into `~/.cache/omarchy-flac/art/`.
- **Media keys** work through MPRIS (`mpv-mpris` is loaded into the engine); note that
  `omarchy.media` prefers players that have a PipeWire stream, so while another PipeWire app is
  *playing*, it may win the keys in exclusive mode.
- **CLI**: `omarchy-shell shell toggle user.flac` (panel),
  `omarchy-shell user.flac playPause|next|prev|stop|status|rescan|toggleExclusive`,
  `omarchy-shell user.flac setExclusive true|false`, `omarchy-shell user.flac playAlbum <album> <track>`,
  `omarchy-shell user.flac shuffleAll`, `omarchy-shell user.flac shuffleAlbum <album>`,
  `omarchy-shell user.flac enqueueAlbum <album>`, `clearQueue`, `shuffleQueue`, `toggleShuffle`,
  `queue` (paths as JSON), `selectLibrary`, `setLibraryDir <path>`.
- **Volume** is deliberately not in software: in exclusive mode the samples reach the DAC
  untouched, so use the DAC's own volume control.

## Settings (inline on the `user.flac` entry in `~/.config/omarchy/shell.json`)

| key | default | meaning |
|---|---|---|
| `libraryDir` | `/run/media/user/Downloads & Media/Music` | scanned recursively for `.flac` |
| `exclusive` | `false` | direct ALSA output (bit-perfect) vs shared PipeWire output (default) |
| `alsaDevice` | `alsa/hw:CARD=II,DEV=0` | mpv `--audio-device` in exclusive mode (must be `hw:`) |
| `pwDeviceName` | `alsa_card.usb-Topping_E50_II-00` | PipeWire `device.name` to release in exclusive mode |
| `pwSinkName` | `""` | PipeWire sink for shared mode (empty = default sink) |
| `showTitleInBar` | `false` | show `title — artist` in the bar instead of the glyph |

Turning the Exclusive switch on (or pressing `e`) first asks which hardware output to use — every
ALSA playback device on the machine is listed with the PipeWire device it maps to; pick one with a
click or ↑↓ + Enter (Esc cancels). The pick is written to `shell.json` as `alsaDevice` /
`pwDeviceName` together with `exclusive: true`, so the choice persists; turning it off is immediate. Find names for another DAC with `mpv --audio-device=help` and `pw-dump | grep device.name`.

## How bit-perfect is achieved

- mpv runs with `--af=`, `--volume=100 --volume-max=100 --volume-gain=0`, `--replaygain=no`,
  `--audio-pitch-correction=no`, native sample rate/format (`--audio-samplerate=0`), and
  `--gapless-audio=weak`. (`yes` would keep the first file's rate and *resample* later tracks;
  `weak` keeps the device open across same-format tracks and re-opens on a format change.)
- **Exclusive mode**: `--ao=alsa --audio-device=alsa/hw:… --alsa-resample=no`. PipeWire keeps the
  card open, so before the first track `omarchy-flac-device release` switches the card's
  PipeWire profile to *off* (saving the profile index and the default sink), waits for the PCM
  to close, and mpv opens `hw:` directly; the DAC then follows each file's rate. On stop / queue
  end / mpv exit / a stale release found at startup, `restore` puts the profile and default
  sink back. While released, other apps fall back to the next sink.
- **Shared mode**: `--ao=pipewire`. Samples go through the PipeWire graph at the graph rate
  (48 kHz on this machine), so 44.1 kHz material is resampled — the badge says so. To make shared
  mode rate-following too, create `~/.config/pipewire/pipewire.conf.d/10-flac-rates.conf`:

  ```
  context.properties = {
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 352800 384000 ]
  }
  ```

  and `systemctl --user restart pipewire pipewire-pulse wireplumber`.
- The badge in the panel is measured, not assumed: `omarchy-flac-device status` reads
  `/proc/asound/<card>/pcm0p/sub0/{status,hw_params}` and reports who owns the PCM and at which
  rate/format. "Bit-perfect" = mpv owns it, rate equals the file's, and the container is at least
  as wide as the source (a 16/24-bit stream in the E50's 32-bit slot is zero-padded — lossless).

## Behaviour worth knowing

- mpv runs as a transient systemd user unit (`omarchy-flac-mpv.service`) and is re-attached
  through `$XDG_RUNTIME_DIR/omarchy-flac.sock`, so `omarchy restart shell` and plugin hot-reloads
  do not interrupt playback or lose the queue. `systemctl --user stop omarchy-flac-mpv` kills it.
- Switching exclusive mode mid-track restarts mpv with the other output and resumes at the same
  position with the same queue.
- Editing this plugin's QML: the shell's hot-reload can serve a cached copy of a changed
  component; if a change does not apply, run `omarchy restart shell`.

## Reverting

`omarchy plugin disable user.flac` (or remove the `user.flac` entry from `bar.layout.right`
in `shell.json`), `systemctl --user stop omarchy-flac-mpv`, and if a release was left behind
`~/.config/omarchy/plugins/user.flac/bin/omarchy-flac-device restore`. Delete the directory
and `~/.cache/omarchy-flac/` to remove everything.
