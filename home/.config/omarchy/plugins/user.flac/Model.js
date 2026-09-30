.pragma library

// Pure helpers shared by Engine.qml and Player.qml. No QML state lives here.

var MUSIC_ICON = "\u{F0759}"      // nf-md-music_note
var DISC_ICON = "\u{F0025}"       // nf-md-album (vinyl record)
var PLAY_ICON = "\u{F040A}"       // nf-md-play
var PAUSE_ICON = "\u{F03E4}"      // nf-md-pause
var PREV_ICON = "\u{F04AE}"       // nf-md-skip_previous
var NEXT_ICON = "\u{F04AD}"       // nf-md-skip_next
var STOP_ICON = "\u{F04DB}"       // nf-md-stop
var REFRESH_ICON = "\u{F0450}"    // nf-md-refresh
var FOLDER_ICON = "\u{F024B}"     // nf-md-folder
var ALBUM_ICON = "\u{F0025}"      // nf-md-album

function formatTime(seconds) {
  if (seconds === null || seconds === undefined || isNaN(seconds) || seconds < 0) return "0:00"
  var s = Math.floor(seconds)
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  var mm = h > 0 ? (m < 10 ? "0" + m : "" + m) : "" + m
  var ss = r < 10 ? "0" + r : "" + r
  return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
}

function formatRate(rate) {
  if (!rate) return ""
  var k = rate / 1000
  return (Math.round(k * 10) / 10).toString().replace(/\.0$/, "") + " kHz"
}

function formatFormat(rate, bps) {
  var parts = []
  if (rate) parts.push(formatRate(rate))
  if (bps) parts.push(bps + "-bit")
  return parts.join(" · ")
}

var SHUFFLE_ICON = "\u{F049D}"    // nf-md-shuffle
var SEARCH_ICON = "\u{F0349}"     // nf-md-magnify
var CHEVRON_RIGHT_ICON = "\u{F0142}"  // nf-md-chevron_right
var CHEVRON_DOWN_ICON = "\u{F0140}"   // nf-md-chevron_down
var PLUS_ICON = "\u{F0415}"           // nf-md-plus
var REMOVE_ICON = "\u{F0156}"         // nf-md-close
var CLEAR_ICON = "\u{F0A7A}"          // nf-md-delete_sweep
var QUEUE_ICON = "\u{F0CB8}"          // nf-md-playlist_music
var SORT_AZ_ICON = "\u{F04BA}"        // nf-md-sort_alphabetical_variant
var SORT_COUNT_ICON = "\u{F04BB}"     // nf-md-sort_numeric_variant

var GROUPS = [
  { key: "album", label: "Album" },
  { key: "genre", label: "Genre" },
  { key: "albumartist", label: "Artist" }
]

function trackMatchesQuery(t, album, terms) {
  if (!terms.length) return true
  var hay = [t.title, t.artist, t.album, album.albumartist, t.genre, String(t.year || "")].join("\n").toLowerCase()
  for (var i = 0; i < terms.length; i++) if (hay.indexOf(terms[i]) === -1) return false
  return true
}

// Build the flat row list the panel's ListView renders: optional level-0
// group headers (genre / album artist), album headers, then tracks. Every
// header row carries `paths` (its tracks in order) so Enter plays the group
// and the shuffle action can shuffle exactly that scope. Search terms are
// AND-ed and matched case-insensitively against title/artist/album/album
// artist/genre/year; a header appears only when it still has matching tracks.
function buildRows(library, opts) {
  var rows = []
  if (!library || !Array.isArray(library.albums)) return rows
  opts = opts || {}
  var group = opts.group || "album"
  var terms = String(opts.query || "").toLowerCase().split(/\s+/).filter(function(x) { return !!x })
  // Albums are collapsed by default; a search expands everything so matches
  // are visible without clicking through.
  var expandedSet = opts.expanded || {}
  var expandedGroups = opts.expandedGroups || {}
  var closingSet = opts.closing || {}
  var openingSet = opts.opening || {}
  var expandAll = terms.length > 0

  // Collect matched albums with their matched tracks, keyed by group.
  var groups = {}
  var order = []
  for (var a = 0; a < library.albums.length; a++) {
    var album = library.albums[a]
    var tracks = []
    for (var t = 0; t < album.tracks.length; t++) {
      var tr = album.tracks[t]
      if (trackMatchesQuery(tr, album, terms)) tracks.push({ track: tr, trackIndex: t })
    }
    if (!tracks.length) continue
    var gkeys
    if (group === "genre") {
      // An album can carry several genres across its tracks; file it under each.
      var seen = {}
      gkeys = []
      for (var g = 0; g < tracks.length; g++) {
        var gn = tracks[g].track.genre || "Unknown genre"
        if (!seen[gn]) { seen[gn] = true; gkeys.push(gn) }
      }
    } else if (group === "albumartist") {
      gkeys = [album.albumartist || "Unknown artist"]
    } else {
      gkeys = [""]
    }
    for (var k = 0; k < gkeys.length; k++) {
      var key = gkeys[k]
      if (!groups[key]) { groups[key] = []; order.push(key) }
      var subset = group === "genre"
        ? tracks.filter(function(x) { return (x.track.genre || "Unknown genre") === key })
        : tracks
      groups[key].push({ album: album, albumIndex: a, tracks: subset })
    }
  }
  if (group !== "album") {
    var byName = function(x, y) { return x.toLowerCase() < y.toLowerCase() ? -1 : (x.toLowerCase() > y.toLowerCase() ? 1 : 0) }
    if (opts.sort === "count") {
      // Most tracks first; ties alphabetical.
      var totals = {}
      for (var gk in groups) {
        var n = 0
        for (var e = 0; e < groups[gk].length; e++) n += groups[gk][e].tracks.length
        totals[gk] = n
      }
      order.sort(function(x, y) { return totals[y] - totals[x] || byName(x, y) })
    } else {
      order.sort(byName)
    }
  }

  for (var o = 0; o < order.length; o++) {
    var key2 = order[o]
    var albums = groups[key2]
    var groupPaths = []
    var groupRowIndex = -1
    // Genre / artist groups are collapsed by default: the list is just the
    // group names until one is opened. A search opens everything.
    var groupKey = "g:" + key2
    var groupOpen = true, groupClosing = false, groupOpening = false
    if (group !== "album") {
      groupOpen = expandAll || !!expandedGroups[groupKey]
      groupClosing = !groupOpen && !!closingSet[groupKey]
      groupOpening = groupOpen && !!openingSet[groupKey]
      groupRowIndex = rows.length
      rows.push({ type: "group", rowKey: groupKey, key: groupKey, expanded: groupOpen, title: key2, subtitle: "", meta: "", paths: [], albumIndex: -1, trackIndex: 0, path: "" })
    }
    var showAlbums = groupOpen || groupClosing
    var groupTracks = 0
    for (var i = 0; i < albums.length; i++) {
      var entry = albums[i]
      var paths = entry.tracks.map(function(x) { return x.track.path })
      groupPaths = groupPaths.concat(paths)
      groupTracks += paths.length
      var albumKey = entry.album.key || String(entry.albumIndex)
      var expanded = expandAll || !!expandedSet[albumKey]
      // A closing album keeps its rows briefly so they can slide away.
      var closing = !expanded && !!closingSet[albumKey]
      var opening = expanded && !!openingSet[albumKey]
      var showTracks = expanded || closing
      if (!showAlbums) continue
      rows.push({
        type: "album",
        rowKey: "a:" + (group !== "album" ? key2 + "/" : "") + albumKey,
        key: albumKey,
        expanded: expanded,
        closing: groupClosing,
        opening: groupOpening,
        art: entry.album.art || "",
        albumIndex: entry.albumIndex,
        trackIndex: entry.tracks[0].trackIndex,
        title: entry.album.album || "Unknown album",
        subtitle: [group === "albumartist" ? "" : entry.album.albumartist, entry.album.year].filter(function(x) { return !!x }).join(" · "),
        path: "",
        paths: paths,
        meta: paths.length + (paths.length === 1 ? " track" : " tracks")
      })
      for (var j = 0; showTracks && j < entry.tracks.length; j++) {
        var tr2 = entry.tracks[j].track
        rows.push({
          type: "track",
          rowKey: "t:" + (group !== "album" ? key2 + "/" : "") + tr2.path,
          closing: closing || groupClosing,
          opening: opening || groupOpening,
          albumIndex: entry.albumIndex,
          trackIndex: entry.tracks[j].trackIndex,
          number: tr2.track,
          title: tr2.title,
          subtitle: tr2.artist && tr2.artist !== entry.album.albumartist ? tr2.artist : "",
          path: tr2.path,
          paths: paths,
          meta: formatFormat(tr2.rate, tr2.bps),
          duration: tr2.duration,
          rate: tr2.rate,
          bps: tr2.bps
        })
      }
    }
    if (groupRowIndex >= 0) {
      rows[groupRowIndex].paths = groupPaths
      rows[groupRowIndex].meta = albums.length + (albums.length === 1 ? " album · " : " albums · ") + groupTracks + " tracks"
    }
  }
  return rows
}

// Every track in the current view, including those inside collapsed albums
// and collapsed groups.
function allPaths(rows) {
  var out = []
  var hasGroups = rows.length > 0 && rows[0].type === "group"
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (hasGroups ? r.type === "group" : r.type === "album") out = out.concat(r.paths)
  }
  return out
}

// The row to highlight for the playing file: the track row when visible,
// otherwise its (collapsed) album row.
function rowIndexForPath(rows, path) {
  if (!path) return -1
  var albumRow = -1
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (r.type === "track" && r.path === path) return i
    if (r.type === "album" && albumRow < 0 && r.paths.indexOf(path) !== -1) albumRow = i
  }
  return albumRow
}

function shuffled(list) {
  var a = list.slice()
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1))
    var tmp = a[i]; a[i] = a[j]; a[j] = tmp
  }
  return a
}

// path → {album, track, albumIndex, trackIndex}, built once per library object
// so an 11k-entry queue does not cost 11k linear scans.
var _indexFor = null
var _index = null
function pathIndex(library) {
  if (!library || !Array.isArray(library.albums)) return {}
  if (_indexFor === library && _index) return _index
  var idx = {}
  for (var a = 0; a < library.albums.length; a++) {
    var tracks = library.albums[a].tracks
    for (var t = 0; t < tracks.length; t++) {
      idx[tracks[t].path] = { album: library.albums[a], track: tracks[t], albumIndex: a, trackIndex: t }
    }
  }
  _indexFor = library
  _index = idx
  return idx
}

function findTrack(library, path) {
  if (!library || !path) return null
  return pathIndex(library)[path] || null
}

// Rows for the Playlist tab: mpv's playlist order, with consecutive entries
// from one album folded under an album header (collapsed unless opened or
// holding the current track). Header rows carry queueStart/queueEnd.
function queueRows(library, playlist, currentPos, expandedSet, closingSet, openingSet) {
  var rows = []
  if (!Array.isArray(playlist) || !playlist.length) return rows
  expandedSet = expandedSet || {}
  closingSet = closingSet || {}
  openingSet = openingSet || {}
  var idx = pathIndex(library)
  var i = 0
  while (i < playlist.length) {
    var fn = playlist[i].filename || ""
    var hit = idx[fn]
    var albumKey = hit ? (hit.album.key || String(hit.albumIndex)) : ("dir:" + fn.substring(0, fn.lastIndexOf("/")))
    var j = i
    while (j + 1 < playlist.length) {
      var fn2 = playlist[j + 1].filename || ""
      var hit2 = idx[fn2]
      var key2 = hit2 ? (hit2.album.key || String(hit2.albumIndex)) : ("dir:" + fn2.substring(0, fn2.lastIndexOf("/")))
      if (key2 !== albumKey) break
      j++
    }
    var rowKey = "q" + i + ":" + albumKey
    var containsCurrent = currentPos >= i && currentPos <= j
    var expanded = expandedSet[rowKey] !== undefined ? !!expandedSet[rowKey] : containsCurrent
    var closing = !expanded && !!closingSet[rowKey]
    var opening = expanded && !!openingSet[rowKey]
    var album = hit ? hit.album : null
    rows.push({
      type: "queueAlbum",
      rowKey: "qa:" + rowKey,
      key: rowKey,
      expanded: expanded,
      art: album && album.art ? album.art : "",
      title: album ? (album.album || "Unknown album") : fn.substring(fn.lastIndexOf("/") + 1),
      subtitle: album ? [album.albumartist, album.year].filter(function(x) { return !!x }).join(" · ") : "",
      meta: (j - i + 1) + (j === i ? " track" : " tracks"),
      queueStart: i,
      queueEnd: j,
      queueIndex: i,
      path: "",
      current: containsCurrent
    })
    for (var q = i; (expanded || closing) && q <= j; q++) {
      var f = playlist[q].filename || ""
      var h = idx[f]
      var tr = h ? h.track : null
      rows.push({
        type: "queue",
        rowKey: "q:" + q + ":" + f,
        closing: closing,
        opening: opening,
        queueIndex: q,
        path: f,
        title: tr ? tr.title : f.split("/").pop(),
        subtitle: tr && tr.artist && album && tr.artist !== album.albumartist ? tr.artist : "",
        meta: tr ? formatFormat(tr.rate, tr.bps) : "",
        duration: tr ? tr.duration : 0,
        art: "",
        current: q === currentPos,
        number: q + 1
      })
    }
    i = j + 1
  }
  return rows
}

// Row to highlight for the playing queue position: its track row when the
// album is open, otherwise the album header.
function queueRowForPos(rows, pos) {
  if (pos < 0) return -1
  var header = -1
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (r.type === "queue" && r.queueIndex === pos) return i
    if (r.type === "queueAlbum" && header < 0 && pos >= r.queueStart && pos <= r.queueEnd) header = i
  }
  return header
}

// mpv's `metadata` property keeps the container's tag case; look a key up
// case-insensitively so ffmpeg-written lowercase tags and metaflac-written
// uppercase tags both resolve.
function tag(metadata, key) {
  if (!metadata) return ""
  var lower = key.toLowerCase()
  for (var k in metadata) if (k.toLowerCase() === lower) return String(metadata[k])
  return ""
}

function bitsFromFormat(fmt) {
  if (!fmt) return 0
  var m = /^[SUF](\d+)/.exec(fmt)
  return m ? Number(m[1]) : 0
}

// Bit-perfect test for exclusive mode: mpv owns the hardware PCM, the device
// runs at the file's sample rate, and the container is at least as wide as the
// source samples (a 16- or 24-bit stream in a 32-bit slot is zero-padded,
// which is lossless — an exact format string match would be wrong here).
function bitPerfect(status, rate, bps) {
  if (!status || status.owner !== "mpv") return false
  if (!rate || Number(status.rate) !== Number(rate)) return false
  var bits = Number(status.bits) || bitsFromFormat(status.format)
  return bits >= (Number(bps) || 0)
}

function modeBadge(engine, track) {
  // Returns { text, state } where state is "good" | "bad" | "neutral" | "warn".
  if (!engine) return { text: "engine offline", state: "bad" }
  var fmt = ""
  if (track) fmt = formatFormat(track.rate, track.bps)
  else if (engine.audioParams) fmt = formatFormat(engine.audioParams.samplerate, 0)
  if (engine.idle || !engine.path) {
    return { text: engine.exclusive ? "exclusive · idle" : "shared · idle", state: "neutral" }
  }
  if (engine.runningExclusive) {
    var ok = track ? bitPerfect(engine.deviceStatus, track.rate, track.bps) : (engine.deviceStatus && engine.deviceStatus.owner === "mpv")
    if (engine.deviceStatus && engine.deviceStatus.owner === "") return { text: "exclusive · " + fmt, state: "neutral" }
    return { text: (ok ? "bit-perfect · " : "NOT bit-perfect · ") + fmt + (engine.deviceStatus && engine.deviceStatus.rate ? " → " + formatRate(engine.deviceStatus.rate) : ""), state: ok ? "good" : "bad" }
  }
  var graph = engine.deviceStatus ? Number(engine.deviceStatus.graphRate) : 0
  if (track && graph && graph !== Number(track.rate)) {
    return { text: "shared · " + fmt + " → resampled to " + formatRate(graph), state: "warn" }
  }
  return { text: "shared · via PipeWire · " + fmt, state: "neutral" }
}

function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}
