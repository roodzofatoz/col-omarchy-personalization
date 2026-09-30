import QtQuick
import Quickshell
import Quickshell.Io

// user.a75 engine: polls bin/omarchy-a75 status and runs every write through
// one queue so two panel edits never interleave on the wire.
Item {
  id: root

  Component.onCompleted: A75Registry.engine = root
  Component.onDestruction: {
    if (A75Registry.engine === root) A75Registry.engine = null
    if (depthRunning) Quickshell.execDetached([bin, "depth", "stop"])
  }

  // ---- key-depth stream (only while the panel is open) ------------
  property var depth: null
  property bool depthRunning: false
  function startDepth() {
    if (depthRunning) return
    depthRunning = true
    run(["depth", "start"], function(r) {
      if (!root.depthRunning) return
      depthProc.command = [root.bin, "depth", "watch"]
      depthProc.running = true
    })
  }
  function stopDepth() {
    if (!depthRunning) return
    depthRunning = false
    depthProc.running = false
    depth = null
    run(["depth", "stop"], null)
  }

  Process {
    id: depthProc
    stdout: SplitParser {
      onRead: function(line) {
        try { root.depth = JSON.parse(line) } catch (e) {}
      }
    }
  }

  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property string bin: Qt.resolvedUrl("bin/omarchy-a75").toString().replace(/^file:\/\//, "")
  readonly property int refreshSec: Math.max(15, Number((settings && settings.refreshIntervalSec) || 60))

  property var status: null
  property var profileState: null
  property bool busy: false
  property string lastError: ""

  readonly property bool present: !!(status && status.present === true)
  readonly property bool permissionError: !!(status && status.permissionError === true)
  // True while the vendor hub owns the keyboard (omarchy-a75-hub writes a hold file).
  readonly property bool held: !!(status && status.held === true)
  readonly property bool stalled: !!(status && status.stalled === true)
  readonly property string preset: (status && status.preset) ? status.preset : ""
  readonly property int profile: (status && typeof status.profile === "number") ? status.profile : -1
  readonly property string firmware: (status && status.firmware) ? status.firmware : ""

  function applySettings(next) { settings = next || {} }

  // ---- serialized command queue -------------------------------------
  property var queue: []
  property var current: null

  function refresh() { run(["status"], null) }
  function loadProfileState() { run(["profile-state"], null) }

  function run(args, done) {
    queue.push({ args: args, done: done })
    pump()
  }

  function pump() {
    if (current || queue.length === 0) return
    current = queue.shift()
    busy = true
    proc.command = [bin].concat(current.args)
    proc.running = true
  }

  Process {
    id: proc
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(code) {
      var job = root.current
      root.current = null
      root.busy = false
      var result = null
      try { result = JSON.parse(out.text) } catch (e) { result = null }
      // Every command prints the status document, even when it failed (unplugged,
      // no permission, held by the vendor hub): always take the presence info.
      if (result && result.present !== undefined) root.status = result
      if (result && result.profileState !== undefined) root.profileState = result.profileState
      var failed = code !== 0 || !result || !!result.error
      var isPoll = !job || !job.args || job.args[0] === "status"
      if (failed) {
        root.lastError = (result && result.error) || (err.text || "").trim().split("\n").pop() || ("command exited " + code)
        if (!isPoll) {
          // A background poll failing would nag every refresh; user actions do notify,
          // and the state is re-read so the panel never shows a stale "connected".
          Quickshell.execDetached(["notify-send", "-a", "VGN A75", "Keyboard command failed", root.lastError])
          root.refresh()
        }
      } else if (!isPoll) {
        // Polls never touch lastError: it describes the last user command until
        // the next one succeeds.
        root.lastError = ""
      }
      if (job && typeof job.done === "function") job.done(result, !failed)
      root.pump()
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // `omarchy-shell user.a75-engine status|refresh|profileState|run 'trigger|--all|--actuation|1.9'`
  IpcHandler {
    target: "user.a75-engine"
    function status(): string { return JSON.stringify(root.status) }
    function profileState(): string { return JSON.stringify(root.profileState) }
    function depth(): string { return JSON.stringify({ running: root.depthRunning, last: root.depth }) }
    function error(): string { return root.lastError }
    function refresh(): void { root.refresh() }
    // Debug aid: push a CLI invocation through the same queue the panel uses.
    // Arguments are '|'-separated because the IPC wrapper splits on commas.
    function run(args: string): string {
      var list = String(args).split("|").filter(function(a) { return a !== "" })
      if (list.length === 0) return "no arguments"
      root.run(list, null)
      return "queued"
    }
  }
}
