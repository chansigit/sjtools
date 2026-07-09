import Foundation

// Minimal assertion harness (old CLT has no usable XCTest for standalone builds)
var failures = 0
var passes = 0

func expectEq<T: Equatable>(_ got: T, _ want: T, _ label: String, file: String = #file, line: Int = #line) {
    if got == want {
        passes += 1
    } else {
        failures += 1
        print("FAIL [\(label)] line \(line): got \(got), want \(want)")
    }
}

func expectTrue(_ cond: Bool, _ label: String, file: String = #file, line: Int = #line) {
    if cond {
        passes += 1
    } else {
        failures += 1
        print("FAIL [\(label)] line \(line): condition is false")
    }
}

func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

let la = TimeZone(identifier: "America/Los_Angeles")!
let london = TimeZone(identifier: "Europe/London")!
let shanghai = TimeZone(identifier: "Asia/Shanghai")!
let utc = TimeZone(identifier: "UTC")!

// ── dayOffset ────────────────────────────────────────────────────────────────
// 2026-07-07 06:11 UTC == 2026-07-06 23:11 PDT (the screenshot moment)
let shot = utcDate(2026, 7, 7, 6, 11)
expectEq(dayOffset(now: shot, tz: london, local: la), 1, "london is next day vs LA")
expectEq(dayOffset(now: shot, tz: shanghai, local: la), 1, "shanghai is next day vs LA")
expectEq(dayOffset(now: shot, tz: la, local: la), 0, "same tz is same day")

// 2026-07-06 22:00 UTC == 2026-07-07 06:00 CST; LA is 2026-07-06 15:00 (previous day)
let morningCN = utcDate(2026, 7, 6, 22, 0)
expectEq(dayOffset(now: morningCN, tz: la, local: shanghai), -1, "LA is previous day vs Shanghai")

// ── daySuperscript ───────────────────────────────────────────────────────────
expectEq(daySuperscript(0), "", "no superscript for same day")
expectEq(daySuperscript(1), "\u{207A}\u{00B9}", "superscript +1")
expectEq(daySuperscript(-1), "\u{207B}\u{00B9}", "superscript -1")

// ── timeString ───────────────────────────────────────────────────────────────
expectEq(timeString(now: shot, tz: london, use24h: false), "7:11 AM", "london 12h")
expectEq(timeString(now: shot, tz: shanghai, use24h: false), "2:11 PM", "shanghai 12h")
expectEq(timeString(now: shot, tz: london, use24h: true), "07:11", "london 24h")
expectEq(timeString(now: shot, tz: shanghai, use24h: true), "14:11", "shanghai 24h")
expectEq(timeString(now: utcDate(2026, 7, 7, 0, 5), tz: utc, use24h: false), "12:05 AM", "midnight 12h")
expectEq(timeString(now: utcDate(2026, 7, 7, 12, 5), tz: utc, use24h: false), "12:05 PM", "noon 12h")
// Kathmandu is UTC+5:45
expectEq(timeString(now: shot, tz: TimeZone(identifier: "Asia/Kathmandu")!, use24h: true), "11:56", "kathmandu odd offset")

// ── statusText ───────────────────────────────────────────────────────────────
let ukEntry = TimeEntry(en: "London", zh: "伦敦", flag: "🇬🇧", tzID: "Europe/London")
let cnEntry = TimeEntry(en: "Beijing", zh: "北京", flag: "🇨🇳", tzID: "Asia/Shanghai")
expectEq(statusText(entries: [ukEntry, cnEntry], now: shot, local: la, use24h: false),
         "🇬🇧 7:11 AM\u{207A}\u{00B9}  🇨🇳 2:11 PM\u{207A}\u{00B9}",
         "status text matches screenshot")
expectEq(statusText(entries: [], now: shot, local: la, use24h: false), "🌐", "empty list shows globe")
// invalid timezone entries are skipped, not crashing
let bad = TimeEntry(en: "Nowhere", zh: "无", flag: "🏳️", tzID: "Not/AZone")
expectEq(statusText(entries: [bad, cnEntry], now: shot, local: la, use24h: true),
         "🇨🇳 14:11\u{207A}\u{00B9}", "invalid tz skipped")

// ── searchCities ─────────────────────────────────────────────────────────────
expectEq(searchCities("北京").first?.tzID, "Asia/Shanghai", "chinese name Beijing")
expectEq(searchCities("北京").first?.flag, "🇨🇳", "Beijing flag")
expectEq(searchCities("beijing").first?.tzID, "Asia/Shanghai", "english lowercase")
expectEq(searchCities("BEIJING").first?.tzID, "Asia/Shanghai", "english uppercase")
expectEq(searchCities("东京").first?.tzID, "Asia/Tokyo", "chinese name Tokyo")
expectEq(searchCities("london").first?.tzID, "Europe/London", "english London")
expectEq(searchCities("xianggang").first?.tzID, "Asia/Hong_Kong", "pinyin Hong Kong")
expectTrue(searchCities("日本").contains(where: { $0.tzID == "Asia/Tokyo" }), "country name in chinese")
expectTrue(searchCities("Chatham").contains(where: { $0.tzID == "Pacific/Chatham" }), "IANA fallback")
expectEq(searchCities("").count, 0, "empty query yields nothing")
expectEq(searchCities("   ").count, 0, "blank query yields nothing")
if let first = searchCities("San").first {
    expectTrue(first.en.lowercased().hasPrefix("san"), "prefix match ranks first")
} else {
    expectTrue(false, "search 'San' has results")
}

// ── city database sanity ─────────────────────────────────────────────────────
expectTrue(cityDatabase.count >= 150, "database has enough cities (\(cityDatabase.count))")
for c in cityDatabase {
    if TimeZone(identifier: c.tzID) == nil {
        failures += 1
        print("FAIL [db] city \(c.en) has unresolvable tz \(c.tzID)")
    } else {
        passes += 1
    }
    if c.flag.isEmpty || c.zh.isEmpty || c.en.isEmpty {
        failures += 1
        print("FAIL [db] city \(c.en) has empty field")
    } else {
        passes += 1
    }
}
// no duplicate english names within the same timezone
var seen = Set<String>()
for c in cityDatabase {
    let key = c.en + "|" + c.tzID
    if seen.contains(key) {
        failures += 1
        print("FAIL [db] duplicate entry \(key)")
    }
    seen.insert(key)
}

// ── flagEmoji ────────────────────────────────────────────────────────────────
expectEq(flagEmoji(countryCode: "DE"), "🇩🇪", "Germany flag from ISO code")
expectEq(flagEmoji(countryCode: "gb"), "🇬🇧", "lowercase ISO code")
expectEq(flagEmoji(countryCode: "CN"), "🇨🇳", "China flag from ISO code")
expectEq(flagEmoji(countryCode: nil), "🌐", "nil code falls back to globe")
expectEq(flagEmoji(countryCode: ""), "🌐", "empty code falls back to globe")
expectEq(flagEmoji(countryCode: "X1"), "🌐", "non-alphabetic code falls back to globe")

// ── persistence round-trip ───────────────────────────────────────────────────
let encoded = encodeEntries([ukEntry, cnEntry])
expectEq(decodeEntries(encoded), [ukEntry, cnEntry], "entries JSON round-trip")
expectEq(decodeEntries(Data("garbage".utf8)), [], "garbage data decodes to empty")

// ── computeFlips (baseline XOR desired) ──────────────────────────────────────
// System natural scrolling ON (baselineNatural = true)
expectEq(computeFlips(settings: ScrollSettings(mouse: .natural, trackpad: .natural), baselineNatural: true),
         ScrollFlips(mouse: false, trackpad: false), "baseline natural, both natural = no flips")
expectEq(computeFlips(settings: ScrollSettings(mouse: .reverse, trackpad: .natural), baselineNatural: true),
         ScrollFlips(mouse: true, trackpad: false), "baseline natural, mouse reverse only")
expectEq(computeFlips(settings: ScrollSettings(mouse: .natural, trackpad: .reverse), baselineNatural: true),
         ScrollFlips(mouse: false, trackpad: true), "baseline natural, trackpad reverse only")
// System natural scrolling OFF (baselineNatural = false — already traditional)
expectEq(computeFlips(settings: ScrollSettings(mouse: .natural, trackpad: .natural), baselineNatural: false),
         ScrollFlips(mouse: true, trackpad: true), "baseline traditional, both natural = flip both")
expectEq(computeFlips(settings: ScrollSettings(mouse: .reverse, trackpad: .reverse), baselineNatural: false),
         ScrollFlips(mouse: false, trackpad: false), "baseline traditional, both reverse = no flips")

// ── shouldRunTap ─────────────────────────────────────────────────────────────
expectEq(shouldRunTap(ScrollFlips(mouse: false, trackpad: false)), false, "no flips = no tap")
expectEq(shouldRunTap(ScrollFlips(mouse: true, trackpad: false)), true, "mouse flip = run tap")
expectEq(shouldRunTap(ScrollFlips(mouse: false, trackpad: true)), true, "trackpad flip = run tap")
expectEq(shouldRunTap(ScrollFlips(mouse: true, trackpad: true)), true, "both flip = run tap")

// ── reversedVerticalDelta: Int64 ─────────────────────────────────────────────
let mouseFlip = ScrollFlips(mouse: true, trackpad: false)
let tpFlip = ScrollFlips(mouse: false, trackpad: true)
let noFlip = ScrollFlips(mouse: false, trackpad: false)
expectEq(reversedVerticalDelta(Int64(5), isContinuous: false, flips: mouseFlip), Int64(-5), "mouse event flipped when mouse flip on")
expectEq(reversedVerticalDelta(Int64(5), isContinuous: true, flips: mouseFlip), Int64(5), "trackpad event untouched when only mouse flip")
expectEq(reversedVerticalDelta(Int64(5), isContinuous: true, flips: tpFlip), Int64(-5), "trackpad event flipped when trackpad flip on")
expectEq(reversedVerticalDelta(Int64(5), isContinuous: false, flips: tpFlip), Int64(5), "mouse event untouched when only trackpad flip")
expectEq(reversedVerticalDelta(Int64(-3), isContinuous: false, flips: noFlip), Int64(-3), "no flip leaves delta unchanged")

// ── reversedVerticalDelta: Double (fixed-point field) ─────────────────────────
expectEq(reversedVerticalDelta(Double(2.5), isContinuous: false, flips: mouseFlip), Double(-2.5), "double mouse flip")
expectEq(reversedVerticalDelta(Double(2.5), isContinuous: true, flips: mouseFlip), Double(2.5), "double trackpad untouched")
expectEq(reversedVerticalDelta(Double(2.5), isContinuous: true, flips: tpFlip), Double(-2.5), "double trackpad flip")

// ── duplicate city detection ─────────────────────────────────────────────────
let existingEntries = [TimeEntry(en: "Beijing", zh: "北京", flag: "🇨🇳", tzID: "Asia/Shanghai")]
expectTrue(isDuplicateEntry(tzID: "Asia/Shanghai", in: existingEntries), "same timezone is a duplicate")
expectTrue(!isDuplicateEntry(tzID: "Asia/Tokyo", in: existingEntries), "different timezone is not a duplicate")
expectTrue(!isDuplicateEntry(tzID: "Asia/Shanghai", in: []), "empty list has no duplicates")

// ── scroll defaults ──────────────────────────────────────────────────────────
expectEq(ScrollSettings.default.mouse, .reverse, "default mouse is reverse")
expectEq(ScrollSettings.default.trackpad, .natural, "default trackpad is natural")

// ── scroll settings persistence ──────────────────────────────────────────────
let ss = ScrollSettings(mouse: .reverse, trackpad: .natural)
expectEq(decodeScrollSettings(encodeScrollSettings(ss)), ss, "scroll settings JSON round-trip")
expectEq(decodeScrollSettings(Data("junk".utf8)), ScrollSettings.default, "garbage scroll settings → default")

// ── DockPin clamp math ───────────────────────────────────────────────────────
let dpBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)   // maxY = 800, maxX = 1000
// The target display is never clamped.
expectTrue(clampedCursor(point: CGPoint(x: 500, y: 799), displayBounds: dpBounds,
                         isTargetDisplay: true, dockEdge: .bottom, zone: 6) == nil,
           "target display never clamps")
// Non-target, near bottom edge → push y to maxY-zone-1 = 793, keep x.
if let c = clampedCursor(point: CGPoint(x: 500, y: 799), displayBounds: dpBounds,
                         isTargetDisplay: false, dockEdge: .bottom, zone: 6) {
    expectEq(c.y, CGFloat(793), "bottom clamp y")
    expectEq(c.x, CGFloat(500), "bottom clamp keeps x")
} else { expectTrue(false, "expected clamp at bottom edge") }
// Non-target, far from bottom edge → no clamp.
expectTrue(clampedCursor(point: CGPoint(x: 500, y: 700), displayBounds: dpBounds,
                         isTargetDisplay: false, dockEdge: .bottom, zone: 6) == nil,
           "not near bottom edge = no clamp")
// Left dock: near left edge (x <= minX+zone) → push x to minX+zone+1 = 7.
if let c = clampedCursor(point: CGPoint(x: 2, y: 400), displayBounds: dpBounds,
                         isTargetDisplay: false, dockEdge: .left, zone: 6) {
    expectEq(c.x, CGFloat(7), "left clamp x")
    expectEq(c.y, CGFloat(400), "left clamp keeps y")
} else { expectTrue(false, "expected clamp at left edge") }
// Right dock: near right edge (x >= maxX-zone) → push x to maxX-zone-1 = 993.
if let c = clampedCursor(point: CGPoint(x: 998, y: 400), displayBounds: dpBounds,
                         isTargetDisplay: false, dockEdge: .right, zone: 6) {
    expectEq(c.x, CGFloat(993), "right clamp x")
} else { expectTrue(false, "expected clamp at right edge") }
// Orientation parsing
expectEq(dockEdge(from: "left"), DockEdge.left, "parse left orientation")
expectEq(dockEdge(from: "right"), DockEdge.right, "parse right orientation")
expectEq(dockEdge(from: "bottom"), DockEdge.bottom, "parse bottom orientation")
expectEq(dockEdge(from: "garbage"), DockEdge.bottom, "unknown orientation defaults to bottom")

// ── DDC/CI brightness payload ────────────────────────────────────────────────
// Set-VCP frame for brightness (VCP 0x10) at value 50: [0x84,0x03,0x10,0x00,0x32,chk]
let ddc = ddcSetVCPPayload(vcp: 0x10, value: 50)
expectEq(ddc.count, 6, "ddc payload length")
expectEq(ddc[0], UInt8(0x84), "ddc length/opcode byte")
expectEq(ddc[1], UInt8(0x03), "ddc set-vcp command")
expectEq(ddc[2], UInt8(0x10), "ddc vcp code = brightness")
expectEq(ddc[3], UInt8(0), "ddc value high byte")
expectEq(ddc[4], UInt8(50), "ddc value low byte")
let ddcChk: UInt8 = 0x6e ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32
expectEq(ddc[5], ddcChk, "ddc checksum (XOR incl. 0x6e dest)")
// high-byte value is carried correctly
let ddcBig = ddcSetVCPPayload(vcp: 0x10, value: 300)
expectEq(ddcBig[3], UInt8(1), "ddc value high byte for 300")
expectEq(ddcBig[4], UInt8(44), "ddc value low byte for 300")

// ── brightness percent clamping ──────────────────────────────────────────────
expectEq(clampBrightnessPercent(150), 100, "clamp above 100")
expectEq(clampBrightnessPercent(-5), 0, "clamp below 0")
expectEq(clampBrightnessPercent(50), 50, "in-range percent unchanged")

print("\n\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
