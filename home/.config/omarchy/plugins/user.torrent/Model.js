.pragma library

// Nerd Font (Material Design set) glyphs, same family the other user plugins use.
var DOWNLOAD_ICON = "\u{F01DA}"    // nf-md-download
var MAGNET_ICON = "\u{F0348}"      // nf-md-magnet
var PLAY_ICON = "\u{F040A}"        // nf-md-play
var PAUSE_ICON = "\u{F03E4}"       // nf-md-pause
var STOP_ICON = "\u{F04DB}"        // nf-md-stop
var FOLDER_ICON = "\u{F024B}"      // nf-md-folder
var REMOVE_ICON = "\u{F0156}"      // nf-md-close
var TRASH_ICON = "\u{F01B4}"       // nf-md-delete
var ALERT_ICON = "\u{F0026}"       // nf-md-alert
var DOT_ICON = "\u{F0765}"         // nf-md-circle_medium
var REFRESH_ICON = "\u{F0450}"     // nf-md-refresh
var PASTE_ICON = "\u{F0192}"       // nf-md-content_paste
var FILE_ICON = "\u{F0214}"        // nf-md-file
var VIDEO_ICON = "\u{F0567}"       // nf-md-video
var MUSIC_ICON = "\u{F075A}"       // nf-md-music
var CHEVRON_DOWN = "\u{F0140}"     // nf-md-chevron_down
var CHEVRON_RIGHT = "\u{F0142}"    // nf-md-chevron_right
var SEED_ICON = "\u{F0552}"        // nf-md-upload
var SEQ_ICON = "\u{F0C7E}"         // nf-md-sort_numeric_ascending (sequential)
var CHECK_ICON = "\u{F012C}"       // nf-md-check
var PLUS_ICON = "\u{F0415}"        // nf-md-plus
var POWER_ICON = "\u{F0425}"       // nf-md-power
var CHECKBOX_ON = "\u{F0132}"      // nf-md-checkbox_marked
var CHECKBOX_OFF = "\u{F0131}"     // nf-md-checkbox_blank_outline
var ARROW_DOWN = "\u{F0045}"       // nf-md-arrow_down
var ARROW_UP = "\u{F005D}"         // nf-md-arrow_up

var VIDEO_EXT = { mp4: 1, mkv: 1, avi: 1, mov: 1, webm: 1, m4v: 1, ts: 1, m2ts: 1, wmv: 1, flv: 1, mpg: 1, mpeg: 1, ogv: 1, "3gp": 1 }

function isVideo(name) {
  var i = (name || "").lastIndexOf(".")
  return i >= 0 && !!VIDEO_EXT[name.slice(i + 1).toLowerCase()]
}

function size(n) {
  n = Number(n) || 0
  var units = ["B", "KB", "MB", "GB", "TB"]
  var u = 0
  while (n >= 1024 && u < units.length - 1) { n /= 1024; u++ }
  return (u === 0 ? Math.round(n) : n.toFixed(u >= 3 ? 2 : 1)) + " " + units[u]
}

function speed(bps) {
  bps = Number(bps) || 0
  if (bps <= 0) return "0 B/s"
  return size(bps) + "/s"
}

function shortSpeed(bps) {
  bps = Number(bps) || 0
  if (bps < 1024) return Math.round(bps) + " B/s"
  if (bps < 1024 * 1024) return Math.round(bps / 1024) + " K/s"
  return (bps / (1024 * 1024)).toFixed(1) + " M/s"
}

function eta(seconds) {
  seconds = Number(seconds)
  if (!isFinite(seconds) || seconds < 0) return ""
  if (seconds < 60) return seconds + "s"
  var m = Math.floor(seconds / 60)
  if (m < 60) return m + "m " + (seconds % 60) + "s"
  var h = Math.floor(m / 60)
  if (h < 48) return h + "h " + (m % 60) + "m"
  return Math.floor(h / 24) + "d " + (h % 24) + "h"
}

function percent(p) { return Math.floor((Number(p) || 0) * 1000) / 10 + "%" }

function stateLabel(t) {
  if (!t) return ""
  switch (t.state) {
    case "downloading": return "downloading"
    case "seeding": return "seeding"
    case "metadata": return "fetching metadata…"
    case "checking": return "checking"
    case "queued": return "queued"
    case "paused": return "paused"
    case "done": return "done"
    case "error": return "error"
    default: return t.state || ""
  }
}

function detail(t) {
  if (!t) return ""
  var parts = []
  if (t.state === "downloading") {
    parts.push(ARROW_DOWN + " " + speed(t.rateDown))
    if (t.rateUp > 0) parts.push(ARROW_UP + " " + speed(t.rateUp))
    if (t.eta >= 0) parts.push(eta(t.eta) + " left")
    parts.push(t.seeds + "/" + t.peers + " peers")
  } else if (t.state === "seeding") {
    parts.push(ARROW_UP + " " + speed(t.rateUp))
    parts.push("ratio " + (Number(t.ratio) || 0).toFixed(2))
    parts.push(t.peers + " peers")
  } else if (t.state === "metadata") {
    parts.push(t.peers + " peers")
  } else if (t.state === "error") {
    parts.push(t.error || "error")
  } else {
    parts.push(stateLabel(t))
    if (t.state === "paused" && t.percent < 1) parts.push(percent(t.percent))
  }
  return parts.join(" · ")
}

function sizeLine(t) {
  if (!t || !t.size) return ""
  if (t.percent >= 1) return size(t.size)
  return size(t.size - t.left) + " / " + size(t.size)
}

// Flat row list for the ListView: torrents, optionally followed by their files.
function buildRows(torrents, expanded, daemonState) {
  var rows = []
  if (daemonState === "missing") {
    rows.push({ type: "empty", key: "empty", text: "transmission-daemon is not installed — run: omarchy pkg add transmission-cli" })
    return rows
  }
  if (daemonState !== "running") {
    rows.push({ type: "empty", key: "empty", text: daemonState === "starting" ? "Starting the torrent daemon…" : "Torrent daemon is not running." })
    return rows
  }
  if (!torrents || !torrents.length) {
    rows.push({ type: "empty", key: "empty", text: "No torrents. Paste a magnet link above, pick a .torrent file, or click a magnet link in the browser." })
    return rows
  }
  for (var i = 0; i < torrents.length; i++) {
    var t = torrents[i]
    var open = !!expanded[String(t.id)]
    rows.push({ type: "torrent", key: "t" + t.id, t: t, expanded: open })
    if (open) {
      for (var j = 0; j < t.files.length; j++) rows.push({ type: "file", key: "f" + t.id + "-" + j, t: t, f: t.files[j] })
    }
  }
  return rows
}

function isSelectable(row) { return !!row && (row.type === "torrent" || row.type === "file") }
