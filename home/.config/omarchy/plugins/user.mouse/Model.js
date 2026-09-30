// Pure helpers for the mouse widget. Kept out of Panel.qml so the display
// rules stay testable by eye and the QML is only layout and wiring.

// Same glyph sets the first-party power widget uses, so a mouse battery and a
// laptop battery read identically in the same bar.
var CHARGING_ICONS = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
var LEVEL_ICONS = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]

var MOUSE_ICON = "󰍽"

// Brand logos shipped in logos/<key>.svg (simple-icons, CC0). Anything not
// listed keeps the battery glyph in the hero.
var BRAND_LOGOS = { razer: "Razer", steelseries: "SteelSeries", corsair: "Corsair" }

// "Razer Viper V3 Pro" / vendor "Razer USA, Ltd" -> "razer"
function brandKey(info) {
  if (!info) return ""
  var src = (info.vendor || info.name || "").trim()
  if (!src) return ""
  var first = src.split(/[\s,]+/)[0].toLowerCase().replace(/[^a-z0-9]/g, "")
  if (BRAND_LOGOS[first]) return first
  var lower = src.toLowerCase()
  for (var key in BRAND_LOGOS) if (lower.indexOf(key) !== -1) return key
  return ""
}

function brandName(info) {
  var key = brandKey(info)
  return key ? BRAND_LOGOS[key] : ""
}

// Below this the battery reading is painted with the theme's urgent colour.
var LOW = 20

function clampPercent(value) {
  if (typeof value !== "number" || !isFinite(value)) return null
  return Math.max(0, Math.min(100, Math.round(value)))
}

function parseStatus(text) {
  if (!text) return null
  try {
    var parsed = JSON.parse(text)
    return (parsed && typeof parsed === "object") ? parsed : null
  } catch (error) {
    return null
  }
}

function batteryIcon(percent, charging) {
  var level = clampPercent(percent)
  if (level === null) return MOUSE_ICON
  // floor(1.0 * 10) would land on index 10, so a full battery is clamped back
  // onto the last icon rather than falling off the end of the array.
  var index = Math.max(0, Math.min(9, Math.floor(level / 10)))
  return charging ? CHARGING_ICONS[index] : LEVEL_ICONS[index]
}

function isLow(percent, charging) {
  var level = clampPercent(percent)
  return level !== null && !charging && level <= LOW
}

function batteryFraction(percent) {
  var level = clampPercent(percent)
  return level === null ? 0 : level / 100
}

// The one-line summary under the device name in the popup hero.
function statusLine(status) {
  if (!status || status.present !== true) return "Not connected"
  if (status.online !== true) return "Asleep"
  if (status.charging === true) return "Charging"
  var level = clampPercent(status.battery)
  if (level === null) return "Connected"
  if (level <= LOW) return "Battery low"
  return "On battery"
}

function batteryLabel(status) {
  var level = status ? clampPercent(status.battery) : null
  return level === null ? "—" : level + "%"
}

function dpiLabel(status) {
  if (!status || typeof status.dpi !== "number") return "—"
  // X and Y are almost always locked together; only spell both out when the
  // mouse is actually configured with independent axes.
  if (typeof status.dpiY === "number" && status.dpiY !== status.dpi) {
    return status.dpi + " × " + status.dpiY
  }
  return String(status.dpi)
}

function stageLabel(status) {
  if (!status || typeof status.dpiStage !== "number") return ""
  var total = (status.dpiStages && status.dpiStages.length) || 0
  if (!total) return ""
  return "Stage " + status.dpiStage + " of " + total
}

function pollingLabel(status) {
  if (!status || typeof status.pollingRate !== "number") return "—"
  return status.pollingRate + " Hz"
}

function firmwareLabel(status) {
  return (status && status.firmware) ? "v" + status.firmware : "—"
}

function accelDescription(enabled) {
  return enabled
    ? "Adaptive curve — pointer speed scales with how fast you move"
    : "Flat profile — raw 1:1 movement, no acceleration curve"
}
