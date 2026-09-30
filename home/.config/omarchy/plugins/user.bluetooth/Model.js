function deviceLabel(device) {
  if (!device) return ""
  return String(device.deviceName || device.name || "").trim()
}

function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()

  var length = Number(values.length || 0)
  if (!isFinite(length) || length <= 0) return []

  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

function isUuidLike(value) {
  var text = String(value || "").trim()
  if (text === "") return false
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
    || /^[0-9a-f]{32}$/i.test(text)
    || /^0x[0-9a-f]{4,32}$/i.test(text)
    || /^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$/i.test(text)
}

function isAddressLike(value) {
  var text = String(value || "").trim()
  return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)
}

function normalizedAddress(value) {
  return String(value || "").trim().toLowerCase().replace(/[^0-9a-f]/g, "")
}

function hasHumanName(device) {
  var label = deviceLabel(device)
  return label !== "" && !isUuidLike(label) && !isAddressLike(label)
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function nodeText(node) {
  var props = nodeProps(node)
  return [
    node ? node.name : "",
    node ? node.description : "",
    node ? node.nickname : "",
    node ? node.nick : "",
    props["node.name"],
    props["node.description"],
    props["node.nick"],
    props["device.name"],
    props["device.description"],
    props["device.product.name"],
    props["device.alias"],
    props["device.string"],
    props["api.bluez5.address"],
    props["bluez5.address"],
    props["media.name"]
  ].join(" ").toLowerCase()
}

function bluetoothSinkMatchesDevice(node, device) {
  if (!node || !node.isSink || node.isStream || !device) return false

  var address = normalizedAddress(device.address)
  var text = nodeText(node)
  if (address !== "" && normalizedAddress(text).indexOf(address) !== -1) return true

  var label = deviceLabel(device).toLowerCase()
  return label !== "" && text.indexOf(label) !== -1
}

function sortedByLabel(devices) {
  var list = toArray(devices)
  list.sort(function(a, b) { return deviceLabel(a).localeCompare(deviceLabel(b)) })
  return list
}

// Primitives-only projection of a BlueZ device for list-model rows. Holding
// the Device QObject in model data puts a live wrapper into every delegate's
// var property, and BlueZ churn (discovery timeouts, unpair) can destroy the
// object while a delegate is still incubating, which segfaults quickshell.
// Actions resolve the backend object via Panel.deviceFor().
function deviceRow(d) {
  if (!d) return null
  return {
    address: d.address || "",
    name: d.name || "",
    deviceName: d.deviceName || "",
    connected: !!d.connected,
    state: d.state !== undefined ? d.state : -1,
    batteryAvailable: !!d.batteryAvailable,
    battery: d.battery !== undefined ? d.battery : 0,
    pairing: !!d.pairing
  }
}

function deviceLists(devices) {
  var values = toArray(devices)
  var connected = []
  var known = []
  var discovered = []

  for (var i = 0; i < values.length; i++) {
    var d = values[i]
    if (!d || !hasHumanName(d)) continue
    if (d.connected) connected.push(d)
    else if (d.paired || d.bonded || d.trusted) known.push(d)
    else discovered.push(d)
  }

  return {
    connected: sortedByLabel(connected),
    known: sortedByLabel(known),
    discovered: sortedByLabel(discovered)
  }
}

function cloneMap(map) {
  var next = ({})
  for (var key in map || {}) next[key] = map[key]
  return next
}

function pendingAction(actions, address) {
  return address && actions && actions[address] ? actions[address] : ""
}

function withPendingAction(actions, address, action) {
  var next = cloneMap(actions)
  if (!address) return next
  if (action) next[address] = action
  else delete next[address]
  return next
}

function visibleSections(lists, discovering) {
  var sections = []
  if (lists && lists.connected && lists.connected.length > 0) sections.push("connected")
  if (lists && lists.known && lists.known.length > 0) sections.push("known")
  if (discovering && lists && lists.discovered && lists.discovered.length > 0) sections.push("discovered")
  return sections
}

function sectionDevices(lists, section) {
  if (!lists) return []
  if (section === "connected") return lists.connected || []
  if (section === "known") return lists.known || []
  if (section === "discovered") return lists.discovered || []
  return []
}

// ---------- Hi-res codec support (user.bluetooth) ----------
// Status objects come from bin/omarchy-bluetooth-codec as JSON; these helpers
// keep the QML side declarative and are unit-tested with node (see
// bin/test_model.js).

var LDAC_QUALITIES = [
  { value: "auto", label: "Auto", tooltip: "LDAC adaptive bitrate (PipeWire default)" },
  { value: "hq", label: "HQ", tooltip: "LDAC high quality, 990/909 kbps" },
  { value: "sq", label: "SQ", tooltip: "LDAC standard quality, 660/606 kbps" },
  { value: "mq", label: "MQ", tooltip: "LDAC mobile quality, 330/303 kbps" }
]

var CODEC_NOTES = {
  ldac: "Sony LDAC, up to 990 kbps, 24-bit/96 kHz",
  aptx_hd: "Qualcomm aptX HD, 576 kbps, 24-bit/48 kHz",
  aptx_ad: "Qualcomm aptX Adaptive, up to 420 kbps, 24-bit/96 kHz",
  lc3plus_hr: "LC3plus HR, 24-bit/96 kHz",
  opus_05_pro: "Opus Pro Audio, high bitrate",
  opus_05: "Opus (PipeWire)",
  opus_g: "Opus (Google)",
  aptx: "Qualcomm aptX, 352 kbps, 16-bit/48 kHz",
  aac: "AAC, ~256 kbps",
  sbc_xq: "SBC-XQ, ~552 kbps",
  sbc: "SBC, ~328 kbps (baseline)",
  aptx_ll: "aptX Low Latency",
  faststream: "FastStream (low latency)"
}

function parseCodecStatus(text) {
  var raw = String(text || "").trim()
  if (raw === "") return null
  var obj
  try { obj = JSON.parse(raw) } catch (e) { return null }
  if (!obj || typeof obj !== "object" || !obj.card) return null
  if (!Array.isArray(obj.codecs)) obj.codecs = []
  return obj
}

function isHiResCodec(id) {
  var key = String(id || "")
  return key === "ldac" || key === "aptx_hd" || key === "aptx_ad" || key === "lc3plus_hr" || key === "opus_05_pro"
}

function bestHiResCodec(codecs) {
  var list = toArray(codecs)
  var best = null
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!c || !c.hires) continue
    if (!best || Number(c.rank || 0) > Number(best.rank || 0)) best = c
  }
  return best
}

function codecTooltip(codec) {
  if (!codec) return ""
  var note = CODEC_NOTES[String(codec.id || "")]
  var label = String(codec.label || codec.id || "")
  var text = note ? note : label
  return codec.hires ? text + " — hi-res" : text
}

function codecChipLabel(codec) {
  if (!codec) return ""
  var label = String(codec.label || codec.id || "")
  return codec.hires ? label + " ✦" : label
}

// The codec after `activeName` in list order, wrapping; the first entry when
// nothing is active. null for lists that offer no alternative.
function nextCodec(codecs, activeName) {
  var list = toArray(codecs)
  if (list.length < 2) return null
  var idx = -1
  for (var i = 0; i < list.length; i++) {
    if (list[i] && String(list[i].name) === String(activeName)) { idx = i; break }
  }
  return list[(idx + 1) % list.length]
}

function ldacQualityOptions() {
  return LDAC_QUALITIES.slice()
}

function nextLdacQuality(label) {
  var idx = -1
  for (var i = 0; i < LDAC_QUALITIES.length; i++) {
    if (LDAC_QUALITIES[i].value === String(label || "")) { idx = i; break }
  }
  return LDAC_QUALITIES[(idx + 1) % LDAC_QUALITIES.length].value
}

// Pending markers are "codec:<name>" or "quality:<label>"; settled once the
// helper's status reflects the request.
function pendingSettled(pending, status) {
  var text = String(pending || "")
  if (text === "" || !status) return true
  if (text.indexOf("codec:") === 0) return String(status.activeName || "") === text.substring(6)
  if (text.indexOf("quality:") === 0) return String(status.qualityLabel || "") === text.substring(8)
  return true
}

// One-line codec summary for a connected row: "LDAC", "LDAC HQ", "aptX", "".
function codecSummary(status) {
  if (!status || !status.activeLabel) return ""
  var text = String(status.activeLabel)
  if (status.active === "ldac" && status.qualityLabel && status.qualityLabel !== "auto")
    text += " " + String(status.qualityLabel).toUpperCase()
  return text
}

// Whether a connected device offers a hi-res codec it is not currently using.
function hiResAvailable(status) {
  if (!status) return false
  var best = bestHiResCodec(status.codecs)
  return !!best && best.id !== status.active
}

if (typeof module !== "undefined") {
  module.exports = {
    deviceLabel: deviceLabel,
    toArray: toArray,
    isUuidLike: isUuidLike,
    isAddressLike: isAddressLike,
    normalizedAddress: normalizedAddress,
    hasHumanName: hasHumanName,
    nodeProps: nodeProps,
    nodeText: nodeText,
    bluetoothSinkMatchesDevice: bluetoothSinkMatchesDevice,
    sortedByLabel: sortedByLabel,
    deviceRow: deviceRow,
    deviceLists: deviceLists,
    cloneMap: cloneMap,
    pendingAction: pendingAction,
    withPendingAction: withPendingAction,
    visibleSections: visibleSections,
    sectionDevices: sectionDevices,
    parseCodecStatus: parseCodecStatus,
    isHiResCodec: isHiResCodec,
    bestHiResCodec: bestHiResCodec,
    codecTooltip: codecTooltip,
    codecChipLabel: codecChipLabel,
    nextCodec: nextCodec,
    ldacQualityOptions: ldacQualityOptions,
    nextLdacQuality: nextLdacQuality,
    pendingSettled: pendingSettled,
    codecSummary: codecSummary,
    hiResAvailable: hiResAvailable
  }
}
