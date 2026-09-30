import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui

// Animated dot field: uniform flat dots drifting and bouncing elastically off
// each other, with a line drawn between any pair that comes close.
//
// The monitors are viewports onto ONE world, not three independent animations.
// Every layer surface lives in this single shell process, so one dot array and
// one integrator are shared, and each PanelWindow draws the slice of the world
// its monitor covers -- so a link straddling two screens lines up across both.
Item {
  id: root

  // Injected by omarchy-shell when the service is instantiated.
  property var shell: null
  property var manifest: null

  // ------------------------------------------------------------------ config

  // Third-party services are handed a capability-scoped shell API that exposes
  // barConfig and idleConfig but not the top-level `plugins` array, so the
  // entry for this plugin in shell.json never arrives through `shell` and every
  // setting silently fell back to its default. Read the file directly instead
  // (watched, so edits apply live); if a future shell does provide shellConfig
  // it takes precedence.
  property var fileCfg: null

  readonly property var cfg: {
    var list = shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins)
      ? shell.shellConfig.plugins : (Array.isArray(fileCfg) ? fileCfg : [])
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].id) === "user.gravity-field") return list[i]
    }
    return ({})
  }

  FileView {
    id: shellJson
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    // The first text() call in Component.onCompleted blocks, so the initial
    // seed already uses the configured values instead of seeding twice.
    blockLoading: true
    onLoaded: root.applyShellJson(text())
    // text() is stale inside the change signal itself; reload -> onLoaded.
    onFileChanged: reload()
    onLoadFailed: root.applyShellJson(null)
  }

  property string lastShellJson: ""

  function applyShellJson(raw) {
    var plugins = []
    if (raw !== null && raw !== undefined) {
      try {
        var parsed = JSON.parse(raw)
        if (parsed && Array.isArray(parsed.plugins)) plugins = parsed.plugins
      } catch (e) {
        // Half-written file mid-save: keep the last good config rather than
        // reseeding with defaults.
        return
      }
    }
    var key = JSON.stringify(plugins)
    if (key === lastShellJson && fileCfg !== null) return
    lastShellJson = key
    fileCfg = plugins
  }

  function num(key, fallback) {
    var v = cfg[key]
    return (typeof v === "number" && isFinite(v)) ? v : fallback
  }

  function flag(key, fallback) {
    var v = cfg[key]
    return (typeof v === "boolean") ? v : fallback
  }

  readonly property int dotCount: Math.max(0, Math.min(3000,
    Math.round(num("dots", num("smallDots", 420)))))
  readonly property real dotRadius: Math.max(0.5, num("radius", 2.6))
  readonly property real linkDistance: Math.max(20, num("linkDistance", 220))
  readonly property real linkOpacity: Math.max(0, Math.min(1, num("linkOpacity", 0.5)))
  readonly property real dim: Math.max(0, Math.min(1, num("dim", 0.85)))
  readonly property real speed: Math.max(1, num("speed", 55))
  readonly property int fps: Math.max(10, Math.min(60, Math.round(num("fps", 40))))
  readonly property int breathPeriod: Math.max(1000, Math.round(num("breathPeriod", 8000)))
  readonly property bool pauseWhenCovered: flag("pauseWhenCovered", true)
  // Outputs to animate on. Empty means every monitor. Each animated surface
  // carries a fixed per-frame compositing cost, so this is the main lever on
  // CPU after fps.
  readonly property var outputs: Array.isArray(cfg.outputs) ? cfg.outputs : []
  readonly property color baseColor: cfg.baseColor ? cfg.baseColor : "#ffffff"
  readonly property color interactionColor: {
    var v = String(cfg.interactionColor || "accent")
    return v === "accent" ? Color.accent : v
  }

  // Per-panel line pool. Links beyond this are dropped for that monitor.
  readonly property int linkPool: 400

  // ------------------------------------------------------------------- world

  readonly property real pad: 300
  property real wx0: 0
  property real wy0: 0
  property real wx1: 1920
  property real wy1: 1080
  readonly property real worldW: Math.max(1, wx1 - wx0)
  readonly property real worldH: Math.max(1, wy1 - wy0)

  function recomputeWorld() {
    var s = Quickshell.screens
    if (!s || s.length === 0) return
    var minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity
    for (var i = 0; i < s.length; i++) {
      minx = Math.min(minx, s[i].x)
      miny = Math.min(miny, s[i].y)
      maxx = Math.max(maxx, s[i].x + s[i].width)
      maxy = Math.max(maxy, s[i].y + s[i].height)
    }
    if (!isFinite(minx) || !isFinite(maxx)) return
    wx0 = minx - pad; wy0 = miny - pad
    wx1 = maxx + pad; wy1 = maxy + pad
  }

  // ---------------------------------------------------------------- dot state

  property var dX: null
  property var dY: null
  property var dVX: null
  property var dVY: null
  property var dFlash: null

  // Links found this frame: endpoint indices plus a 0..1 closeness weight.
  property var linkA: null
  property var linkB: null
  property var linkT: null
  property int linkCount: 0
  property int maxLinks: 1

  // Uniform-grid spatial hash. cellSize is the LINK distance, so one 3x3
  // neighbourhood sweep finds every link and every collision in one pass.
  property var cellHead: null
  property var cellNext: null
  property real cellSize: 220
  property int gridW: 1
  property int gridH: 1

  property real breath: 0
  property real clockMs: 0
  property bool seeded: false

  function rnd(a, b) { return a + Math.random() * (b - a) }

  function seed() {
    recomputeWorld()

    var n = dotCount
    dX = new Float64Array(n); dY = new Float64Array(n)
    dVX = new Float64Array(n); dVY = new Float64Array(n)
    dFlash = new Float64Array(n)

    var r = dotRadius
    for (var i = 0; i < n; i++) {
      dX[i] = rnd(wx0 + r, wx1 - r)
      dY[i] = rnd(wy0 + r, wy1 - r)
      var ang = Math.random() * Math.PI * 2
      var sp = rnd(speed * 0.6, speed * 1.4)
      dVX[i] = Math.cos(ang) * sp
      dVY[i] = Math.sin(ang) * sp
    }

    maxLinks = Math.max(1, n * 8)
    linkA = new Int32Array(maxLinks)
    linkB = new Int32Array(maxLinks)
    linkT = new Float64Array(maxLinks)
    linkCount = 0

    cellSize = linkDistance
    gridW = Math.max(1, Math.ceil(worldW / cellSize))
    gridH = Math.max(1, Math.ceil(worldH / cellSize))
    cellHead = new Int32Array(gridW * gridH)
    cellNext = new Int32Array(n)

    seeded = true
  }

  // ----------------------------------------------------------------- physics

  function step(dt) {
    if (!seeded) return
    var n = dotCount
    if (n === 0) return
    var i

    clockMs += dt * 1000
    breath = 0.5 - 0.5 * Math.cos((clockMs % breathPeriod) / breathPeriod * Math.PI * 2)

    // Everything the hot loops touch is copied into locals first. Inside a
    // QML function an unqualified property name is an object property lookup
    // on every access, which made this pass ~10x slower than the maths.
    var dX = root.dX, dY = root.dY, dVX = root.dVX, dVY = root.dVY
    var dFlash = root.dFlash
    var cellHead = root.cellHead, cellNext = root.cellNext
    var linkA = root.linkA, linkB = root.linkB, linkT = root.linkT
    var maxL = root.maxLinks
    var cs = root.cellSize, gw = root.gridW, gh = root.gridH
    var x0 = root.wx0, y0 = root.wy0, x1 = root.wx1, y1 = root.wy1

    var r = dotRadius
    var rsum = r * 2
    var rsum2 = rsum * rsum
    var linkD = linkDistance
    var linkD2 = linkD * linkD

    // Integrate, bounce off the padded world box, decay the collision flash.
    var flashDecay = dt / 0.45
    for (i = 0; i < n; i++) {
      var x = dX[i] + dVX[i] * dt
      var y = dY[i] + dVY[i] * dt

      if (x < x0 + r) { x = x0 + r; dVX[i] = Math.abs(dVX[i]) }
      else if (x > x1 - r) { x = x1 - r; dVX[i] = -Math.abs(dVX[i]) }
      if (y < y0 + r) { y = y0 + r; dVY[i] = Math.abs(dVY[i]) }
      else if (y > y1 - r) { y = y1 - r; dVY[i] = -Math.abs(dVY[i]) }

      dX[i] = x; dY[i] = y

      var f = dFlash[i] - flashDecay
      dFlash[i] = f > 0 ? f : 0
    }

    // Rebuild the spatial hash: one linked list of dot indices per cell.
    var cells = gw * gh
    for (i = 0; i < cells; i++) cellHead[i] = -1
    for (i = 0; i < n; i++) {
      var cx = (dX[i] - x0) / cs | 0
      var cy = (dY[i] - y0) / cs | 0
      if (cx < 0) cx = 0; else if (cx >= gw) cx = gw - 1
      if (cy < 0) cy = 0; else if (cy >= gh) cy = gh - 1
      var c = cy * gw + cx
      cellNext[i] = cellHead[c]
      cellHead[c] = i
    }

    // One sweep of the 3x3 neighbourhood: record links, resolve collisions.
    var lc = 0
    for (i = 0; i < n; i++) {
      var icx = (dX[i] - x0) / cs | 0
      var icy = (dY[i] - y0) / cs | 0
      if (icx < 0) icx = 0; else if (icx >= gw) icx = gw - 1
      if (icy < 0) icy = 0; else if (icy >= gh) icy = gh - 1

      for (var oy = -1; oy <= 1; oy++) {
        var ny = icy + oy
        if (ny < 0 || ny >= gh) continue
        for (var ox = -1; ox <= 1; ox++) {
          var nx = icx + ox
          if (nx < 0 || nx >= gw) continue

          for (var j = cellHead[ny * gw + nx]; j !== -1; j = cellNext[j]) {
            if (j <= i) continue

            var ddx = dX[j] - dX[i]
            var ddy = dY[j] - dY[i]
            var d2 = ddx * ddx + ddy * ddy
            if (d2 >= linkD2 || d2 <= 1e-9) continue

            var d = Math.sqrt(d2)

            if (lc < maxL) {
              linkA[lc] = i
              linkB[lc] = j
              linkT[lc] = 1 - d / linkD
              lc++
            }

            if (d2 >= rsum2) continue

            var unx = ddx / d
            var uny = ddy / d

            // Equal masses, perfectly elastic: exchange the velocity
            // components along the line of centres.
            var vn = (dVX[j] - dVX[i]) * unx + (dVY[j] - dVY[i]) * uny
            if (vn < 0) {
              dVX[i] += vn * unx; dVY[i] += vn * uny
              dVX[j] -= vn * unx; dVY[j] -= vn * uny
              dFlash[i] = 1; dFlash[j] = 1
            }

            // Push apart so they cannot stick together.
            var sep = (rsum - d) * 0.5
            dX[i] -= unx * sep; dY[i] -= uny * sep
            dX[j] += unx * sep; dY[j] += uny * sep
          }
        }
      }
    }
    linkCount = lc
  }

  // ------------------------------------------------------------------ colour

  property var colorLut: []

  function rebuildLut() {
    var lut = []
    var b = baseColor, a = interactionColor
    for (var i = 0; i <= 32; i++) {
      var t = i / 32
      lut.push(Qt.rgba(b.r + (a.r - b.r) * t,
                       b.g + (a.g - b.g) * t,
                       b.b + (a.b - b.b) * t, 1))
    }
    colorLut = lut
  }

  function colorFor(p) {
    if (colorLut.length === 0) return baseColor
    return colorLut[Math.round((p < 0 ? 0 : (p > 1 ? 1 : p)) * 32)]
  }

  onBaseColorChanged: rebuildLut()
  onInteractionColorChanged: rebuildLut()

  // ------------------------------------------------------------------ paused

  property var panels: []
  property int panelCount: 0
  property int coveredCount: 0

  readonly property var lockService: shell ? shell.serviceFor("omarchy.lock") : null
  readonly property bool locked: lockService ? lockService.lockRequested === true : false

  readonly property bool active: seeded && !locked && panelCount > 0
    && coveredCount < panelCount && dotCount > 0

  // A plain Timer, not FrameAnimation: this service is instantiated into a
  // windowless Item, so there is no render loop to deliver frame callbacks and
  // FrameAnimation never ticks here.
  //
  // The timer runs panelCount times per animation frame and each tick serves
  // ONE window: the physics steps on the first tick of a frame and panel k is
  // synced on tick k, so no two layer surfaces are re-rendered in the same
  // event-loop pass. Every panel still refreshes at `fps` and all of them
  // show the same world state (a panel is just presented up to one tick
  // later), so links crossing a monitor edge still line up. Measured here:
  // rendering both windows back to back cost 12% of a core, either alone
  // 3-4%; staggered, both together cost about what one did.
  property real lastTickMs: 0
  property int tickIndex: 0

  Timer {
    interval: Math.max(4, Math.round(1000 / (root.fps * Math.max(1, root.panelCount))))
    repeat: true
    running: root.active
    onRunningChanged: { root.lastTickMs = 0; root.tickIndex = 0 }
    onTriggered: {
      var list = root.panels
      var n = list.length > 0 ? list.length : 1
      var k = root.tickIndex
      root.tickIndex = (k + 1) % n
      if (k >= n) k = 0

      if (k === 0) {
        var now = Date.now()
        if (root.lastTickMs === 0) {
          root.lastTickMs = now
        } else {
          var dt = (now - root.lastTickMs) / 1000
          root.lastTickMs = now
          if (dt > 0.05) dt = 0.05
          if (dt > 0) root.step(dt)
        }
      }

      var p = list[k]
      if (p && !p.covered) p.sync()
    }
  }

  onDotCountChanged: seed()
  onDotRadiusChanged: seed()
  onLinkDistanceChanged: seed()

  // Inspection hook: `omarchy-shell dotfield stats`
  IpcHandler {
    target: "dotfield"

    function stats(): string {
      var out = "dots=" + root.dotCount + " radius=" + root.dotRadius
        + " linkDistance=" + root.linkDistance + " links=" + root.linkCount
        + " fps=" + root.fps + " active=" + root.active
        + " world=" + Math.round(root.wx0) + "," + Math.round(root.wy0)
        + "->" + Math.round(root.wx1) + "," + Math.round(root.wy1)
      out += " configured=" + (Object.keys(root.cfg).length > 0)
      for (var i = 0; i < root.panels.length; i++) {
        var p = root.panels[i]
        out += " [" + p.screen.name + " covered=" + p.covered
          + " linkSlots=" + p.prevLinkSlots + "]"
      }
      return out
    }

    // Micro-benchmark of the JS side: `omarchy-shell dotfield bench`.
    // step(0) runs the full hash rebuild and neighbour sweep without moving
    // anything, and sync() is idempotent, so this is safe on the live field.
    // Scene-graph rendering of the two windows is not included.
    function bench(): string {
      if (!root.seeded) return "not seeded"
      var iters = 200, i, p
      var t0 = Date.now()
      for (i = 0; i < iters; i++) root.step(0)
      var t1 = Date.now()
      for (i = 0; i < iters; i++) {
        for (p = 0; p < root.panels.length; p++) {
          if (root.panels[p] && !root.panels[p].covered) root.panels[p].sync()
        }
      }
      var t2 = Date.now()
      var stepMs = (t1 - t0) / iters, syncMs = (t2 - t1) / iters
      return "per frame: step=" + stepMs.toFixed(3) + "ms sync=" + syncMs.toFixed(3)
        + "ms total=" + (stepMs + syncMs).toFixed(3) + "ms -> ~"
        + ((stepMs + syncMs) * root.fps / 10).toFixed(1) + "% of one core at "
        + root.fps + " fps (JS only; rendering is extra)"
    }
  }

  Connections {
    target: Quickshell
    ignoreUnknownSignals: true
    function onScreensChanged() { root.recomputeWorld() }
  }

  Component.onCompleted: {
    rebuildLut()
    applyShellJson(shellJson.text())
    seed()
  }

  // ------------------------------------------------------------------ panels

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      color: "transparent"
      // Same caution as the stock background plugin: a layer surface parked
      // with updatesEnabled false has been observed to lose its committed
      // buffer and leave a black desktop.
      updatesEnabled: true

      // Sits above the wallpaper (Background) and below every app window.
      WlrLayershell.namespace: "gravity-field"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Empty input region: clicks fall through to the wallpaper below, so
      // double-click-to-switch-background keeps working.
      mask: Region {}

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }

      property bool covered: false

      // Cached delegate references. Repeater.itemAt() is a C++ call per dot
      // and per link every frame, but the delegates only change when the
      // model does, so they are looked up once and the arrays reused.
      property var dotItems: null
      property var linkItems: null
      property bool itemsDirty: true
      // Shadow copies of per-item state, so unchanged values are neither
      // re-read nor re-written across the JS/C++ boundary each frame:
      // visibility per dot and per link slot, last colour index per dot
      // (-1 means "never written"), and quantised opacity per link slot.
      property var dotVis: null
      property var linkVis: null
      property var lastColorIdx: null
      property var linkAlphaQ: null
      // How many link slots were used last frame, so only those get hidden.
      property int prevLinkSlots: 0

      function rebuildItemCache() {
        var i
        var n = dotRep.count
        var d = new Array(n)
        for (i = 0; i < n; i++) d[i] = dotRep.itemAt(i)
        dotItems = d
        var p = linkRep.count
        var l = new Array(p)
        for (i = 0; i < p; i++) l[i] = linkRep.itemAt(i)
        linkItems = l
        // Fresh delegates start visible, so the first sync positions or hides
        // every one of them.
        dotVis = new Uint8Array(n); dotVis.fill(1)
        linkVis = new Uint8Array(p); linkVis.fill(1)
        lastColorIdx = new Int16Array(n); lastColorIdx.fill(-1)
        linkAlphaQ = new Int16Array(p); linkAlphaQ.fill(-1)
        prevLinkSlots = p
        itemsDirty = false
      }

      // A monitor counts as covered when no part of the wallpaper is visible on
      // it. A single fullscreen window is the easy case; the common one is
      // several tiled windows that collectively hide everything. Testing the
      // union of the window rectangles is what makes the animation actually
      // pause during normal use, which matters far more for power than the
      // dot count does.
      readonly property bool outputEnabled:
        root.outputs.length === 0 || root.outputs.indexOf(String(panel.screen.name)) !== -1

      onOutputEnabledChanged: recomputeCovered()

      function recomputeCovered() {
        // A disabled output is treated as covered: it is neither drawn nor
        // synced, and it counts toward stopping the integrator entirely.
        if (!outputEnabled) { covered = true; return }
        if (!root.pauseWhenCovered) { covered = false; return }
        var mon = Hyprland.monitorFor(panel.screen)
        if (!mon) { covered = false; return }
        if (mon.activeWorkspace && mon.activeWorkspace.hasFullscreen) { covered = true; return }

        var wsId = mon.activeWorkspace ? mon.activeWorkspace.id : -9999
        var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var sx = panel.screen.x, sy = panel.screen.y
        var sw = panel.screen.width, sh = panel.screen.height
        var sx1 = sx + sw, sy1 = sy + sh

        // Window rectangles on this monitor's active workspace, clipped to it.
        var rx0 = [], ry0 = [], rx1 = [], ry1 = []
        for (var i = 0; i < list.length; i++) {
          var t = list[i]
          if (!t || !t.workspace || t.workspace.id !== wsId) continue
          var o = t.lastIpcObject
          if (!o || !o.at || !o.size) continue
          var ax = Math.max(sx, o.at[0]), ay = Math.max(sy, o.at[1])
          var bx = Math.min(sx1, o.at[0] + o.size[0]), by = Math.min(sy1, o.at[1] + o.size[1])
          if (bx - ax < 1 || by - ay < 1) continue
          rx0.push(ax); ry0.push(ay); rx1.push(bx); ry1.push(by)
        }
        if (rx0.length === 0) { covered = false; return }

        // Coordinate compression: the union covers the monitor iff every cell
        // of the grid formed by the rectangle edges is inside some rectangle.
        var xs = [sx, sx1], ys = [sy, sy1]
        for (i = 0; i < rx0.length; i++) {
          if (rx0[i] > sx && rx0[i] < sx1) xs.push(rx0[i])
          if (rx1[i] > sx && rx1[i] < sx1) xs.push(rx1[i])
          if (ry0[i] > sy && ry0[i] < sy1) ys.push(ry0[i])
          if (ry1[i] > sy && ry1[i] < sy1) ys.push(ry1[i])
        }
        xs.sort(function(a, b) { return a - b })
        ys.sort(function(a, b) { return a - b })

        var tol = 2
        for (var xi = 0; xi + 1 < xs.length; xi++) {
          var cx0 = xs[xi], cx1 = xs[xi + 1]
          if (cx1 - cx0 <= tol) continue
          var mx = (cx0 + cx1) * 0.5
          for (var yi = 0; yi + 1 < ys.length; yi++) {
            var cy0 = ys[yi], cy1 = ys[yi + 1]
            if (cy1 - cy0 <= tol) continue
            var my = (cy0 + cy1) * 0.5
            var inside = false
            for (i = 0; i < rx0.length; i++) {
              if (mx >= rx0[i] && mx <= rx1[i] && my >= ry0[i] && my <= ry1[i]) { inside = true; break }
            }
            if (!inside) { covered = false; return }
          }
        }
        covered = true
      }

      onCoveredChanged: root.coveredCount += (covered ? 1 : -1)

      Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(event) { panel.recomputeCovered() }
      }

      Component.onCompleted: {
        recomputeCovered()
        root.panels.push(panel)
        root.panelCount++
        if (covered) root.coveredCount++
        sync()
      }

      Component.onDestruction: {
        var idx = root.panels.indexOf(panel)
        if (idx !== -1) root.panels.splice(idx, 1)
        root.panelCount--
        if (covered) root.coveredCount--
      }

      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.dim
      }

      Item {
        id: field
        anchors.fill: parent
        visible: !panel.covered

        // Links first so they sit behind the dots.
        // Size and tint are bound, not assigned per frame: they only change
        // when the config does, and per-frame writes were the dominant cost.
        Repeater {
          id: linkRep
          model: root.linkPool
          delegate: Link { tint: root.baseColor }
          onItemAdded: panel.itemsDirty = true
          onItemRemoved: panel.itemsDirty = true
        }
        Repeater {
          id: dotRep
          model: root.dotCount
          delegate: Dot {
            width: root.dotRadius * 2
            height: root.dotRadius * 2
          }
          onItemAdded: panel.itemsDirty = true
          onItemRemoved: panel.itemsDirty = true
        }
      }

      // Places this monitor's slice of the shared world. Called once per tick
      // from the single integrator above, so all panels stay in lockstep.
      function sync() {
        if (!root.seeded || !root.dX) return
        if (itemsDirty || !dotItems || dotItems.length !== dotRep.count
            || !linkItems || linkItems.length !== linkRep.count) rebuildItemCache()
        var ox = panel.screen.x
        var oy = panel.screen.y
        var w = panel.width
        var h = panel.height
        var r = root.dotRadius
        var m = r + 4
        var i, item, px, py
        // Hoist the typed arrays: each root.* read is a property lookup.
        var dX = root.dX, dY = root.dY, dFlash = root.dFlash

        // --- dots
        var items = dotItems, vis = dotVis, lastIdx = lastColorIdx
        var count = Math.min(items.length, root.dotCount)
        for (i = 0; i < count; i++) {
          item = items[i]
          if (!item) continue
          px = dX[i] - ox
          py = dY[i] - oy
          if (px < -m || px > w + m || py < -m || py > h + m) {
            if (vis[i]) { item.visible = false; vis[i] = 0 }
            continue
          }
          if (!vis[i]) { item.visible = true; vis[i] = 1 }
          item.x = px - r
          item.y = py - r
          // Collisions are rare, so most dots keep the same colour frame to
          // frame; skipping the write avoids a scene-graph invalidation.
          var fi = Math.round(dFlash[i] * 32)
          if (lastIdx[i] !== fi) {
            item.core = root.colorFor(dFlash[i])
            lastIdx[i] = fi
          }
        }

        // --- links
        // Gently pulse the whole web rather than the dot size, so the dots stay
        // exactly uniform. Opacity is quantised to 1/64 steps (invisible on a
        // dim 1px line) so the write can be skipped when it has not moved.
        var alphaScale = root.linkOpacity * (0.75 + 0.25 * root.breath) * 64
        var lm = 8
        var slot = 0
        var litems = linkItems, lvis = linkVis, laq = linkAlphaQ
        var pool = litems.length
        var lc = root.linkCount
        var linkA = root.linkA, linkB = root.linkB, linkT = root.linkT
        for (i = 0; i < lc && slot < pool; i++) {
          var a = linkA[i], b = linkB[i]
          var ax = dX[a] - ox, ay = dY[a] - oy
          var bx = dX[b] - ox, by = dY[b] - oy

          // Skip only if the whole segment is off this monitor.
          if ((ax < -lm && bx < -lm) || (ax > w + lm && bx > w + lm)) continue
          if ((ay < -lm && by < -lm) || (ay > h + lm && by > h + lm)) continue

          var sx = bx - ax, sy = by - ay
          var len = Math.sqrt(sx * sx + sy * sy)
          if (len < 0.5) continue

          item = litems[slot]
          if (!item) break
          if (!lvis[slot]) { item.visible = true; lvis[slot] = 1 }
          item.width = len
          item.x = (ax + bx) * 0.5 - len * 0.5
          item.y = (ay + by) * 0.5 - 0.5
          item.rotation = Math.atan2(sy, sx) * 57.29577951308232
          var aq = (linkT[i] * alphaScale) | 0
          if (laq[slot] !== aq) { item.opacity = aq / 64; laq[slot] = aq }
          slot++
        }
        // Only clear slots that were in use last frame.
        for (i = slot; i < prevLinkSlots && i < pool; i++) {
          if (lvis[i] && litems[i]) { litems[i].visible = false; lvis[i] = 0 }
        }
        prevLinkSlots = slot
      }
    }
  }
}
