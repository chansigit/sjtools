import Foundation

// MARK: - Models

struct City {
    let en: String
    let zh: String
    let countryEn: String
    let countryZh: String
    let flag: String
    let tzID: String
}

struct TimeEntry: Codable, Equatable {
    var en: String
    var zh: String
    var flag: String
    var tzID: String
}

// MARK: - Day offset & formatting

/// Calendar-day difference of `tz` relative to `local` at instant `now` (-1, 0, +1).
func dayOffset(now: Date, tz: TimeZone, local: TimeZone) -> Int {
    func dayNumber(_ zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: now)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utcCal.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
        return Int((midnight.timeIntervalSinceReferenceDate / 86400.0).rounded())
    }
    return dayNumber(tz) - dayNumber(local)
}

private let superscriptDigits: [Character: String] = [
    "0": "\u{2070}", "1": "\u{00B9}", "2": "\u{00B2}", "3": "\u{00B3}", "4": "\u{2074}",
    "5": "\u{2075}", "6": "\u{2076}", "7": "\u{2077}", "8": "\u{2078}", "9": "\u{2079}",
]

func daySuperscript(_ offset: Int) -> String {
    if offset == 0 { return "" }
    let sign = offset > 0 ? "\u{207A}" : "\u{207B}"
    return sign + String(abs(offset)).compactMap { superscriptDigits[$0] }.joined()
}

func timeString(now: Date, tz: TimeZone, use24h: Bool) -> String {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = tz
    fmt.dateFormat = use24h ? "HH:mm" : "h:mm a"
    return fmt.string(from: now)
}

/// Text for the menu bar: "🇬🇧 7:11 AM⁺¹  🇨🇳 2:11 PM⁺¹", or "🌐" when empty.
func statusText(entries: [TimeEntry], now: Date, local: TimeZone, use24h: Bool) -> String {
    var parts: [String] = []
    for e in entries {
        guard let tz = TimeZone(identifier: e.tzID) else { continue }
        let sup = daySuperscript(dayOffset(now: now, tz: tz, local: local))
        parts.append("\(e.flag) \(timeString(now: now, tz: tz, use24h: use24h))\(sup)")
    }
    return parts.isEmpty ? "🌐" : parts.joined(separator: "  ")
}

// MARK: - Persistence

func encodeEntries(_ entries: [TimeEntry]) -> Data {
    return (try? JSONEncoder().encode(entries)) ?? Data()
}

func decodeEntries(_ data: Data) -> [TimeEntry] {
    return (try? JSONDecoder().decode([TimeEntry].self, from: data)) ?? []
}

// MARK: - Search

/// Transliterate Chinese to pinyin without tone marks or spaces ("香港" → "xianggang").
func latinize(_ s: String) -> String {
    let m = NSMutableString(string: s)
    CFStringTransform(m, nil, kCFStringTransformToLatin, false)
    CFStringTransform(m, nil, kCFStringTransformStripCombiningMarks, false)
    return (m as String)
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "'", with: "")
        .lowercased()
}

private let cityPinyins: [String] = cityDatabase.map { latinize($0.zh) }

func searchCities(_ query: String) -> [City] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return [] }
    let qSquash = q.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")

    var scored: [(rank: Int, index: Int, city: City)] = []
    for (i, c) in cityDatabase.enumerated() {
        let en = c.en.lowercased()
        let enSquash = en.replacingOccurrences(of: " ", with: "")
        let py = cityPinyins[i]
        var rank: Int?
        if en == q || c.zh == q || py == qSquash || enSquash == qSquash {
            rank = 0
        } else if en.hasPrefix(q) || c.zh.hasPrefix(q) || py.hasPrefix(qSquash) || enSquash.hasPrefix(qSquash) {
            rank = 1
        } else if en.contains(q) || c.zh.contains(q)
                    || (qSquash.count >= 2 && (py.contains(qSquash) || enSquash.contains(qSquash))) {
            rank = 2
        } else if c.countryEn.lowercased() == q || c.countryZh == q {
            rank = 3
        } else if !c.countryEn.isEmpty && (c.countryEn.lowercased().contains(q) || c.countryZh.contains(q)) {
            rank = 4
        } else if c.tzID.lowercased().contains(q) {
            rank = 5
        }
        if let r = rank { scored.append((r, i, c)) }
    }
    scored.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.index < $1.index }
    var results = scored.map { $0.city }

    // Fallback: raw IANA identifiers not covered by the curated database
    let qID = q.replacingOccurrences(of: " ", with: "_")
    let covered = Set(results.map { $0.tzID })
    for id in TimeZone.knownTimeZoneIdentifiers {
        if id.lowercased().contains(qID) && !covered.contains(id) {
            let name = id.split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? id
            results.append(City(en: name, zh: name, countryEn: "", countryZh: "", flag: "🌐", tzID: id))
        }
    }
    return results.count > 40 ? Array(results.prefix(40)) : results
}

// MARK: - City database

private func C(_ en: String, _ zh: String, _ cEn: String, _ cZh: String, _ flag: String, _ tz: String) -> City {
    return City(en: en, zh: zh, countryEn: cEn, countryZh: cZh, flag: flag, tzID: tz)
}

let cityDatabase: [City] = [
    // China (mainland civil time is Asia/Shanghai everywhere)
    C("Beijing", "北京", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Shanghai", "上海", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Shenzhen", "深圳", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Guangzhou", "广州", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Hangzhou", "杭州", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Chengdu", "成都", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Chongqing", "重庆", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Nanjing", "南京", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Wuhan", "武汉", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Xi'an", "西安", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Tianjin", "天津", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Suzhou", "苏州", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Qingdao", "青岛", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Dalian", "大连", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Xiamen", "厦门", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Kunming", "昆明", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Changsha", "长沙", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Zhengzhou", "郑州", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Shenyang", "沈阳", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Harbin", "哈尔滨", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Changchun", "长春", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Hefei", "合肥", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Fuzhou", "福州", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Jinan", "济南", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Shijiazhuang", "石家庄", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Taiyuan", "太原", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Nanchang", "南昌", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Nanning", "南宁", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Guiyang", "贵阳", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Lanzhou", "兰州", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Xining", "西宁", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Yinchuan", "银川", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Hohhot", "呼和浩特", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Urumqi", "乌鲁木齐", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Lhasa", "拉萨", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Haikou", "海口", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Sanya", "三亚", "China", "中国", "🇨🇳", "Asia/Shanghai"),
    C("Hong Kong", "香港", "Hong Kong", "中国香港", "🇭🇰", "Asia/Hong_Kong"),
    C("Macau", "澳门", "Macau", "中国澳门", "🇲🇴", "Asia/Macau"),
    C("Taipei", "台北", "Taiwan", "中国台湾", "🇹🇼", "Asia/Taipei"),
    C("Hsinchu", "新竹", "Taiwan", "中国台湾", "🇹🇼", "Asia/Taipei"),
    C("Kaohsiung", "高雄", "Taiwan", "中国台湾", "🇹🇼", "Asia/Taipei"),

    // Japan & Korea
    C("Tokyo", "东京", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Osaka", "大阪", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Kyoto", "京都", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Nagoya", "名古屋", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Yokohama", "横滨", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Kobe", "神户", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Sapporo", "札幌", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Fukuoka", "福冈", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Sendai", "仙台", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Hiroshima", "广岛", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Naha", "那霸", "Japan", "日本", "🇯🇵", "Asia/Tokyo"),
    C("Seoul", "首尔", "South Korea", "韩国", "🇰🇷", "Asia/Seoul"),
    C("Busan", "釜山", "South Korea", "韩国", "🇰🇷", "Asia/Seoul"),
    C("Incheon", "仁川", "South Korea", "韩国", "🇰🇷", "Asia/Seoul"),
    C("Daejeon", "大田", "South Korea", "韩国", "🇰🇷", "Asia/Seoul"),
    C("Daegu", "大邱", "South Korea", "韩国", "🇰🇷", "Asia/Seoul"),

    // Southeast Asia
    C("Singapore", "新加坡", "Singapore", "新加坡", "🇸🇬", "Asia/Singapore"),
    C("Kuala Lumpur", "吉隆坡", "Malaysia", "马来西亚", "🇲🇾", "Asia/Kuala_Lumpur"),
    C("Penang", "槟城", "Malaysia", "马来西亚", "🇲🇾", "Asia/Kuala_Lumpur"),
    C("Bangkok", "曼谷", "Thailand", "泰国", "🇹🇭", "Asia/Bangkok"),
    C("Chiang Mai", "清迈", "Thailand", "泰国", "🇹🇭", "Asia/Bangkok"),
    C("Phuket", "普吉", "Thailand", "泰国", "🇹🇭", "Asia/Bangkok"),
    C("Hanoi", "河内", "Vietnam", "越南", "🇻🇳", "Asia/Ho_Chi_Minh"),
    C("Ho Chi Minh City", "胡志明市", "Vietnam", "越南", "🇻🇳", "Asia/Ho_Chi_Minh"),
    C("Da Nang", "岘港", "Vietnam", "越南", "🇻🇳", "Asia/Ho_Chi_Minh"),
    C("Phnom Penh", "金边", "Cambodia", "柬埔寨", "🇰🇭", "Asia/Phnom_Penh"),
    C("Vientiane", "万象", "Laos", "老挝", "🇱🇦", "Asia/Vientiane"),
    C("Yangon", "仰光", "Myanmar", "缅甸", "🇲🇲", "Asia/Yangon"),
    C("Manila", "马尼拉", "Philippines", "菲律宾", "🇵🇭", "Asia/Manila"),
    C("Cebu", "宿务", "Philippines", "菲律宾", "🇵🇭", "Asia/Manila"),
    C("Jakarta", "雅加达", "Indonesia", "印度尼西亚", "🇮🇩", "Asia/Jakarta"),
    C("Surabaya", "泗水", "Indonesia", "印度尼西亚", "🇮🇩", "Asia/Jakarta"),
    C("Bali", "巴厘岛", "Indonesia", "印度尼西亚", "🇮🇩", "Asia/Makassar"),

    // South Asia
    C("New Delhi", "新德里", "India", "印度", "🇮🇳", "Asia/Kolkata"),
    C("Mumbai", "孟买", "India", "印度", "🇮🇳", "Asia/Kolkata"),
    C("Bangalore", "班加罗尔", "India", "印度", "🇮🇳", "Asia/Kolkata"),
    C("Chennai", "金奈", "India", "印度", "🇮🇳", "Asia/Kolkata"),
    C("Kolkata", "加尔各答", "India", "印度", "🇮🇳", "Asia/Kolkata"),
    C("Hyderabad", "海得拉巴", "India", "印度", "🇮🇳", "Asia/Kolkata"),
    C("Pune", "浦那", "India", "印度", "🇮🇳", "Asia/Kolkata"),
    C("Islamabad", "伊斯兰堡", "Pakistan", "巴基斯坦", "🇵🇰", "Asia/Karachi"),
    C("Karachi", "卡拉奇", "Pakistan", "巴基斯坦", "🇵🇰", "Asia/Karachi"),
    C("Lahore", "拉合尔", "Pakistan", "巴基斯坦", "🇵🇰", "Asia/Karachi"),
    C("Dhaka", "达卡", "Bangladesh", "孟加拉国", "🇧🇩", "Asia/Dhaka"),
    C("Colombo", "科伦坡", "Sri Lanka", "斯里兰卡", "🇱🇰", "Asia/Colombo"),
    C("Kathmandu", "加德满都", "Nepal", "尼泊尔", "🇳🇵", "Asia/Kathmandu"),

    // Central & West Asia
    C("Almaty", "阿拉木图", "Kazakhstan", "哈萨克斯坦", "🇰🇿", "Asia/Almaty"),
    C("Astana", "阿斯塔纳", "Kazakhstan", "哈萨克斯坦", "🇰🇿", "Asia/Almaty"),
    C("Tashkent", "塔什干", "Uzbekistan", "乌兹别克斯坦", "🇺🇿", "Asia/Tashkent"),
    C("Bishkek", "比什凯克", "Kyrgyzstan", "吉尔吉斯斯坦", "🇰🇬", "Asia/Bishkek"),
    C("Ulaanbaatar", "乌兰巴托", "Mongolia", "蒙古", "🇲🇳", "Asia/Ulaanbaatar"),
    C("Tbilisi", "第比利斯", "Georgia", "格鲁吉亚", "🇬🇪", "Asia/Tbilisi"),
    C("Yerevan", "埃里温", "Armenia", "亚美尼亚", "🇦🇲", "Asia/Yerevan"),
    C("Baku", "巴库", "Azerbaijan", "阿塞拜疆", "🇦🇿", "Asia/Baku"),
    C("Tehran", "德黑兰", "Iran", "伊朗", "🇮🇷", "Asia/Tehran"),
    C("Baghdad", "巴格达", "Iraq", "伊拉克", "🇮🇶", "Asia/Baghdad"),
    C("Riyadh", "利雅得", "Saudi Arabia", "沙特阿拉伯", "🇸🇦", "Asia/Riyadh"),
    C("Jeddah", "吉达", "Saudi Arabia", "沙特阿拉伯", "🇸🇦", "Asia/Riyadh"),
    C("Dubai", "迪拜", "United Arab Emirates", "阿联酋", "🇦🇪", "Asia/Dubai"),
    C("Abu Dhabi", "阿布扎比", "United Arab Emirates", "阿联酋", "🇦🇪", "Asia/Dubai"),
    C("Doha", "多哈", "Qatar", "卡塔尔", "🇶🇦", "Asia/Qatar"),
    C("Kuwait City", "科威特城", "Kuwait", "科威特", "🇰🇼", "Asia/Kuwait"),
    C("Manama", "麦纳麦", "Bahrain", "巴林", "🇧🇭", "Asia/Bahrain"),
    C("Muscat", "马斯喀特", "Oman", "阿曼", "🇴🇲", "Asia/Muscat"),
    C("Amman", "安曼", "Jordan", "约旦", "🇯🇴", "Asia/Amman"),
    C("Beirut", "贝鲁特", "Lebanon", "黎巴嫩", "🇱🇧", "Asia/Beirut"),
    C("Jerusalem", "耶路撒冷", "Israel", "以色列", "🇮🇱", "Asia/Jerusalem"),
    C("Tel Aviv", "特拉维夫", "Israel", "以色列", "🇮🇱", "Asia/Jerusalem"),
    C("Istanbul", "伊斯坦布尔", "Turkey", "土耳其", "🇹🇷", "Europe/Istanbul"),
    C("Ankara", "安卡拉", "Turkey", "土耳其", "🇹🇷", "Europe/Istanbul"),

    // Europe
    C("London", "伦敦", "United Kingdom", "英国", "🇬🇧", "Europe/London"),
    C("Cambridge", "剑桥", "United Kingdom", "英国", "🇬🇧", "Europe/London"),
    C("Oxford", "牛津", "United Kingdom", "英国", "🇬🇧", "Europe/London"),
    C("Manchester", "曼彻斯特", "United Kingdom", "英国", "🇬🇧", "Europe/London"),
    C("Birmingham", "伯明翰", "United Kingdom", "英国", "🇬🇧", "Europe/London"),
    C("Edinburgh", "爱丁堡", "United Kingdom", "英国", "🇬🇧", "Europe/London"),
    C("Glasgow", "格拉斯哥", "United Kingdom", "英国", "🇬🇧", "Europe/London"),
    C("Dublin", "都柏林", "Ireland", "爱尔兰", "🇮🇪", "Europe/Dublin"),
    C("Paris", "巴黎", "France", "法国", "🇫🇷", "Europe/Paris"),
    C("Lyon", "里昂", "France", "法国", "🇫🇷", "Europe/Paris"),
    C("Marseille", "马赛", "France", "法国", "🇫🇷", "Europe/Paris"),
    C("Nice", "尼斯", "France", "法国", "🇫🇷", "Europe/Paris"),
    C("Berlin", "柏林", "Germany", "德国", "🇩🇪", "Europe/Berlin"),
    C("Munich", "慕尼黑", "Germany", "德国", "🇩🇪", "Europe/Berlin"),
    C("Frankfurt", "法兰克福", "Germany", "德国", "🇩🇪", "Europe/Berlin"),
    C("Hamburg", "汉堡", "Germany", "德国", "🇩🇪", "Europe/Berlin"),
    C("Cologne", "科隆", "Germany", "德国", "🇩🇪", "Europe/Berlin"),
    C("Stuttgart", "斯图加特", "Germany", "德国", "🇩🇪", "Europe/Berlin"),
    C("Heidelberg", "海德堡", "Germany", "德国", "🇩🇪", "Europe/Berlin"),
    C("Dresden", "德累斯顿", "Germany", "德国", "🇩🇪", "Europe/Berlin"),
    C("Zurich", "苏黎世", "Switzerland", "瑞士", "🇨🇭", "Europe/Zurich"),
    C("Geneva", "日内瓦", "Switzerland", "瑞士", "🇨🇭", "Europe/Zurich"),
    C("Basel", "巴塞尔", "Switzerland", "瑞士", "🇨🇭", "Europe/Zurich"),
    C("Lausanne", "洛桑", "Switzerland", "瑞士", "🇨🇭", "Europe/Zurich"),
    C("Bern", "伯尔尼", "Switzerland", "瑞士", "🇨🇭", "Europe/Zurich"),
    C("Vienna", "维也纳", "Austria", "奥地利", "🇦🇹", "Europe/Vienna"),
    C("Amsterdam", "阿姆斯特丹", "Netherlands", "荷兰", "🇳🇱", "Europe/Amsterdam"),
    C("Rotterdam", "鹿特丹", "Netherlands", "荷兰", "🇳🇱", "Europe/Amsterdam"),
    C("The Hague", "海牙", "Netherlands", "荷兰", "🇳🇱", "Europe/Amsterdam"),
    C("Utrecht", "乌得勒支", "Netherlands", "荷兰", "🇳🇱", "Europe/Amsterdam"),
    C("Brussels", "布鲁塞尔", "Belgium", "比利时", "🇧🇪", "Europe/Brussels"),
    C("Luxembourg", "卢森堡", "Luxembourg", "卢森堡", "🇱🇺", "Europe/Luxembourg"),
    C("Copenhagen", "哥本哈根", "Denmark", "丹麦", "🇩🇰", "Europe/Copenhagen"),
    C("Stockholm", "斯德哥尔摩", "Sweden", "瑞典", "🇸🇪", "Europe/Stockholm"),
    C("Gothenburg", "哥德堡", "Sweden", "瑞典", "🇸🇪", "Europe/Stockholm"),
    C("Oslo", "奥斯陆", "Norway", "挪威", "🇳🇴", "Europe/Oslo"),
    C("Helsinki", "赫尔辛基", "Finland", "芬兰", "🇫🇮", "Europe/Helsinki"),
    C("Reykjavik", "雷克雅未克", "Iceland", "冰岛", "🇮🇸", "Atlantic/Reykjavik"),
    C("Madrid", "马德里", "Spain", "西班牙", "🇪🇸", "Europe/Madrid"),
    C("Barcelona", "巴塞罗那", "Spain", "西班牙", "🇪🇸", "Europe/Madrid"),
    C("Lisbon", "里斯本", "Portugal", "葡萄牙", "🇵🇹", "Europe/Lisbon"),
    C("Rome", "罗马", "Italy", "意大利", "🇮🇹", "Europe/Rome"),
    C("Milan", "米兰", "Italy", "意大利", "🇮🇹", "Europe/Rome"),
    C("Florence", "佛罗伦萨", "Italy", "意大利", "🇮🇹", "Europe/Rome"),
    C("Venice", "威尼斯", "Italy", "意大利", "🇮🇹", "Europe/Rome"),
    C("Naples", "那不勒斯", "Italy", "意大利", "🇮🇹", "Europe/Rome"),
    C("Turin", "都灵", "Italy", "意大利", "🇮🇹", "Europe/Rome"),
    C("Athens", "雅典", "Greece", "希腊", "🇬🇷", "Europe/Athens"),
    C("Prague", "布拉格", "Czech Republic", "捷克", "🇨🇿", "Europe/Prague"),
    C("Warsaw", "华沙", "Poland", "波兰", "🇵🇱", "Europe/Warsaw"),
    C("Krakow", "克拉科夫", "Poland", "波兰", "🇵🇱", "Europe/Warsaw"),
    C("Budapest", "布达佩斯", "Hungary", "匈牙利", "🇭🇺", "Europe/Budapest"),
    C("Bucharest", "布加勒斯特", "Romania", "罗马尼亚", "🇷🇴", "Europe/Bucharest"),
    C("Sofia", "索非亚", "Bulgaria", "保加利亚", "🇧🇬", "Europe/Sofia"),
    C("Belgrade", "贝尔格莱德", "Serbia", "塞尔维亚", "🇷🇸", "Europe/Belgrade"),
    C("Zagreb", "萨格勒布", "Croatia", "克罗地亚", "🇭🇷", "Europe/Zagreb"),
    C("Kyiv", "基辅", "Ukraine", "乌克兰", "🇺🇦", "Europe/Kyiv"),
    C("Moscow", "莫斯科", "Russia", "俄罗斯", "🇷🇺", "Europe/Moscow"),
    C("Saint Petersburg", "圣彼得堡", "Russia", "俄罗斯", "🇷🇺", "Europe/Moscow"),
    C("Vladivostok", "海参崴", "Russia", "俄罗斯", "🇷🇺", "Asia/Vladivostok"),

    // United States
    C("New York", "纽约", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Boston", "波士顿", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Washington DC", "华盛顿", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Philadelphia", "费城", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Miami", "迈阿密", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Atlanta", "亚特兰大", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Pittsburgh", "匹兹堡", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Charlotte", "夏洛特", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Raleigh", "罗利", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Durham", "达勒姆", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Orlando", "奥兰多", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Tampa", "坦帕", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Baltimore", "巴尔的摩", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Princeton", "普林斯顿", "United States", "美国", "🇺🇸", "America/New_York"),
    C("New Haven", "纽黑文", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Ithaca", "伊萨卡", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Providence", "普罗维登斯", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Columbus", "哥伦布", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Cleveland", "克利夫兰", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Cincinnati", "辛辛那提", "United States", "美国", "🇺🇸", "America/New_York"),
    C("Detroit", "底特律", "United States", "美国", "🇺🇸", "America/Detroit"),
    C("Ann Arbor", "安娜堡", "United States", "美国", "🇺🇸", "America/Detroit"),
    C("Indianapolis", "印第安纳波利斯", "United States", "美国", "🇺🇸", "America/Indiana/Indianapolis"),
    C("Chicago", "芝加哥", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Houston", "休斯顿", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Dallas", "达拉斯", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Austin", "奥斯汀", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("San Antonio", "圣安东尼奥", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Minneapolis", "明尼阿波利斯", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("St. Louis", "圣路易斯", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Kansas City", "堪萨斯城", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("New Orleans", "新奥尔良", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Madison", "麦迪逊", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Milwaukee", "密尔沃基", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Nashville", "纳什维尔", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Oklahoma City", "俄克拉何马城", "United States", "美国", "🇺🇸", "America/Chicago"),
    C("Denver", "丹佛", "United States", "美国", "🇺🇸", "America/Denver"),
    C("Boulder", "博尔德", "United States", "美国", "🇺🇸", "America/Denver"),
    C("Salt Lake City", "盐湖城", "United States", "美国", "🇺🇸", "America/Denver"),
    C("Albuquerque", "阿尔伯克基", "United States", "美国", "🇺🇸", "America/Denver"),
    C("Phoenix", "菲尼克斯", "United States", "美国", "🇺🇸", "America/Phoenix"),
    C("Tucson", "图森", "United States", "美国", "🇺🇸", "America/Phoenix"),
    C("Los Angeles", "洛杉矶", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("San Francisco", "旧金山", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("San Jose", "圣何塞", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("San Diego", "圣迭戈", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Seattle", "西雅图", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Portland", "波特兰", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Sacramento", "萨克拉门托", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Las Vegas", "拉斯维加斯", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Stanford", "斯坦福", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Palo Alto", "帕洛阿尔托", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Mountain View", "山景城", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Cupertino", "库比蒂诺", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Berkeley", "伯克利", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Irvine", "尔湾", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Pasadena", "帕萨迪纳", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Santa Barbara", "圣巴巴拉", "United States", "美国", "🇺🇸", "America/Los_Angeles"),
    C("Anchorage", "安克雷奇", "United States", "美国", "🇺🇸", "America/Anchorage"),
    C("Honolulu", "檀香山", "United States", "美国", "🇺🇸", "Pacific/Honolulu"),

    // Canada & Mexico
    C("Toronto", "多伦多", "Canada", "加拿大", "🇨🇦", "America/Toronto"),
    C("Montreal", "蒙特利尔", "Canada", "加拿大", "🇨🇦", "America/Toronto"),
    C("Ottawa", "渥太华", "Canada", "加拿大", "🇨🇦", "America/Toronto"),
    C("Quebec City", "魁北克城", "Canada", "加拿大", "🇨🇦", "America/Toronto"),
    C("Vancouver", "温哥华", "Canada", "加拿大", "🇨🇦", "America/Vancouver"),
    C("Victoria", "维多利亚", "Canada", "加拿大", "🇨🇦", "America/Vancouver"),
    C("Calgary", "卡尔加里", "Canada", "加拿大", "🇨🇦", "America/Edmonton"),
    C("Edmonton", "埃德蒙顿", "Canada", "加拿大", "🇨🇦", "America/Edmonton"),
    C("Winnipeg", "温尼伯", "Canada", "加拿大", "🇨🇦", "America/Winnipeg"),
    C("Halifax", "哈利法克斯", "Canada", "加拿大", "🇨🇦", "America/Halifax"),
    C("Mexico City", "墨西哥城", "Mexico", "墨西哥", "🇲🇽", "America/Mexico_City"),
    C("Guadalajara", "瓜达拉哈拉", "Mexico", "墨西哥", "🇲🇽", "America/Mexico_City"),
    C("Monterrey", "蒙特雷", "Mexico", "墨西哥", "🇲🇽", "America/Monterrey"),
    C("Cancun", "坎昆", "Mexico", "墨西哥", "🇲🇽", "America/Cancun"),
    C("Tijuana", "蒂华纳", "Mexico", "墨西哥", "🇲🇽", "America/Tijuana"),

    // Central & South America, Caribbean
    C("Sao Paulo", "圣保罗", "Brazil", "巴西", "🇧🇷", "America/Sao_Paulo"),
    C("Rio de Janeiro", "里约热内卢", "Brazil", "巴西", "🇧🇷", "America/Sao_Paulo"),
    C("Brasilia", "巴西利亚", "Brazil", "巴西", "🇧🇷", "America/Sao_Paulo"),
    C("Buenos Aires", "布宜诺斯艾利斯", "Argentina", "阿根廷", "🇦🇷", "America/Argentina/Buenos_Aires"),
    C("Santiago", "圣地亚哥", "Chile", "智利", "🇨🇱", "America/Santiago"),
    C("Lima", "利马", "Peru", "秘鲁", "🇵🇪", "America/Lima"),
    C("Bogota", "波哥大", "Colombia", "哥伦比亚", "🇨🇴", "America/Bogota"),
    C("Caracas", "加拉加斯", "Venezuela", "委内瑞拉", "🇻🇪", "America/Caracas"),
    C("Quito", "基多", "Ecuador", "厄瓜多尔", "🇪🇨", "America/Guayaquil"),
    C("Montevideo", "蒙得维的亚", "Uruguay", "乌拉圭", "🇺🇾", "America/Montevideo"),
    C("La Paz", "拉巴斯", "Bolivia", "玻利维亚", "🇧🇴", "America/La_Paz"),
    C("Panama City", "巴拿马城", "Panama", "巴拿马", "🇵🇦", "America/Panama"),
    C("San Jose CR", "圣何塞(哥斯达黎加)", "Costa Rica", "哥斯达黎加", "🇨🇷", "America/Costa_Rica"),
    C("Havana", "哈瓦那", "Cuba", "古巴", "🇨🇺", "America/Havana"),
    C("San Juan", "圣胡安", "Puerto Rico", "波多黎各", "🇵🇷", "America/Puerto_Rico"),

    // Africa
    C("Cairo", "开罗", "Egypt", "埃及", "🇪🇬", "Africa/Cairo"),
    C("Lagos", "拉各斯", "Nigeria", "尼日利亚", "🇳🇬", "Africa/Lagos"),
    C("Abuja", "阿布贾", "Nigeria", "尼日利亚", "🇳🇬", "Africa/Lagos"),
    C("Nairobi", "内罗毕", "Kenya", "肯尼亚", "🇰🇪", "Africa/Nairobi"),
    C("Johannesburg", "约翰内斯堡", "South Africa", "南非", "🇿🇦", "Africa/Johannesburg"),
    C("Cape Town", "开普敦", "South Africa", "南非", "🇿🇦", "Africa/Johannesburg"),
    C("Casablanca", "卡萨布兰卡", "Morocco", "摩洛哥", "🇲🇦", "Africa/Casablanca"),
    C("Algiers", "阿尔及尔", "Algeria", "阿尔及利亚", "🇩🇿", "Africa/Algiers"),
    C("Tunis", "突尼斯", "Tunisia", "突尼斯", "🇹🇳", "Africa/Tunis"),
    C("Addis Ababa", "亚的斯亚贝巴", "Ethiopia", "埃塞俄比亚", "🇪🇹", "Africa/Addis_Ababa"),
    C("Accra", "阿克拉", "Ghana", "加纳", "🇬🇭", "Africa/Accra"),
    C("Dakar", "达喀尔", "Senegal", "塞内加尔", "🇸🇳", "Africa/Dakar"),
    C("Kinshasa", "金沙萨", "DR Congo", "刚果(金)", "🇨🇩", "Africa/Kinshasa"),

    // Oceania
    C("Sydney", "悉尼", "Australia", "澳大利亚", "🇦🇺", "Australia/Sydney"),
    C("Melbourne", "墨尔本", "Australia", "澳大利亚", "🇦🇺", "Australia/Melbourne"),
    C("Brisbane", "布里斯班", "Australia", "澳大利亚", "🇦🇺", "Australia/Brisbane"),
    C("Perth", "珀斯", "Australia", "澳大利亚", "🇦🇺", "Australia/Perth"),
    C("Adelaide", "阿德莱德", "Australia", "澳大利亚", "🇦🇺", "Australia/Adelaide"),
    C("Canberra", "堪培拉", "Australia", "澳大利亚", "🇦🇺", "Australia/Sydney"),
    C("Hobart", "霍巴特", "Australia", "澳大利亚", "🇦🇺", "Australia/Hobart"),
    C("Darwin", "达尔文", "Australia", "澳大利亚", "🇦🇺", "Australia/Darwin"),
    C("Auckland", "奥克兰", "New Zealand", "新西兰", "🇳🇿", "Pacific/Auckland"),
    C("Wellington", "惠灵顿", "New Zealand", "新西兰", "🇳🇿", "Pacific/Auckland"),
    C("Christchurch", "基督城", "New Zealand", "新西兰", "🇳🇿", "Pacific/Auckland"),
    C("Queenstown", "皇后镇", "New Zealand", "新西兰", "🇳🇿", "Pacific/Auckland"),
    C("Suva", "苏瓦", "Fiji", "斐济", "🇫🇯", "Pacific/Fiji"),
    C("Guam", "关岛", "Guam", "关岛", "🇬🇺", "Pacific/Guam"),

    // Utility
    C("UTC", "协调世界时", "", "", "🌐", "UTC"),
]
