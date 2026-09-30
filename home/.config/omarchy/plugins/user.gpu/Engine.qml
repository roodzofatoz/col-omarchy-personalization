import QtQuick
import Quickshell
import Quickshell.Io

// user.gpu engine: runs bin/omarchy-gpu-updates on a schedule and keeps the
// last report for the bar widgets (one per monitor) to render.
Item {
  id: root

  Component.onCompleted: GpuRegistry.engine = root
  Component.onDestruction: { if (GpuRegistry.engine === root) GpuRegistry.engine = null }

  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property string bin: Qt.resolvedUrl("bin/omarchy-gpu-updates").toString().replace(/^file:\/\//, "")
  readonly property real checkHours: Math.max(0.25, Number((settings && settings.checkHours) || 6))
  readonly property bool checkUpstream: !(settings && settings.checkUpstream === false)

  property var report: null
  property bool checking: false
  property string lastError: ""
  property string checkedAt: ""
  // True from the moment an update was launched until the re-check after it
  // has finished, so the indicator stays visible while the update runs.
  property bool updating: false

  readonly property int updateCount: report && report.updates ? report.updates.length : 0
  readonly property bool rebootNeeded: !!(report && report.rebootNeeded)
  readonly property bool attention: updateCount > 0 || rebootNeeded

  function applySettings(next) { settings = next || {} }

  function check() {
    if (checkProc.running) return
    checking = true
    checkProc.command = checkUpstream ? [bin, "check"] : [bin, "check", "--no-upstream"]
    checkProc.running = true
  }

  Process {
    id: checkProc
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(code) {
      root.checking = false
      root.updating = false
      if (code !== 0) {
        root.lastError = (err.text || ("check exited " + code)).trim().split("\n").pop()
        return
      }
      try {
        var d = JSON.parse(out.text)
        root.report = d
        root.checkedAt = d.checkedAt || ""
        root.lastError = d.warnings && d.warnings.length ? d.warnings.join("; ") : ""
      } catch (e) {
        root.lastError = "check returned unreadable output"
      }
    }
  }

  Timer {
    interval: root.checkHours * 3600 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.check()
  }

  // Full system update in Omarchy's floating presentation terminal — the
  // same flow as the stock update widget. Partial upgrades are unsupported on
  // Arch, so drivers are updated together with everything else.
  function update() {
    updating = true
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"])
    recheck.restart()
  }

  // Re-check a while after an update was launched (the terminal is
  // interactive, so the exact end isn't known).
  Timer { id: recheck; interval: 120000; repeat: false; onTriggered: root.check() }

  function openReleaseNotes() {
    var url = "https://www.nvidia.com/en-us/drivers/unix/"
    if (report && report.gpus && report.gpus.length) {
      var v = report.gpus[0].vendor
      if (v === "amd") url = "https://docs.mesa3d.org/relnotes.html"
      else if (v === "intel") url = "https://docs.mesa3d.org/relnotes.html"
    }
    Quickshell.execDetached(["xdg-open", url])
  }

  function reboot() {
    Quickshell.execDetached(["omarchy-system-reboot"])
  }

  // `omarchy-shell user.gpu check|status|update`
  IpcHandler {
    target: "user.gpu"
    function check(): void { root.check() }
    function status(): string { return JSON.stringify({ updates: root.report ? root.report.updates : null, rebootNeeded: root.rebootNeeded, checkedAt: root.checkedAt, error: root.lastError }) }
    function update(): void { root.update() }
    // Debug aid: inject a fake report (JSON) to preview the pending/reboot UI;
    // the next scheduled or manual check replaces it.
    function setReport(json: string): string {
      try { root.report = JSON.parse(json); root.checkedAt = root.report.checkedAt || root.checkedAt; root.lastError = ""; return "ok" }
      catch (e) { return "bad json" }
    }
    function setUpdating(flag: string): void { root.updating = flag === "true" }
  }
}
