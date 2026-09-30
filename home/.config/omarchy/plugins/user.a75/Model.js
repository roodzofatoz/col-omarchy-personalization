.pragma library

var KEYBOARD_ICON = "\u{F030C}"   // nf-md-keyboard
var REFRESH_ICON = "\u{F0450}"    // nf-md-refresh
var FIRMWARE_ICON = "\u{F01DA}"   // nf-md-download

var PRESET_LABELS = { comfort: "Comfort", sensitive: "Sensitive", gaming: "Gaming", custom: "Custom" }

function presetLabel(name) {
  return PRESET_LABELS[name] || "—"
}

// raw 0.1 mm integer → "1.5 mm"
function mm(raw) {
  if (raw === null || raw === undefined) return "—"
  return (Number(raw) / 10).toFixed(1) + " mm"
}

function statusLine(status) {
  if (!status) return "not checked yet"
  if (status.permissionError) return "no permission — install the udev rule"
  if (!status.present) return "not connected"
  var parts = []
  if (status.firmware) parts.push("firmware " + status.firmware)
  if (typeof status.profile === "number") parts.push("profile " + (status.profile + 1))
  if (status.reportRate) parts.push(status.reportRate + " Hz")
  return parts.join(" · ") || "connected"
}

function draftFrom(profileState) {
  var d = (profileState && profileState["default"]) || { actuation: 20, release: 20, rt: false, rtPress: 3, rtRelease: 3, deadzoneBottom: 0 }
  return { actuation: d.actuation, release: d.release, rt: !!d.rt, rtPress: d.rtPress, rtRelease: d.rtRelease, deadzoneBottom: d.deadzoneBottom }
}

// CLI takes millimetres; raw is 0.1 mm.
function rawToArg(raw) { return (Number(raw) / 10).toFixed(1) }

function triggerArgs(draft) {
  return ["--actuation", rawToArg(draft.actuation), "--release", rawToArg(draft.release),
          "--rt", draft.rt ? "on" : "off", "--rt-press", rawToArg(draft.rtPress),
          "--rt-release", rawToArg(draft.rtRelease), "--deadzone-bottom", rawToArg(draft.deadzoneBottom)]
}

var PRESET_OPTIONS = [
  { value: "comfort", label: "Comfort" }, { value: "sensitive", label: "Sensitive" },
  { value: "gaming", label: "Gaming" }, { value: "custom", label: "Custom" }
]
var PROFILE_OPTIONS = [
  { value: "0", label: "Profile 1" }, { value: "1", label: "Profile 2" },
  { value: "2", label: "Profile 3" }, { value: "3", label: "Profile 4" }
]

var SLIDERS = [
  { key: "actuation", label: "Actuation", min: 1, max: 40, rtOnly: false },
  { key: "release", label: "Release", min: 1, max: 40, rtOnly: false },
  { key: "rtPress", label: "Rapid trigger press", min: 1, max: 40, rtOnly: true },
  { key: "rtRelease", label: "Rapid trigger release", min: 1, max: 40, rtOnly: true },
  { key: "deadzoneBottom", label: "Bottom dead zone", min: 0, max: 10, rtOnly: false }
]

var INSTALL_LINE ="sudo install -m 644 ~/.config/omarchy/plugins/user.a75/udev/60-omarchy-a75-hidraw.rules /etc/udev/rules.d/ && sudo udevadm control --reload"

// Physical layout read from the vendor's default key matrix: column-major,
// six rows per column, slot = col * 6 + row. Entries with key: false are the
// volume knob (consumer codes) and empty slots; they take no trigger settings.
var COLUMNS = [
  ["Esc", "`", "Tab", "Caps", "Shift", "Ctrl"],
  ["F1", "1", "Q", "A", "ISO\\", ""],
  ["F2", "2", "W", "S", "Z", "Super"],
  ["F3", "3", "E", "D", "X", "Alt"],
  ["F4", "4", "R", "F", "C", ""],
  ["F5", "5", "T", "G", "V", ""],
  ["F6", "6", "Y", "H", "B", "Space"],
  ["F7", "7", "U", "J", "N", "Vol−"],
  ["F8", "8", "I", "K", "M", "Vol+"],
  ["F9", "9", "O", "L", ",", "AltGr"],
  ["F10", "0", "P", ";", ".", "Fn"],
  ["F11", "-", "[", "'", "/", "Ctrl"],
  ["F12", "=", "]", "", "Shift", "←"],
  ["Del", "Bksp", "\\", "Enter", "↑", "↓"],
  ["Mute", "Ins", "End", "PgUp", "PgDn", "→"]
]
var NOT_A_SWITCH = { "Vol−": true, "Vol+": true, "Mute": true, "": true }

var LAYOUT = (function() {
  var cols = []
  for (var c = 0; c < COLUMNS.length; c++) {
    var rows = []
    for (var r = 0; r < 6; r++) {
      var label = COLUMNS[c][r]
      rows.push({ slot: c * 6 + r, label: label, key: !NOT_A_SWITCH[label] })
    }
    cols.push(rows)
  }
  return cols
})()

function keyAt(col, row) { return LAYOUT[col][row] }

function selectedSlots(selected) {
  return Object.keys(selected || {}).filter(function(k) { return selected[k] }).map(Number).sort(function(a, b) { return a - b })
}

function hasCustom(profileState, slot) {
  return !!(profileState && profileState.keys && profileState.keys[String(slot)])
}
