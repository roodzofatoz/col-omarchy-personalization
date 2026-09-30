.pragma library

// Nerd Font (Material Design set) glyphs, same family the flac plugin uses.
var SERVER_ICON = "\u{F048B}"      // nf-md-server
var PLAY_ICON = "\u{F040A}"        // nf-md-play
var STOP_ICON = "\u{F04DB}"        // nf-md-stop
var RESTART_ICON = "\u{F0450}"     // nf-md-refresh
var FOLDER_ICON = "\u{F024B}"      // nf-md-folder
var TERMINAL_ICON = "\u{F018D}"    // nf-md-console
var WEB_ICON = "\u{F059F}"         // nf-md-web
var LOG_ICON = "\u{F09EE}"         // nf-md-file_document_outline
var REMOVE_ICON = "\u{F0156}"      // nf-md-close
var CLOCK_ICON = "\u{F0954}"       // nf-md-history
var DOT_ICON = "\u{F0765}"         // nf-md-circle_medium
var ALERT_ICON = "\u{F0026}"       // nf-md-alert
var DOCKER_ICON = "\u{F0868}"      // nf-md-docker

function isDocker(inst) { return !!inst && (inst.kind === "compose" || inst.kind === "container") }

function dockerDetail(inst) {
  if (!isDocker(inst) || !inst.docker) return ""
  if (inst.kind === "compose") return "compose · " + ((inst.docker.containers || []).length ? (inst.docker.containers || []).join(", ") : inst.docker.project || "")
  return "container · " + (inst.docker.image || "")
}

function uptime(sinceEpoch, nowMs) {
  if (!sinceEpoch) return ""
  var s = Math.max(0, Math.floor(nowMs / 1000) - sinceEpoch)
  if (s < 60) return "up " + s + "s"
  var m = Math.floor(s / 60)
  if (m < 60) return "up " + m + "m"
  var h = Math.floor(m / 60)
  if (h < 48) return "up " + h + "h " + (m % 60) + "m"
  return "up " + Math.floor(h / 24) + "d"
}

function ago(iso, nowMs) {
  if (!iso) return ""
  var t = Date.parse(iso)
  if (isNaN(t)) return ""
  var s = Math.max(0, Math.floor((nowMs - t) / 1000))
  if (s < 60) return "just now"
  var m = Math.floor(s / 60)
  if (m < 60) return m + " min ago"
  var h = Math.floor(m / 60)
  if (h < 24) return h + " h ago"
  var d = Math.floor(h / 24)
  if (d < 14) return d + " d ago"
  var dt = new Date(t)
  return dt.toLocaleDateString(Qt.locale(), "d MMM")
}

function portsText(inst) {
  if (!inst) return ""
  var ports = inst.ports || []
  var out = []
  for (var i = 0; i < ports.length; i++) out.push(":" + (typeof ports[i] === "number" ? ports[i] : ports[i].port))
  return out.join("  ")
}

function firstPort(inst) {
  if (!inst || !inst.ports || !inst.ports.length) return 0
  var p = inst.ports[0]
  return typeof p === "number" ? p : p.port
}

function elide(s, n) {
  if (!s) return ""
  return s.length > n ? s.substring(0, n - 1) + "…" : s
}

// Flatten engine state into panel rows: section headers + instance rows.
function buildRows(running, recent) {
  var rows = []
  rows.push({ type: "header", key: "h-run", title: "Running", count: running.length })
  if (!running.length) rows.push({ type: "empty", key: "e-run", text: "Nothing is listening from a project folder right now." })
  for (var i = 0; i < running.length; i++) rows.push({ type: "running", key: "r-" + running[i].id, inst: running[i] })
  rows.push({ type: "header", key: "h-rec", title: "Ran before", count: recent.length })
  if (!recent.length) rows.push({ type: "empty", key: "e-rec", text: "Instances you stop will stay here so you can start them again." })
  for (var j = 0; j < recent.length; j++) rows.push({ type: "recent", key: "p-" + recent[j].id, inst: recent[j] })
  return rows
}

function isInstance(row) { return row && (row.type === "running" || row.type === "recent") }
