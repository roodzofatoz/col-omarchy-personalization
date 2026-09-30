# user.bluetooth — Bluetooth panel with hi-res codec control

Clone of the stock `omarchy.bluetooth` bar widget (kept in sync via
`omarchy.clonedFrom`) with one addition: control over the A2DP codec that
PipeWire uses for each connected Bluetooth audio device.

## What it adds

- **Codec chips** under every connected device that offers more than one
  codec (LDAC, aptX HD, aptX, AAC, SBC-XQ, SBC, …). Hi-res codecs carry a ✦.
  Click a chip to switch live; PipeWire re-negotiates the A2DP transport in
  about a second, the device stays connected.
- **LDAC quality chips** (Auto / HQ / SQ / MQ) when LDAC is active. HQ is the
  990/909 kbps mode, Auto is PipeWire's adaptive default.
- **Status line** shows the active codec next to the battery level, e.g.
  `LDAC HQ · 85%`.
- **Prefer hi-res on connect** (setting, default on): when a device connects,
  the widget switches it to the best hi-res codec it offers if PipeWire picked
  a lesser one, then applies the configured LDAC quality.
- Keyboard: with a connected row focused, `c` cycles the codec and `q` cycles
  the LDAC quality.

## Settings (`~/.config/omarchy/shell.json`, on the `user.bluetooth` entry)

| key               | default  | meaning                                                   |
|-------------------|----------|-----------------------------------------------------------|
| `preferHiRes`     | `true`   | auto-switch to the best hi-res codec when a device connects |
| `ldacQuality`     | `"auto"` | LDAC mode applied on connect: `auto`, `hq`, `sq`, `mq`     |
| `showCodecPicker` | `true`   | show the codec / quality chips under connected devices     |

## How it works

`bin/omarchy-bluetooth-codec` wraps PipeWire:

- codec list and switch: `pactl send-message /card/bluez_card.<ADDR>/bluez list-codecs | switch-codec '"<name>"'`
- LDAC quality: the sink node's `quality` prop, via `pw-cli set-param <node> Props '{ quality = N }'`
  (-1 auto, 0 hq, 1 sq, 2 mq)

Everything is live; nothing is written to WirePlumber config, so the
preference is re-applied by the widget on each connection.

Only codecs PipeWire has a plugin for show up (`/usr/lib/spa-0.2/bluez5/`).
On Arch, LDAC needs `libldac`, aptX/aptX HD need `libfreeaptx`, both present
on this machine. The device must advertise the codec too — SBC-only earbuds
get no chips.

## Tests

```
node bin/test_model.js
```

## Troubleshooting

- The helper logs every invocation (including the automatic `prefer` on
  connect) to `~/.local/state/omarchy-bluetooth-codec.log`.
- Only codecs the *device advertises on this connection* are listed. Some
  earbuds (the FIIO UTWS5 here) stop advertising their LDAC endpoint after a
  quick disconnect/reconnect; BlueZ then logs `load_remote_sep() Unable to
  load LastUsed`. Put the earbuds back in the case (full power cycle) and
  reconnect; the widget switches them to LDAC automatically once the
  endpoint is back.
- Edits to `Panel.qml` are picked up by the shell's plugin watcher but the
  compiled component stays cached, so run `omarchy restart shell` after
  changing QML. Edits to `bin/omarchy-bluetooth-codec` apply immediately.
