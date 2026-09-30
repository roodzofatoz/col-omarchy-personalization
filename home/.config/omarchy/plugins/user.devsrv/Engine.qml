import QtQuick
import Quickshell
import Quickshell.Io

// user.devsrv engine: the one-per-shell service that polls bin/omarchy-devsrv
// and exposes the running instances and the history. Bar widgets (one per
// monitor) only render this and call its functions.
//
// Nothing here owns a server process: instances started from the panel run
// as transient `devsrv-<id>` systemd user units, so they survive shell
// restarts and plugin hot-reloads, and the next engine simply sees them in
// the scan.
Item {
  id: root

  Component.onCompleted: DevsrvRegistry.engine = root
  Component.onDestruction: { if (DevsrvRegistry.engine === root) DevsrvRegistry.engine = null }

  property var shell: null
  property var manifest: null
  // Pushed by the bar widget from its inline shell.json entry.
  property var settings: ({})

  readonly property string bin: Qt.resolvedUrl("bin/omarchy-devsrv").toString().replace(/^file:\/\//, "")
  readonly property int pollSeconds: Math.max(2, Number((settings && settings.pollSeconds) || 5))
  readonly property int historyLimit: Math.max(1, Number((settings && settings.historyLimit) || 30))

  property var running: []
  property var history: []
  readonly property var recent: {
    var out = []
    for (var i = 0; i < history.length; i++) if (!history[i].running) out.push(history[i])
    return out.slice(0, historyLimit)
  }
  readonly property int runningCount: running.length
  property string scannedAt: ""
  property bool scanning: false
  property string lastError: ""
  // id -> "starting" | "stopping" while an action is in flight, cleared by
  // the scan that follows it.
  property var busy: ({})
  // Widgets add themselves here while their panel is open: poll faster then.
  property int openPanels: 0

  function applySettings(next) { settings = next || {} }

  // ------------------------------------------------------------------ scan
  function rescan() {
    if (scanProc.running) return
    scanning = true
    scanProc.running = true
  }

  Process {
    id: scanProc
    command: [root.bin, "scan"]
    stdout: StdioCollector {
      id: scanOut
      waitForEnd: true
    }
    stderr: StdioCollector { id: scanErr; waitForEnd: true }
    onExited: function(code) {
      root.scanning = false
      if (code !== 0) {
        root.lastError = "scan failed: " + (scanErr.text || ("exit " + code)).trim()
        return
      }
      try {
        var d = JSON.parse(scanOut.text)
        root.running = d.running || []
        root.history = d.history || []
        root.scannedAt = d.scannedAt || ""
        root.lastError = ""
        // Drop "busy" markers whose outcome the scan now reflects.
        var next = {}
        var changed = false
        for (var id in root.busy) {
          var isRunning = root.isRunning(id)
          var keep = (root.busy[id] === "starting" && !isRunning) || (root.busy[id] === "stopping" && isRunning)
          if (keep) next[id] = root.busy[id]; else changed = true
        }
        if (changed) root.busy = next
      } catch (e) {
        root.lastError = "scan returned unreadable output"
      }
    }
  }

  Timer {
    interval: root.openPanels > 0 ? 1500 : root.pollSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.rescan()
  }

  function isRunning(id) {
    for (var i = 0; i < running.length; i++) if (running[i].id === id) return true
    return false
  }

  function find(id) {
    for (var i = 0; i < running.length; i++) if (running[i].id === id) return running[i]
    for (var j = 0; j < history.length; j++) if (history[j].id === id) return history[j]
    return null
  }

  // --------------------------------------------------------------- actions
  // Actions run one at a time through a single Process so their JSON reply
  // (and any error) is read back; every completed action triggers a rescan.
  property var queue: []

  function act(op, id, extra) {
    var args = [bin, op, id]
    if (extra !== undefined && extra !== null) args.push(String(extra))
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
      if (reply && reply.ok === false) root.lastError = reply.error || "action failed"
      else if (code !== 0) root.lastError = (actErr.text || ("action exited " + code)).trim()
      else root.lastError = ""
      root.rescan()
      root.pump()
    }
  }

  function mark(id, state) {
    var next = Object.assign({}, busy)
    next[id] = state
    busy = next
  }

  function start(id) { mark(id, "starting"); act("start", id) }
  function stop(id) { mark(id, "stopping"); act("stop", id) }
  function restart(id) { mark(id, "starting"); act("stop", id); act("start", id) }
  function openFolder(id) { act("open", id) }
  function openTerminal(id) { act("terminal", id) }
  function openLogs(id) { act("logs", id) }
  function openUrl(id, port) { act("url", id, port) }
  function forget(id) { act("forget", id) }
  function clearError() { lastError = "" }

  // `omarchy-shell user.devsrv list|start <id>|stop <id>|rescan`
  IpcHandler {
    target: "user.devsrv"
    function list(): string { return JSON.stringify({ running: root.running, recent: root.recent }) }
    function start(id: string): void { root.start(id) }
    function stop(id: string): void { root.stop(id) }
    function rescan(): void { root.rescan() }
  }
}
