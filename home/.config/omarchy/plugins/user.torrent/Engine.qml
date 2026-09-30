import QtQuick
import Quickshell
import Quickshell.Io

// user.torrent engine: the one-per-shell service that polls bin/omarchy-torrent
// and exposes the torrent list, transfer rates and active streams. Bar widgets
// (one per monitor) only render this and call its functions.
//
// Nothing here owns a network process: transmission-daemon runs as the
// transient `omarchy-torrent-daemon` systemd user unit and every stream
// server as `omarchy-torrent-stream-<id>-<file>`, so they survive shell
// restarts and plugin hot-reloads; the next engine simply sees them again.
Item {
  id: root

  Component.onCompleted: {
    TorrentRegistry.engine = root
    bootstrap.start()
  }
  Component.onDestruction: { if (TorrentRegistry.engine === root) TorrentRegistry.engine = null }

  property var shell: null
  property var manifest: null
  // Pushed by the bar widget from its inline shell.json entry.
  property var settings: ({})

  readonly property string bin: Qt.resolvedUrl("bin/omarchy-torrent").toString().replace(/^file:\/\//, "")
  readonly property int pollSeconds: Math.max(2, Number((settings && settings.pollSeconds) || 4))
  readonly property bool handleMagnetLinks: !(settings && settings.handleMagnetLinks === false)

  // ---------------------------------------------------------------- state
  property string daemon: "unknown"      // running | starting | down | missing | unknown
  property var torrents: []
  property var streams: []
  property var config: ({})
  property int rateDown: 0
  property int rateUp: 0
  property string scannedAt: ""
  property bool scanning: false
  property string lastError: ""
  property string notice: ""
  // Magnet / .torrent sitting in the clipboard (checked when a panel opens).
  property string clipboardCandidate: ""
  // id -> "pausing" | "resuming" | "removing" | "streaming" while an action is in flight.
  property var busy: ({})
  // Widgets add themselves here while their panel is open: poll faster then.
  property int openPanels: 0

  readonly property int activeCount: {
    var n = 0
    for (var i = 0; i < torrents.length; i++) if (torrents[i].state === "downloading" || torrents[i].state === "metadata") n++
    return n
  }
  readonly property int seedingCount: {
    var n = 0
    for (var i = 0; i < torrents.length; i++) if (torrents[i].state === "seeding") n++
    return n
  }
  readonly property int errorCount: {
    var n = 0
    for (var i = 0; i < torrents.length; i++) if (torrents[i].state === "error") n++
    return n
  }

  // ------------------------------------------------------------- settings
  property string appliedConfig: ""
  function applySettings(next) {
    settings = next || {}
    var cfg = {
      downloadDir: settings.downloadDir || "",
      rpcPort: settings.rpcPort || "",
      seedRatioLimit: (settings.seedRatioLimit === undefined || settings.seedRatioLimit === null) ? "" : settings.seedRatioLimit,
      player: settings.player || ""
    }
    var s = JSON.stringify(cfg)
    if (s !== appliedConfig) {
      appliedConfig = s
      act("configure", s)
    }
  }

  Timer {
    id: bootstrap
    interval: 400
    onTriggered: {
      if (root.handleMagnetLinks) root.act("register")
      root.rescan(true)
    }
  }

  // ------------------------------------------------------------------ scan
  function rescan(wait) {
    if (scanProc.running) return
    scanning = true
    scanProc.command = wait ? [bin, "status", "--wait"] : [bin, "status"]
    scanProc.running = true
  }

  Process {
    id: scanProc
    command: [root.bin, "status"]
    stdout: StdioCollector { id: scanOut; waitForEnd: true }
    stderr: StdioCollector { id: scanErr; waitForEnd: true }
    onExited: function(code) {
      root.scanning = false
      if (code !== 0) {
        root.lastError = "status failed: " + (scanErr.text || ("exit " + code)).trim()
        return
      }
      try {
        var d = JSON.parse(scanOut.text)
        root.daemon = d.daemon || "down"
        root.torrents = d.torrents || []
        root.streams = d.streams || []
        root.config = d.config || {}
        root.rateDown = d.rateDown || 0
        root.rateUp = d.rateUp || 0
        root.scannedAt = d.scannedAt || ""
        if (d.error) root.lastError = d.error
        // Drop "busy" markers whose outcome the scan now reflects.
        var next = {}
        var changed = false
        for (var id in root.busy) {
          var t = root.find(Number(id))
          var b = root.busy[id]
          var keep = (b === "pausing" && t && t.state !== "paused" && t.state !== "done")
            || (b === "resuming" && t && (t.state === "paused" || t.state === "done"))
            || (b === "removing" && !!t)
          if (keep) next[id] = b; else changed = true
        }
        if (changed) root.busy = next
      } catch (e) {
        root.lastError = "status returned unreadable output"
      }
    }
  }

  Timer {
    interval: root.openPanels > 0 ? 1000 : root.pollSeconds * 1000
    running: true
    repeat: true
    onTriggered: root.rescan(false)
  }

  function find(id) {
    for (var i = 0; i < torrents.length; i++) if (torrents[i].id === id) return torrents[i]
    return null
  }

  // --------------------------------------------------------------- actions
  // Actions run one at a time through a single Process so their JSON reply
  // (and any error) is read back; every completed action triggers a rescan.
  property var queue: []

  function act() {
    var args = [bin]
    for (var i = 0; i < arguments.length; i++) {
      if (arguments[i] === undefined || arguments[i] === null) continue
      args.push(String(arguments[i]))
    }
    queue = queue.concat([args])
    pump()
  }

  function pump() {
    if (actionProc.running || !queue.length) return
    var next = queue[0]
    queue = queue.slice(1)
    actionProc.command = next
    actionProc.running = true
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actOut; waitForEnd: true }
    stderr: StdioCollector { id: actErr; waitForEnd: true }
    onExited: function(code) {
      var reply = null
      try { reply = JSON.parse(actOut.text) } catch (e) {}
      var op = actionProc.command.length > 1 ? actionProc.command[1] : ""
      if (reply && reply.ok === false) root.lastError = reply.error || (op + " failed")
      else if (code !== 0) root.lastError = (actErr.text || (op + " exited " + code)).trim()
      else {
        root.lastError = ""
        if (op === "add" && reply) {
          root.notice = reply.duplicate ? "Already added: " + (reply.name || "") : "Added: " + (reply.name || "torrent")
          noticeTimer.restart()
          root.clipboardCandidate = ""
        } else if (op === "stream" && reply && reply.url) {
          root.notice = "Streaming → " + (root.config.player || "mpv")
          noticeTimer.restart()
        }
      }
      if (op === "stream" || op === "pick") {
        // The stream unit or the file dialog held the queue; clear the marker now.
        var next = Object.assign({}, root.busy)
        for (var id in next) if (next[id] === "streaming") delete next[id]
        root.busy = next
      }
      if (op !== "clipboard" && op !== "register") root.rescan(false)
      root.pump()
    }
  }

  Timer { id: noticeTimer; interval: 5000; onTriggered: root.notice = "" }

  function mark(id, state) {
    var next = Object.assign({}, busy)
    next[String(id)] = state
    busy = next
  }

  function add(source) {
    var s = (source || "").trim()
    if (!s) return
    act("add", s)
  }
  function addFromClipboard() { if (clipboardCandidate) add(clipboardCandidate) }
  function pickFile() { pickProc.running = true }
  function pause(id) { mark(id, "pausing"); act("pause", id) }
  function resume(id) { mark(id, "resuming"); act("resume", id) }
  function toggle(id) {
    var t = find(id)
    if (!t) return
    if (t.state === "paused" || t.state === "done") resume(id); else pause(id)
  }
  function remove(id, deleteData) { mark(id, "removing"); act("remove", id, deleteData ? "--data" : null) }
  function setSequential(id, on) { act("sequential", id, on ? "on" : "off") }
  function setWanted(id, fileIndex, on) { act("wanted", id, fileIndex, on ? "on" : "off") }
  function openFolder(id) { act("open", id) }
  function verify(id) { act("verify", id) }
  function stream(id, fileIndex) {
    if (fileIndex === undefined || fileIndex === null || fileIndex < 0) {
      var t = find(id)
      if (!t || t.bestMedia < 0) { lastError = "No playable media file in this torrent yet"; return }
      fileIndex = t.bestMedia
    }
    mark(id, "streaming")
    act("stream", id, fileIndex)
  }
  function stopStream(id, fileIndex) { act("stop-stream", id, fileIndex) }
  function daemonStart() { act("daemon", "start") }
  function daemonStop() { act("daemon", "stop") }
  function daemonRestart() { act("daemon", "restart") }
  function clearError() { lastError = "" }

  function isStreaming(id, fileIndex) {
    for (var i = 0; i < streams.length; i++) {
      var s = streams[i]
      if (s.torrentId === id && (fileIndex === undefined || fileIndex === null || s.fileIndex === fileIndex)) return true
    }
    return false
  }

  // File picker runs outside the action queue: zenity blocks until the user
  // answers, and the queue must stay free for pause/resume meanwhile.
  Process {
    id: pickProc
    command: [root.bin, "pick"]
    stdout: StdioCollector { id: pickOut; waitForEnd: true }
    onExited: function(code) {
      var reply = null
      try { reply = JSON.parse(pickOut.text) } catch (e) {}
      if (reply && reply.ok === false) root.lastError = reply.error || "pick failed"
      else if (reply && reply.ok && !reply.cancelled) {
        root.notice = (reply.duplicate ? "Already added: " : "Added: ") + (reply.name || "torrent")
        noticeTimer.restart()
      }
      root.rescan(false)
    }
  }

  // Clipboard check when a panel opens.
  function checkClipboard() { if (!clipProc.running) clipProc.running = true }
  Process {
    id: clipProc
    command: [root.bin, "clipboard"]
    stdout: StdioCollector { id: clipOut; waitForEnd: true }
    onExited: function(code) {
      try {
        var d = JSON.parse(clipOut.text)
        root.clipboardCandidate = (d && d.candidate) || ""
      } catch (e) { root.clipboardCandidate = "" }
    }
  }

  // `omarchy-shell user.torrent add <magnet|file>|list|rescan|stream <id> [file]`
  IpcHandler {
    target: "user.torrent"
    function list(): string { return JSON.stringify({ daemon: root.daemon, torrents: root.torrents, streams: root.streams }) }
    function add(source: string): void { root.add(source) }
    function rescan(): void { root.rescan(false) }
    function stream(id: string, fileIndex: string): void { root.stream(Number(id), fileIndex === "" ? -1 : Number(fileIndex)) }
    function pause(id: string): void { root.pause(Number(id)) }
    function resume(id: string): void { root.resume(Number(id)) }
  }
}
