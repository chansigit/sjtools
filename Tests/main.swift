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

// ── persistence round-trip ───────────────────────────────────────────────────
let encoded = encodeEntries([ukEntry, cnEntry])
expectEq(decodeEntries(encoded), [ukEntry, cnEntry], "entries JSON round-trip")
expectEq(decodeEntries(Data("garbage".utf8)), [], "garbage data decodes to empty")

print("\n\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
