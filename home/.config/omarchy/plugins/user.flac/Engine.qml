import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// user.flac engine: the one-per-shell service that owns the mpv process and
// the JSON IPC socket. Bar widgets (one per monitor) render whatever this
// exposes and call its functions; nothing here is per-screen.
//
// mpv is launched *detached* and found again through its socket, so the
// plugin hot-reload the shell performs on every file save under
// ~/.config/omarchy/plugins/ (which destroys and recreates this service)
// leaves playback untouched — the new instance simply re-attaches.
//
// Bit-perfect rules (see README): no software volume, no filters, native
// sample rate/format, `--gapless-audio=weak`. In exclusive mode mpv opens the
// ALSA hw: device and PipeWire is asked to let go of the card first
// (bin/omarchy-flac-device release); shared mode plays through PipeWire.
Item {
  id: root

  // Injected by the shell (shell.qml ensureService).
  property var shell: null
  property var manifest: null

  // Pushed by the bar widget from its inline shell.json entry; the service
  // itself receives no settings from the shell.
  property var settings: ({})

  readonly property bool exclusive: !!(settings && settings.exclusive === true)
  readonly property string alsaDevice: (settings && settings.alsaDevice) || "alsa/hw:CARD=II,DEV=0"
  readonly property string pwDeviceName: (settings && settings.pwDeviceName) || "alsa_card.usb-Topping_E50_II-00"
  readonly property string pwSinkName: (settings && settings.pwSinkName) || ""
  readonly property string libraryDir: (settings && settings.libraryDir) || "/run/media/user/Downloads & Media/Music"
  readonly property string alsaCard: {
    var m = /CARD=([^,]+)/.exec(alsaDevice)
    return m ? m[1] : "II"
  }

  readonly property string deviceBin: Qt.resolvedUrl("bin/omarchy-flac-device").toString().replace(/^file:\/\//, "")
  readonly property string scanBin: Qt.resolvedUrl("bin/omarchy-flac-scan").toString().replace(/^file:\/\//, "")
  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-flac.sock"

  // ---- playback state mirrored from mpv ----
  property bool connected: false
  property bool paused: true
  property bool idle: true
  property real timePos: 0
  property real duration: 0
  property int playlistPos: -1
  property int playlistCount: 0
  // mpv's playlist as [{filename, current}], kept in sync via observe_property.
  property var playlist: []
  readonly property string nextPath: playlistPos >= 0 && playlistPos + 1 < playlist.length ? playlist[playlistPos + 1].filename : ""
  readonly property var nextTrack: {
    if (!nextPath) return null
    var hit = Model.findTrack(library, nextPath)
    return hit ? hit.track : { path: nextPath, title: nextPath.split("/").pop(), artist: "", album: "" }
  }
  property var metadata: ({})
  property var audioParams: null
  property string path: ""
  property string runningAudioDevice: ""
  readonly property bool runningExclusive: runningAudioDevice.indexOf("alsa/") === 0
  readonly property bool playing: connected && !idle && !paused
  // Only meaningful once mpv has told us which device it opened; comparing
  // against the empty initial value would "fix" a mismatch that isn't there.
  readonly property bool modeMismatch: connected && runningAudioDevice !== "" && ((exclusive && !runningExclusive) || (!exclusive && runningExclusive))

  // ---- device / library state ----
  property var deviceStatus: ({})
  property bool deviceReleased: false
  property bool deviceBusy: false
  property var library: null
  property bool scanning: false
  property string lastError: ""

  // Current track resolved from the library (title/artist/rate/bps), falling
  // back to mpv's own tags for files outside the library.
  readonly property var trackHit: Model.findTrack(library, path)
  readonly property string artPath: trackHit && trackHit.album && trackHit.album.art ? trackHit.album.art : ""
  readonly property var track: {
    var hit = trackHit
    if (hit) return hit.track
    if (!path) return null
    return {
      path: path,
      title: Model.tag(metadata, "title") || path.split("/").pop(),
      artist: Model.tag(metadata, "artist"),
      album: Model.tag(metadata, "album"),
      rate: audioParams ? audioParams.samplerate : 0,
      bps: 0,
      duration: duration
    }
  }
  readonly property string title: track ? (track.title || "") : ""
  readonly property string artist: track ? (track.artist || "") : ""
  readonly property string album: track ? (track.album || "") : ""

  // ---------------------------------------------------------------- settings
  function applySettings(next) {
    var before = JSON.stringify(settings || {})
    settings = next || {}
    if (JSON.stringify(settings) === before) return
    if (connected && modeMismatch) restartForMode()
  }

  function setExclusive(enabled) {
    var next = Object.assign({}, settings || {}, { exclusive: !!enabled })
    if (shell && typeof shell.updateEntryInline === "function") shell.updateEntryInline("user.flac", next)
    applySettings(next)
  }

  function toggleExclusive() { setExclusive(!exclusive) }

  // Exclusive mode needs a concrete hardware output: the panel asks which
  // one when the switch is turned on. `outputs` is refreshed on request.
  property var outputs: []
  property bool outputsLoading: false
  function listOutputs() {
    if (outputsProc.running) return
    outputsLoading = true
    outputsProc.running = true
  }
  Process {
    id: outputsProc
    command: [root.deviceBin, "outputs"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.outputsLoading = false
        try { root.outputs = JSON.parse(text) } catch (e) { root.outputs = [] }
      }
    }
    onExited: root.outputsLoading = false
  }
  function setExclusiveOutput(alsaDevice, pwDeviceName) {
    if (!alsaDevice) return
    var next = Object.assign({}, settings || {}, { exclusive: true, alsaDevice: alsaDevice, pwDeviceName: pwDeviceName || "" })
    if (shell && typeof shell.updateEntryInline === "function") shell.updateEntryInline("user.flac", next)
    applySettings(next)
  }

  // ------------------------------------------------------------------- mpv
  function mpvArgs(useExclusive) {
    var args = [
      "mpv",
      "--idle=yes", "--vid=no", "--audio-display=no", "--no-terminal",
      "--no-config", "--load-scripts=no",
      "--script=/usr/lib/mpv-mpris/mpris.so",
      "--input-ipc-server=" + socketPath,
      "--af=", "--volume=100", "--volume-max=100", "--volume-gain=0",
      "--replaygain=no", "--audio-pitch-correction=no", "--audio-normalize-downmix=no",
      "--audio-samplerate=0", "--audio-channels=auto-safe",
      "--gapless-audio=weak", "--prefetch-playlist=yes",
      "--force-media-title=", "--title=omarchy-flac"
    ]
    if (useExclusive) {
      args.push("--ao=alsa", "--audio-device=" + alsaDevice, "--alsa-resample=no", "--alsa-buffer-time=500000")
    } else {
      args.push("--ao=pipewire", "--audio-device=" + (pwSinkName ? "pipewire/" + pwSinkName : "pipewire"))
    }
    return args
  }

  property bool spawnRequested: false
  property int connectFailures: 0
  property var pendingResume: null

  // mpv runs as a transient systemd user unit rather than a child of the
  // shell: `omarchy restart shell` kills the shell's process tree, and the
  // player must outlive it (the new engine simply re-attaches).
  function spawnMpv() {
    if (spawnRequested) return
    spawnRequested = true
    connectFailures = 0
    var unit = "omarchy-flac-mpv"
    Quickshell.execDetached(["bash", "-c",
      "systemctl --user stop " + unit + " >/dev/null 2>&1; systemctl --user reset-failed " + unit + " >/dev/null 2>&1; "
      + "exec systemd-run --user --quiet --collect --unit=" + unit + " --description='Omarchy FLAC player (mpv)' \"$@\"",
      "omarchy-flac"].concat(mpvArgs(exclusive)))
    spawnGuard.restart()
  }

  Timer {
    id: spawnGuard
    interval: 4000
    onTriggered: root.spawnRequested = false
  }

  function send(cmd, requestId) {
    if (!socket || !socket.connected) return
    var msg = { command: cmd }
    if (requestId !== undefined) msg.request_id = requestId
    socket.write(JSON.stringify(msg) + "\n")
  }

  function observe() {
    var props = ["pause", "idle-active", "time-pos", "duration", "playlist-pos", "playlist-count", "metadata", "audio-params", "path", "audio-device", "playlist"]
    for (var i = 0; i < props.length; i++) send(["observe_property", i + 1, props[i]])
  }

  function handleMessage(msg) {
    if (msg.event === "property-change") {
      switch (msg.name) {
        case "pause": paused = msg.data !== false; break
        case "idle-active":
          idle = msg.data !== false
          if (idle) {
            path = ""; timePos = 0; duration = 0; audioParams = null; metadata = ({})
            if (deviceReleased && !pendingResume) restoreDevice()
          }
          break
        case "time-pos": if (typeof msg.data === "number") timePos = msg.data; break
        case "duration": if (typeof msg.data === "number") duration = msg.data; break
        case "playlist-pos": playlistPos = typeof msg.data === "number" ? msg.data : -1; break
        case "playlist-count": playlistCount = typeof msg.data === "number" ? msg.data : 0; break
        case "metadata": metadata = msg.data || ({}); break
        case "audio-params": audioParams = msg.data || null; break
        case "path": path = typeof msg.data === "string" ? msg.data : ""; break
        case "audio-device":
          runningAudioDevice = typeof msg.data === "string" ? msg.data : ""
          if (modeMismatch && !pendingResume) restartForMode()
          break
        case "playlist": playlist = Array.isArray(msg.data) ? msg.data : []; break
      }
      return
    }
    if (msg.event === "end-file" && msg.reason === "error") {
      lastError = "Playback failed" + (msg.file_error ? ": " + msg.file_error : "")
      return
    }
    if (msg.event === "file-loaded") {
      lastError = ""
      statusPoll.restart()
      return
    }
  }

  // A Socket that has failed to connect once will not try again when
  // `connected` is toggled, so every attempt gets a fresh object.
  property var socket: null

  function connectSocket() {
    if (socket) {
      if (socket.connected) return
      socket.destroy()
      socket = null
    }
    socket = socketComponent.createObject(root, { path: socketPath })
    socket.connected = true
  }

  Component {
    id: socketComponent
    Socket {
      id: sock
      parser: SplitParser {
        onRead: function(line) {
          if (!line) return
          var msg = null
          try { msg = JSON.parse(line) } catch (e) { return }
          root.handleMessage(msg)
          if (root.pendingResume && msg.request_id === 4242 && Array.isArray(msg.data)) {
            root.pendingResume.paths = msg.data.map(function(e) { return e.filename })
          }
        }
      }
      onConnectedChanged: {
        if (root.socket !== sock) return
        root.connected = connected
        if (connected) {
          root.connectFailures = 0
          root.spawnRequested = false
          root.observe()
          root.probeDevice()
          if (root.pendingResume) Qt.callLater(root.applyPendingResume)
        } else {
          root.idle = true
          root.path = ""
          root.runningAudioDevice = ""
          if (root.pendingResume) {
            // We asked mpv to quit for a mode switch: bring the new one up now.
            root.spawnRequested = false
            root.spawnMpv()
          } else if (root.deviceReleased) {
            root.restoreDevice()
          }
        }
      }
      onError: function(err) {
        if (root.socket !== sock) return
        root.connectFailures++
        // No socket yet (or a dead one): after a couple of misses, launch mpv.
        // mpv removes a stale socket file itself on start.
        if (root.connectFailures >= 2 && !root.spawnRequested) {
          root.checkStaleState()
          root.spawnMpv()
        }
      }
    }
  }

  Timer {
    id: reconnect
    interval: root.spawnRequested ? 250 : 1000
    running: !root.connected
    repeat: true
    onTriggered: root.connectSocket()
  }

  function restartForMode() {
    if (!connected) return
    pendingResume = {
      paths: [],
      index: playlistPos,
      pos: timePos,
      wasIdle: idle,
      paused: paused
    }
    // Fetch the playlist before quitting so the same queue continues.
    send(["get_property", "playlist"], 4242)
    quitAfterPlaylist.restart()
  }

  Timer {
    id: quitAfterPlaylist
    interval: 150
    onTriggered: {
      if (!root.pendingResume) return
      root.send(["quit"])
    }
  }

  function applyPendingResume() {
    var r = pendingResume
    pendingResume = null
    if (!r || r.wasIdle || !r.paths.length) {
      if (deviceReleased && !runningExclusive) restoreDevice()
      return
    }
    startQueue(r.paths, Math.max(0, r.index), r.pos, r.paused)
  }

  // ------------------------------------------------------------- transport
  // Load `paths` as the playlist and start at `index`. Album playback goes
  // through here so gapless spans the whole album.
  function startQueue(paths, index, seekTo, startPaused) {
    if (!paths || !paths.length) return
    var go = function() {
      // Load the chosen track first so nothing else ever touches the DAC,
      // then slot the earlier tracks in front of it and the rest behind.
      var start = Math.max(0, Math.min(paths.length - 1, index || 0))
      send(["set_property", "pause", !!startPaused])
      send(["loadfile", paths[start], "replace"])
      for (var i = 0; i < start; i++) send(["loadfile", paths[i], "insert-at", i])
      for (var j = start + 1; j < paths.length; j++) send(["loadfile", paths[j], "append"])
      if (seekTo && seekTo > 0.5) pendingSeek = seekTo
      lastError = ""
    }
    if (exclusive && !deviceReleased) releaseDevice(go)
    else if (!exclusive && deviceReleased) { restoreDevice(); go() }
    else go()
  }

  property real pendingSeek: 0
  onPathChanged: {
    if (connected && path) statusKick.restart()
    if (path && pendingSeek > 0) {
      var s = pendingSeek
      pendingSeek = 0
      seekTimer.pos = s
      seekTimer.restart()
    }
  }
  Timer {
    id: seekTimer
    property real pos: 0
    interval: 200
    onTriggered: root.send(["seek", pos, "absolute"])
  }

  function playAlbum(albumIndex, trackIndex) {
    if (!library || !library.albums[albumIndex]) return
    var paths = library.albums[albumIndex].tracks.map(function(t) { return t.path })
    startQueue(paths, trackIndex || 0, 0, false)
  }

  // Play an arbitrary ordered list (a search result, a genre, an artist…).
  function playPaths(paths, index) {
    if (!paths || !paths.length) return
    startQueue(paths, index || 0, 0, false)
  }

  // Shuffle: the queue itself is randomised up front (rather than mpv's
  // shuffle flag) so prev/next walk a stable order and the panel can show it.
  function shufflePaths(paths) {
    if (!paths || !paths.length) return
    startQueue(Model.shuffled(paths), 0, 0, false)
  }

  // ---- queue editing (the Playlist tab) ----
  // Append to the queue. `append-play` lets mpv decide whether to start (it
  // does only when nothing is playing), so this never trusts a possibly
  // stale idle flag; the DAC hand-off keys on deviceReleased instead.
  function enqueuePaths(paths) {
    if (!paths || !paths.length || !connected) return
    var wasIdle = idle && !path
    var go = function() {
      for (var i = 0; i < paths.length; i++) send(["loadfile", paths[i], "append-play"])
      // Only clear pause when this enqueue is what starts playback; a paused
      // track must stay paused when more music is appended behind it.
      if (wasIdle) send(["set_property", "pause", false])
    }
    if (exclusive && !deviceReleased) releaseDevice(go)
    else go()
  }
  function playQueueIndex(index) {
    if (!connected || index < 0 || index >= playlist.length) return
    var go = function() { send(["playlist-play-index", index]); send(["set_property", "pause", false]) }
    if (exclusive && !deviceReleased) releaseDevice(go)
    else go()
  }
  function removeQueueIndex(index) {
    if (!connected || index < 0 || index >= playlist.length) return
    send(["playlist-remove", index])
  }
  // Remove [start, end] inclusive; walk backwards so indices stay valid.
  function removeQueueRange(start, end) {
    if (!connected) return
    for (var i = Math.min(end, playlist.length - 1); i >= Math.max(0, start); i--) send(["playlist-remove", i])
  }
  function clearQueue() {
    if (!connected) return
    send(["stop"])          // drops the current file too; idle-active restores the DAC
    send(["playlist-clear"])
  }
  function shuffleQueue() {
    if (!connected || playlist.length < 2) return
    send(["playlist-shuffle"])
  }

  // Shuffle toggle: mpv keeps the pre-shuffle order, so turning it off
  // restores the original sequence (the current track keeps playing).
  property bool shuffleOn: false
  function setShuffle(on) {
    if (!connected) return
    if (on === shuffleOn) return
    shuffleOn = on
    if (playlist.length > 1) send([on ? "playlist-shuffle" : "playlist-unshuffle"])
  }
  function toggleShuffle() { setShuffle(!shuffleOn) }

  function shuffleAll() {
    if (!library) return
    var paths = []
    for (var a = 0; a < library.albums.length; a++)
      for (var t = 0; t < library.albums[a].tracks.length; t++) paths.push(library.albums[a].tracks[t].path)
    shufflePaths(paths)
  }

  function shuffleAlbum(albumIndex) {
    if (!library || !library.albums[albumIndex]) return
    shufflePaths(library.albums[albumIndex].tracks.map(function(t) { return t.path }))
  }

  function playPause() {
    if (!connected || idle) return
    send(["cycle", "pause"])
  }
  function play() { if (connected && !idle) send(["set_property", "pause", false]) }
  function pause() { if (connected && !idle) send(["set_property", "pause", true]) }
  function next() { if (connected && !idle) send(["playlist-next", "weak"]) }
  function previous() {
    if (!connected || idle) return
    // Like every CD player: within the first few seconds go to the previous
    // track, otherwise restart the current one.
    if (timePos > 3) send(["seek", 0, "absolute"])
    else send(["playlist-prev", "weak"])
  }
  // Stop = pause and rewind the current track; the playlist and the loaded
  // file stay put so Play resumes from the top of the same song. (Clearing
  // the queue is the Playlist tab's 🗑 action.)
  function stop() {
    if (!connected || idle) return
    send(["set_property", "pause", true])
    send(["seek", 0, "absolute"])
  }
  function seek(seconds, absolute) {
    if (!connected || idle) return
    send(["seek", seconds, absolute ? "absolute" : "relative"])
  }
  function seekFraction(fraction) {
    if (!connected || idle || !duration) return
    seek(Math.max(0, Math.min(duration, fraction * duration)), true)
  }

  // ---------------------------------------------------------------- device
  property var afterRelease: null

  function releaseDevice(then) {
    if (deviceBusy) { afterRelease = then; return }
    afterRelease = then || null
    deviceBusy = true
    deviceProc.command = [deviceBin, "release", pwDeviceName, alsaCard]
    deviceProc.mode = "release"
    deviceProc.running = true
  }

  function restoreDevice() {
    if (deviceBusy) return
    deviceBusy = true
    deviceProc.command = [deviceBin, "restore", pwDeviceName, alsaCard]
    deviceProc.mode = "restore"
    deviceProc.running = true
  }

  // A previous shell/mpv session that died mid-play leaves the profile off;
  // if no mpv is around to use the card, give it back to PipeWire.
  function checkStaleState() {
    if (!deviceReleased) {
      staleProc.command = [deviceBin, "status", pwDeviceName, alsaCard]
      staleProc.running = true
    }
  }

  Process {
    id: staleProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var st = JSON.parse(text)
          if (st.released && st.owner !== "mpv") root.restoreDevice()
        } catch (e) {}
      }
    }
  }

  Process {
    id: deviceProc
    property string mode: ""
    stdout: StdioCollector {
      id: deviceOut
      waitForEnd: true
    }
    onExited: function(code) {
      root.deviceBusy = false
      var st = null
      try { st = JSON.parse(deviceOut.text) } catch (e) {}
      if (st) root.deviceStatus = st
      if (mode === "release") {
        if (code === 0) {
          root.deviceReleased = true
          var cb = root.afterRelease
          root.afterRelease = null
          if (cb) cb()
        } else {
          root.lastError = "Could not release " + root.pwDeviceName + " from PipeWire"
          root.afterRelease = null
        }
      } else if (mode === "restore") {
        root.deviceReleased = false
        if (root.afterRelease) { var cb2 = root.afterRelease; root.afterRelease = null; root.releaseDevice(cb2) }
      }
    }
  }

  function probeDevice() {
    if (!statusProc.running) statusProc.running = true
  }

  Process {
    id: statusProc
    command: [root.deviceBin, "status", root.pwDeviceName, root.alsaCard]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var st = null
        try { st = JSON.parse(text) } catch (e) { return }
        root.deviceStatus = st
        // A fresh engine instance (shell restart, plugin reload) inherits a
        // release made by its predecessor: adopt it so the profile is given
        // back when playback ends — or right away if nothing is playing.
        if (st.released && !root.deviceBusy && !root.deviceReleased) {
          root.deviceReleased = true
          if (root.connected && root.idle && !root.pendingResume) root.restoreDevice()
        }
      }
    }
  }

  // A format change (new sample rate / bit depth) re-opens the device; read
  // hw_params again right after so the badge never lags behind the track.
  onAudioParamsChanged: if (connected && !idle) statusKick.restart()
  // mpv reports the new track before its audio reaches the device (decoder
  // runs ahead of the buffers), so probe a few times over the next seconds.
  Timer {
    id: statusKick
    property int shots: 0
    interval: 700
    repeat: true
    onRunningChanged: if (running) shots = 0
    onTriggered: {
      root.probeDevice()
      if (++shots >= 4) stop()
    }
  }

  Timer {
    id: statusPoll
    interval: root.playing ? 2000 : 6000
    running: root.connected && !root.idle
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeDevice()
  }

  // --------------------------------------------------------------- library
  property bool rescanPending: false
  function rescan(force) {
    // A directory change while a scan is in flight must not be dropped:
    // remember it and run again when the current scan finishes.
    if (scanProc.running) { rescanPending = true; return }
    scanning = true
    scanProc.command = force ? [scanBin, libraryDir, "--force"] : [scanBin, libraryDir]
    scanProc.running = true
  }

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.scanning = false
        try {
          root.library = JSON.parse(text)
          root.lastError = ""
        } catch (e) {
          root.lastError = "Library scan failed"
          console.warn("user.flac scan parse failed; output bytes", text.length)
        }
      }
    }
    stderr: StdioCollector {
      id: scanErr
      waitForEnd: true
    }
    onExited: function(code) {
      root.scanning = false
      if (code !== 0 || scanErr.text) console.warn("user.flac scan exit", code, "dir", root.libraryDir, "stderr:", scanErr.text.slice(0, 400))
      if (root.rescanPending) { root.rescanPending = false; root.rescan(false) }
    }
  }

  onLibraryDirChanged: rescan(false)

  function openLibraryFolder() {
    Quickshell.execDetached(["bash", "-lc", "xdg-open " + Model.shellQuote(libraryDir.replace(/^~/, Quickshell.env("HOME")))])
  }

  // Folder chooser for the library; the pick is persisted to shell.json
  // (the widget's inline entry) so it survives restarts, then rescanned.
  property bool pickingLibrary: false
  function selectLibraryDir() {
    if (pickerProc.running) return
    pickingLibrary = true
    var start = libraryDir.replace(/^~/, Quickshell.env("HOME"))
    pickerProc.command = ["zenity", "--file-selection", "--directory", "--title=Select music library folder", "--filename=" + start + "/"]
    pickerProc.running = true
  }
  function setLibraryDir(dir) {
    dir = String(dir || "").trim()
    if (!dir) return
    var next = Object.assign({}, settings || {}, { libraryDir: dir })
    if (shell && typeof shell.updateEntryInline === "function") shell.updateEntryInline("user.flac", next)
    applySettings(next)   // onLibraryDirChanged → rescan
  }
  Process {
    id: pickerProc
    stdout: StdioCollector {
      id: pickerOut
      waitForEnd: true
    }
    onExited: function(code) {
      root.pickingLibrary = false
      if (code === 0) root.setLibraryDir(pickerOut.text.split("\n")[0])
    }
  }

  function statusJson() {
    return JSON.stringify({
      connected: connected, idle: idle, paused: paused, playing: playing,
      exclusive: exclusive, runningExclusive: runningExclusive,
      path: path, title: title, artist: artist, album: album,
      timePos: timePos, duration: duration,
      playlistPos: playlistPos, playlistCount: playlistCount,
      libraryDir: libraryDir, albums: library ? library.albums.length : 0, tracks: library ? library.count : 0, scanning: scanning,
      nextPath: nextPath, nextTitle: nextTrack ? nextTrack.title : "", shuffle: shuffleOn,
      device: deviceStatus, bitPerfect: track ? Model.bitPerfect(deviceStatus, track.rate, track.bps) : false,
      error: lastError
    })
  }

  IpcHandler {
    target: "user.flac"

    function ping(): string { return root.connected ? "ok" : "no-engine" }
    function status(): string { return root.statusJson() }
    function playPause(): string { root.playPause(); return "ok" }
    function play(): string { root.play(); return "ok" }
    function pause(): string { root.pause(); return "ok" }
    function next(): string { root.next(); return "ok" }
    function prev(): string { root.previous(); return "ok" }
    function previous(): string { root.previous(); return "ok" }
    function stop(): string { root.stop(); return "ok" }
    function seek(seconds: string): string { root.seek(Number(seconds), false); return "ok" }
    function setExclusive(enabled: string): string { root.setExclusive(enabled === "true" || enabled === "1" || enabled === "on"); return "ok" }
    function toggleExclusive(): string { root.toggleExclusive(); return root.exclusive ? "exclusive" : "shared" }
    function outputs(): string { return JSON.stringify(root.outputs) }
    function setExclusiveOutput(alsaDevice: string, pwDeviceName: string): string { root.setExclusiveOutput(alsaDevice, pwDeviceName); return "ok" }
    function rescan(): string { root.rescan(true); return "ok" }
    function selectLibrary(): string { root.selectLibraryDir(); return "ok" }
    function setLibraryDir(dir: string): string { root.setLibraryDir(dir); return "ok" }
    function playAlbum(albumIndex: string, trackIndex: string): string { root.playAlbum(Number(albumIndex), Number(trackIndex)); return "ok" }
    function shuffleAll(): string { root.shuffleAll(); return "ok" }
    function enqueueAlbum(albumIndex: string): string {
      var a = root.library ? root.library.albums[Number(albumIndex)] : null
      if (!a) return "no such album"
      root.enqueuePaths(a.tracks.map(function(t) { return t.path })); return "ok"
    }
    function clearQueue(): string { root.clearQueue(); return "ok" }
    function shuffleQueue(): string { root.shuffleQueue(); return "ok" }
    function toggleShuffle(): string { root.toggleShuffle(); return root.shuffleOn ? "on" : "off" }
    function queue(): string { return JSON.stringify(root.playlist.map(function(e) { return e.filename })) }
    function shuffleAlbum(albumIndex: string): string { root.shuffleAlbum(Number(albumIndex)); return "ok" }
  }

  Component.onDestruction: { if (FlacRegistry.engine === root) FlacRegistry.engine = null }
  Component.onCompleted: {
    FlacRegistry.engine = root
    connectSocket()
    rescan(false)
  }
}
