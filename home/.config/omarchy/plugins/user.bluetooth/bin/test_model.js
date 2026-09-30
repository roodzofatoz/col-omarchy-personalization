// Unit tests for the codec helpers in Model.js. Run: node bin/test_model.js
const assert = require("node:assert/strict")
const path = require("node:path")
const M = require(path.join(__dirname, "..", "Model.js"))

const status = M.parseCodecStatus(JSON.stringify({
  address: "40:ED:98:1A:C5:29", card: "bluez_card.40_ED_98_1A_C5_29", active: "aptx", activeName: "6",
  activeLabel: "aptX", hasQuality: false, qualityLabel: "",
  codecs: [
    { name: "8", label: "LDAC", id: "ldac", hires: true, rank: 100 },
    { name: "6", label: "aptX", id: "aptx", hires: false, rank: 50 },
    { name: "1", label: "SBC", id: "sbc", hires: false, rank: 10 }
  ]
}))
assert.ok(status, "status parses")
assert.equal(M.parseCodecStatus(""), null)
assert.equal(M.parseCodecStatus("not json"), null)
assert.equal(M.parseCodecStatus(JSON.stringify({ address: "x", card: null, error: "no-card" })), null, "no card -> null")

assert.equal(M.bestHiResCodec(status.codecs).id, "ldac")
assert.equal(M.bestHiResCodec([{ id: "sbc", hires: false }]), null)
assert.equal(M.hiResAvailable(status), true)
assert.equal(M.hiResAvailable(Object.assign({}, status, { active: "ldac" })), false)

assert.equal(M.nextCodec(status.codecs, "6").name, "1")
assert.equal(M.nextCodec(status.codecs, "1").name, "8", "wraps")
assert.equal(M.nextCodec(status.codecs, "").name, "8", "no active -> first")
assert.equal(M.nextCodec([{ name: "1" }], "1"), null, "single codec -> null")

assert.equal(M.codecSummary(status), "aptX")
assert.equal(M.codecSummary({ activeLabel: "LDAC", active: "ldac", qualityLabel: "hq" }), "LDAC HQ")
assert.equal(M.codecSummary({ activeLabel: "LDAC", active: "ldac", qualityLabel: "auto" }), "LDAC")
assert.equal(M.codecSummary(null), "")

assert.equal(M.nextLdacQuality("auto"), "hq")
assert.equal(M.nextLdacQuality("mq"), "auto")
assert.equal(M.nextLdacQuality(""), "auto")
assert.deepEqual(M.ldacQualityOptions().map(o => o.value), ["auto", "hq", "sq", "mq"])

assert.equal(M.pendingSettled("codec:8", status), false)
assert.equal(M.pendingSettled("codec:6", status), true)
assert.equal(M.pendingSettled("quality:hq", { qualityLabel: "hq" }), true)
assert.equal(M.pendingSettled("quality:hq", { qualityLabel: "auto" }), false)
assert.equal(M.pendingSettled("", null), true)

assert.equal(M.codecChipLabel(status.codecs[0]), "LDAC ✦")
assert.equal(M.codecChipLabel(status.codecs[1]), "aptX")
assert.match(M.codecTooltip(status.codecs[0]), /990 kbps.*hi-res/)
assert.equal(M.isHiResCodec("aptx_hd"), true)
assert.equal(M.isHiResCodec("sbc"), false)

// Stock helpers still intact after the patch.
assert.equal(M.deviceLabel({ name: " Buds " }), "Buds")
assert.equal(M.hasHumanName({ name: "00:11:22:33:44:55" }), false)

console.log("test_model.js: all assertions passed")
