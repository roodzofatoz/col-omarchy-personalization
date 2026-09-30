# user.gpu — GPU driver update check for the Omarchy bar

An indicator in the hover-revealed indicator block (next to night light / DND):
hidden while everything is current, shown on its own — with a theme-accent dot —
while a GPU driver update is pending or an update is running, and urgent
(red dot, "Reboot needed") when the loaded driver/kernel no longer matches what
is installed.

```
manifest.json           kinds ["service","bar-widget"]
Engine.qml              runs the check on a schedule, keeps the report, IPC target user.gpu
Widget.qml              invisible placeholder — keeps the service loaded, forwards settings
Model.js                glyphs, state → headline, row ordering
bin/omarchy-gpu-updates check [--no-upstream]   the checker (JSON)
../user.indicators/indicators/Gpu.qml           the indicator + panel (lives in the cloned indicator block)
```

The indicator block is the `user.indicators` clone of `omarchy.indicators`
(made with `omarchy plugin clone omarchy.indicators`); "Gpu" is in its default
list and in its manifest options. The `user.gpu` entry in `shell.json` must stay
in the layout: a plugin's service only runs while it has an entry, so the
placeholder widget is zero-sized rather than removed.

## What it checks

- **GPU + driver in use** — `lspci` and the kernel driver bound in `/sys/class/drm`.
- **Loaded vs installed** — `/sys/module/nvidia/version` against `nvidia-utils`, and the
  running kernel against the `linux*` package. A mismatch means "Reboot needed".
- **Pending updates** — `checkupdates` (repo, no root) and `yay -Qua` (AUR), filtered to
  driver packages: `nvidia*`, `lib32-nvidia*`, `mesa`, `lib32-mesa`, `vulkan-*`, `amdvlk`,
  `xf86-video-*`, `linux-firmware*`, `linux*`/headers, `dkms`, `egl-*`, `libva-*driver`,
  `cuda*`, `rocm-*`, `opencl-*`.
- **Upstream** — NVIDIA's current production branch from `download.nvidia.com` (informational;
  Arch's package can be ahead of it, as it is with a feature branch).

## Using it

- **Indicator**: hover the indicator area to reveal it while current; it stays
  visible on its own while updates are pending / an update is running / a reboot
  is needed. Left click opens the panel, right click re-checks. Dot under the
  icon = update available (theme accent, pulsing while updating) or reboot
  needed (urgent).
- **Panel**: GPU / driver / status hero, pending updates with old → new versions (↻ marks
  ones that need a reboot), **Update** (runs `omarchy update` in a floating terminal — the
  whole system, since partial upgrades are unsupported on Arch), **Reboot** when needed,
  installed driver packages, and the kernel/upstream footer.
- **Keys**: `r` check, `u` update, `n` release notes, `Enter` update when updates are pending,
  `Esc` close, `Tab` next panel.
- **CLI**: `omarchy-shell user.gpu check|status|update`,
  `omarchy-shell user.gpu setReport '<json>'` / `setUpdating true|false` (debug: preview the
  pending/updating UI until the next check), or
  `~/.config/omarchy/plugins/user.gpu/bin/omarchy-gpu-updates check`.

## Settings (inline on the `user.gpu` entry in `~/.config/omarchy/shell.json`)

| key | default | meaning |
|---|---|---|
| `checkHours` | `6` | re-check interval |
| `checkUpstream` | `true` | look up NVIDIA's latest on nvidia.com |
| `hideWhenCurrent` | `false` | hide the icon while everything is current |
