.pragma library

var GPU_ICON = "\u{F08AE}"        // nf-md-expansion_card
var REFRESH_ICON = "\u{F0450}"    // nf-md-refresh
var UPDATE_ICON = "\u{F01DA}"     // nf-md-download
var RESTART_ICON = "\u{F0709}"    // nf-md-restart
var CHECK_ICON = "\u{F012C}"      // nf-md-check
var ALERT_ICON = "\u{F0026}"      // nf-md-alert
var ARROW_ICON = "\u{F0054}"      // nf-md-arrow_right
var WEB_ICON = "\u{F059F}"        // nf-md-web

function ago(iso, nowMs) {
  if (!iso) return "never"
  var t = Date.parse(iso)
  if (isNaN(t)) return ""
  var s = Math.max(0, Math.floor((nowMs - t) / 1000))
  if (s < 60) return "just now"
  var m = Math.floor(s / 60)
  if (m < 60) return m + " min ago"
  var h = Math.floor(m / 60)
  if (h < 24) return h + " h ago"
  return Math.floor(h / 24) + " d ago"
}

// "ok" | "updates" | "reboot" | "error" | "checking" | "unknown"
function state(engine) {
  if (!engine) return "unknown"
  if (engine.checking && !engine.report) return "checking"
  if (engine.lastError && !engine.report) return "error"
  if (!engine.report) return "unknown"
  if (engine.report.rebootNeeded) return "reboot"
  if (engine.report.updates && engine.report.updates.length) return "updates"
  return "ok"
}

function headline(engine) {
  var s = state(engine)
  if (s === "checking") return "Checking…"
  if (s === "error") return "Check failed"
  if (s === "unknown") return "Not checked yet"
  if (s === "reboot") return "Reboot needed"
  if (s === "updates") {
    var n = engine.report.updates.length
    return n + (n === 1 ? " driver update" : " driver updates")
  }
  return "Drivers up to date"
}

function driverLabel(gpu, report) {
  if (!gpu) return ""
  var drv = gpu.driver || "no driver bound"
  if (gpu.vendor === "nvidia" && report && report.running && report.running.nvidia) return drv + " " + report.running.nvidia
  if ((gpu.vendor === "amd" || gpu.vendor === "intel") && report && report.running && report.running.mesa) return drv + " · mesa " + report.running.mesa
  return drv
}

// Installed packages worth showing first, in a stable order.
var PRIORITY = ["nvidia-utils", "nvidia-open-dkms", "nvidia-dkms", "nvidia", "nvidia-open", "lib32-nvidia-utils",
  "mesa", "lib32-mesa", "vulkan-radeon", "vulkan-intel", "amdvlk", "linux", "linux-headers", "linux-lts", "linux-zen",
  "linux-firmware", "linux-firmware-nvidia", "linux-firmware-amdgpu", "libva-nvidia-driver", "egl-wayland", "vulkan-icd-loader"]

function installedRows(report, updates) {
  if (!report || !report.installed) return []
  var pending = {}
  for (var i = 0; i < (updates || []).length; i++) pending[updates[i].name] = updates[i]
  var names = Object.keys(report.installed)
  names.sort(function(a, b) {
    var pa = PRIORITY.indexOf(a), pb = PRIORITY.indexOf(b)
    if (pa < 0) pa = 99; if (pb < 0) pb = 99
    return pa !== pb ? pa - pb : (a < b ? -1 : a > b ? 1 : 0)
  })
  var rows = []
  for (var j = 0; j < names.length; j++) {
    var n = names[j]
    if (/^linux-firmware-(atheros|broadcom|cirrus|mediatek|other|realtek|whence|intel|radeon)$/.test(n)) continue
    rows.push({ name: n, version: report.installed[n], update: pending[n] || null })
  }
  return rows
}
