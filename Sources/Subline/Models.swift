import Foundation

enum BillingCycle: String, CaseIterable, Codable, Identifiable {
    case weekly
    case monthly
    case yearly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "주간"
        case .monthly: "월간"
        case .yearly: "연간"
        case .custom: "사용자 지정"
        }
    }

    var monthsPerCharge: Double {
        switch self {
        case .weekly: 12.0 / 52.0
        case .monthly: 1
        case .yearly: 12
        case .custom: 1
        }
    }

    var defaultAdvanceMonths: Int {
        switch self {
        case .weekly: 0
        case .monthly: 1
        case .yearly: 12
        case .custom: 1
        }
    }

    func date(after date: Date, customMonths: Int, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:
            calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            calendar.date(byAdding: .year, value: 1, to: date) ?? date
        case .custom:
            calendar.date(byAdding: .month, value: max(customMonths, 1), to: date) ?? date
        }
    }

    func date(before date: Date, customMonths: Int, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:
            calendar.date(byAdding: .day, value: -7, to: date) ?? date
        case .monthly:
            calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .yearly:
            calendar.date(byAdding: .year, value: -1, to: date) ?? date
        case .custom:
            calendar.date(byAdding: .month, value: -max(customMonths, 1), to: date) ?? date
        }
    }
}

enum BillingPeriodUnit: String, CaseIterable, Codable, Identifiable {
    case days
    case weeks
    case months
    case years

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days: "일"
        case .weeks: "주"
        case .months: "개월"
        case .years: "년"
        }
    }

    func date(after date: Date, value: Int, calendar: Calendar = .current) -> Date {
        switch self {
        case .days:
            calendar.date(byAdding: .day, value: max(value, 1), to: date) ?? date
        case .weeks:
            calendar.date(byAdding: .day, value: max(value, 1) * 7, to: date) ?? date
        case .months:
            calendar.date(byAdding: .month, value: max(value, 1), to: date) ?? date
        case .years:
            calendar.date(byAdding: .year, value: max(value, 1), to: date) ?? date
        }
    }

    var monthsPerUnit: Double {
        switch self {
        case .days: 12.0 / 365.2425
        case .weeks: 12.0 / 52.0
        case .months: 1
        case .years: 12
        }
    }
}

enum SubscriptionStatus: String, CaseIterable, Codable, Identifiable {
    case active
    case trial
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "사용 중"
        case .trial: "무료 체험"
        case .archived: "보관됨"
        }
    }
}

enum CurrencyCode: String, CaseIterable, Codable, Identifiable {
    case krw = "KRW"
    case usd = "USD"
    case jpy = "JPY"
    case eur = "EUR"
    case gbp = "GBP"

    var id: String { rawValue }
}

enum TrialDurationUnit: String, CaseIterable, Codable, Identifiable {
    case days
    case months
    case years

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days: "일"
        case .months: "개월"
        case .years: "년"
        }
    }

    func date(after date: Date, value: Int, calendar: Calendar = .current) -> Date {
        switch self {
        case .days:
            calendar.date(byAdding: .day, value: max(value, 1), to: date) ?? date
        case .months:
            calendar.date(byAdding: .month, value: max(value, 1), to: date) ?? date
        case .years:
            calendar.date(byAdding: .year, value: max(value, 1), to: date) ?? date
        }
    }
}

struct Subscription: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var amount: Decimal
    var currency: CurrencyCode
    var cycle: BillingCycle
    var customMonths: Int
    var billingPeriodValue: Int
    var billingPeriodUnit: BillingPeriodUnit
    var splitCount: Int
    var planStartDate: Date
    var trialStartDate: Date?
    var trialDurationValue: Int
    var trialDurationUnit: TrialDurationUnit
    var status: SubscriptionStatus
    var cancellationURL: String
    var notes: String
    var colorName: String
    var symbolName: String
    var symbolForeground: String

    init(
        id: UUID = UUID(),
        name: String,
        amount: Decimal,
        currency: CurrencyCode,
        cycle: BillingCycle,
        customMonths: Int = 1,
        billingPeriodValue: Int? = nil,
        billingPeriodUnit: BillingPeriodUnit? = nil,
        splitCount: Int = 1,
        planStartDate: Date,
        trialStartDate: Date? = nil,
        trialDurationValue: Int = 14,
        trialDurationUnit: TrialDurationUnit = .days,
        status: SubscriptionStatus = .active,
        cancellationURL: String = "",
        notes: String = "",
        colorName: String = "blue",
        symbolName: String = "repeat",
        symbolForeground: String = "white"
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.cycle = cycle
        self.customMonths = customMonths
        let migratedPeriod = Self.period(from: cycle, customMonths: customMonths)
        self.billingPeriodValue = billingPeriodValue ?? migratedPeriod.value
        self.billingPeriodUnit = billingPeriodUnit ?? migratedPeriod.unit
        self.splitCount = max(splitCount, 1)
        self.planStartDate = planStartDate
        self.trialStartDate = trialStartDate
        self.trialDurationValue = trialDurationValue
        self.trialDurationUnit = trialDurationUnit
        self.status = status
        self.cancellationURL = cancellationURL
        self.notes = notes
        self.colorName = colorName
        self.symbolName = symbolName
        self.symbolForeground = symbolForeground
    }

    var monthsPerCharge: Double {
        Double(max(billingPeriodValue, 1)) * billingPeriodUnit.monthsPerUnit
    }

    var monthlyEquivalent: Decimal {
        guard monthsPerCharge > 0 else { return amount }
        return amount / Decimal(monthsPerCharge)
    }

    var userAmount: Decimal { amount / Decimal(max(splitCount, 1)) }

    var userMonthlyEquivalent: Decimal { monthlyEquivalent / Decimal(max(splitCount, 1)) }

    var billingPeriodTitle: String {
        "\(max(billingPeriodValue, 1))\(billingPeriodUnit.title)마다"
    }

    var effectiveStatus: SubscriptionStatus {
        if status == .archived { return status }
        if let trialEnd = trialEndDate {
            return Date() <= trialEnd ? .trial : .active
        }
        return status == .trial ? .active : status
    }

    var nextChargeDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var candidate = calendar.startOfDay(for: effectiveFirstChargeDate)

        while candidate < today {
            candidate = billingPeriodUnit.date(after: candidate, value: billingPeriodValue, calendar: calendar)
        }

        return candidate
    }

    var effectiveFirstChargeDate: Date {
        guard let trialStartDate else { return planStartDate }
        return trialDurationUnit.date(after: trialStartDate, value: trialDurationValue)
    }

    var trialEndDate: Date? {
        guard let trialStartDate else { return nil }
        return trialDurationUnit.date(after: trialStartDate, value: trialDurationValue)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case currency
        case cycle
        case customMonths
        case billingPeriodValue
        case billingPeriodUnit
        case splitCount
        case planStartDate
        case firstChargeDate
        case lastChargeDate
        case nextChargeDate
        case trialStartDate
        case trialDurationValue
        case trialDurationUnit
        case trialEndDate
        case status
        case cancellationURL
        case notes
        case colorName
        case symbolName
        case symbolForeground
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Decimal.self, forKey: .amount)
        currency = try container.decode(CurrencyCode.self, forKey: .currency)
        cycle = try container.decode(BillingCycle.self, forKey: .cycle)
        customMonths = try container.decodeIfPresent(Int.self, forKey: .customMonths) ?? 1
        let migratedPeriod = Self.period(from: cycle, customMonths: customMonths)
        billingPeriodValue = try container.decodeIfPresent(Int.self, forKey: .billingPeriodValue) ?? migratedPeriod.value
        billingPeriodUnit = try container.decodeIfPresent(BillingPeriodUnit.self, forKey: .billingPeriodUnit) ?? migratedPeriod.unit
        splitCount = max(try container.decodeIfPresent(Int.self, forKey: .splitCount) ?? 1, 1)

        if let decodedPlanStartDate = try container.decodeIfPresent(Date.self, forKey: .planStartDate) {
            planStartDate = decodedPlanStartDate
        } else if let decodedFirstChargeDate = try container.decodeIfPresent(Date.self, forKey: .firstChargeDate) {
            planStartDate = decodedFirstChargeDate
        } else if let decodedLastChargeDate = try container.decodeIfPresent(Date.self, forKey: .lastChargeDate) {
            planStartDate = decodedLastChargeDate
        } else if let decodedNextChargeDate = try container.decodeIfPresent(Date.self, forKey: .nextChargeDate) {
            planStartDate = decodedNextChargeDate
        } else {
            planStartDate = Date()
        }

        trialStartDate = try container.decodeIfPresent(Date.self, forKey: .trialStartDate)
        trialDurationValue = try container.decodeIfPresent(Int.self, forKey: .trialDurationValue) ?? 14
        trialDurationUnit = try container.decodeIfPresent(TrialDurationUnit.self, forKey: .trialDurationUnit) ?? .days

        if trialStartDate == nil,
           let decodedTrialEndDate = try container.decodeIfPresent(Date.self, forKey: .trialEndDate) {
            trialStartDate = Calendar.current.date(byAdding: .day, value: -trialDurationValue, to: decodedTrialEndDate)
        }

        status = (try? container.decode(SubscriptionStatus.self, forKey: .status)) ?? .active
        cancellationURL = try container.decodeIfPresent(String.self, forKey: .cancellationURL) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? Self.suggestedColorName(for: name)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? Self.suggestedSymbolName(for: name)
        symbolForeground = try container.decodeIfPresent(String.self, forKey: .symbolForeground) ?? "white"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(currency, forKey: .currency)
        try container.encode(cycle, forKey: .cycle)
        try container.encode(customMonths, forKey: .customMonths)
        try container.encode(billingPeriodValue, forKey: .billingPeriodValue)
        try container.encode(billingPeriodUnit, forKey: .billingPeriodUnit)
        try container.encode(splitCount, forKey: .splitCount)
        try container.encode(planStartDate, forKey: .planStartDate)
        try container.encode(nextChargeDate, forKey: .nextChargeDate)
        try container.encodeIfPresent(trialStartDate, forKey: .trialStartDate)
        try container.encode(trialDurationValue, forKey: .trialDurationValue)
        try container.encode(trialDurationUnit, forKey: .trialDurationUnit)
        try container.encodeIfPresent(trialEndDate, forKey: .trialEndDate)
        try container.encode(status, forKey: .status)
        try container.encode(cancellationURL, forKey: .cancellationURL)
        try container.encode(notes, forKey: .notes)
        try container.encode(colorName, forKey: .colorName)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(symbolForeground, forKey: .symbolForeground)
    }

    static func period(from cycle: BillingCycle, customMonths: Int) -> (value: Int, unit: BillingPeriodUnit) {
        switch cycle {
        case .weekly:
            (1, .weeks)
        case .monthly:
            (1, .months)
        case .yearly:
            (1, .years)
        case .custom:
            (max(customMonths, 1), .months)
        }
    }

    static func suggestedSymbolName(for name: String) -> String {
        let n = name.lowercased()

        if n.contains("spotify") { return "headphones" }
        if n.contains("kakao") { return "bubble.left.and.right.fill" }
        if n.contains("배민") || n.contains("baemin") || n.contains("배달") { return "fork.knife" }
        if n.contains("claude") { return "sparkles" }
        if n.contains("openai") || n.contains("chatgpt") || n.contains("codex") { return "waveform" }
        if n.contains("1password") || n.contains("password") || n.contains("비밀번호") { return "key.fill" }
        if n.contains("todoist") || n.contains("todo") || n.contains("할일") { return "checklist" }
        if n.contains("setapp") { return "square.stack.3d.up.fill" }
        if n.contains("icloud") { return "icloud" }
        if n.contains("cloud") { return "cloud.fill" }
        if n.contains("gpt") || n.contains("chat") || n.contains("ai") { return "waveform" }
        if n.contains("figma") || n.contains("design") { return "paintpalette" }
        if n.contains("netflix") || n.contains("stream") || n.contains("watch") || n.contains("youtube") { return "play.tv" }
        if n.contains("music") { return "music.note" }
        if n.contains("terminal") || n.contains("cursor") || n.contains("xcode") { return "terminal.fill" }
        if n.contains("github") || n.contains("gitlab") { return "chevron.left.forwardslash.chevron.right" }
        if n.contains("dropbox") || n.contains("drive") { return "cloud.fill" }
        if n.contains("notion") || n.contains("obsidian") || n.contains("doc") { return "doc.fill" }
        if n.contains("discord") || n.contains("slack") || n.contains("teams") { return "bubble.left.and.right.fill" }
        if n.contains("game") || n.contains("steam") || n.contains("xbox") || n.contains("playstation") { return "gamecontroller" }
        if n.contains("news") || n.contains("medium") || n.contains("substack") { return "newspaper" }

        return "repeat"
    }

    static func suggestedColorName(for name: String) -> String {
        let n = name.lowercased()

        if n.contains("spotify") { return "green" }
        if n.contains("kakao") { return "yellow" }
        if n.contains("배민") || n.contains("baemin") { return "teal" }
        if n.contains("claude") { return "orange" }
        if n.contains("openai") || n.contains("chatgpt") || n.contains("codex") { return "teal" }
        if n.contains("1password") || n.contains("password") { return "blue" }
        if n.contains("todoist") { return "red" }
        if n.contains("setapp") { return "purple" }
        if n.contains("netflix") { return "red" }
        if n.contains("apple") || n.contains("icloud") { return "blue" }
        if n.contains("figma") { return "purple" }
        if n.contains("discord") { return "indigo" }
        if n.contains("slack") { return "purple" }
        if n.contains("notion") { return "gray" }
        if n.contains("github") { return "gray" }
        if n.contains("youtube") { return "red" }
        if n.contains("dropbox") { return "blue" }

        return "blue"
    }
}

struct ExchangeRates: Codable {
    var usd: Decimal = 1520
    var jpy: Decimal = 9.55
    var eur: Decimal = 1764
    var gbp: Decimal = 2043

    func krwValue(for amount: Decimal, currency: CurrencyCode) -> Decimal {
        switch currency {
        case .krw: amount
        case .usd: amount * usd
        case .jpy: amount * jpy
        case .eur: amount * eur
        case .gbp: amount * gbp
        }
    }
}

struct SubscriptionPreset: Identifiable {
    let id = UUID()
    let name: String
    let symbolName: String
    let colorName: String
    let amount: Decimal
    let currency: CurrencyCode
    let billingPeriodValue: Int
    let billingPeriodUnit: BillingPeriodUnit
    let category: String

    static let all: [SubscriptionPreset] = [
        .init(name: "Netflix",          symbolName: "play.tv",                                colorName: "red",    amount: 17000,  currency: .krw, billingPeriodValue: 1, billingPeriodUnit: .months, category: "스트리밍"),
        .init(name: "Spotify",          symbolName: "headphones",                             colorName: "green",  amount: 9.99,   currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "스트리밍"),
        .init(name: "Apple Music",      symbolName: "music.note",                             colorName: "red",    amount: 10900,  currency: .krw, billingPeriodValue: 1, billingPeriodUnit: .months, category: "스트리밍"),
        .init(name: "YouTube Premium",  symbolName: "play.rectangle.fill",                   colorName: "red",    amount: 14900,  currency: .krw, billingPeriodValue: 1, billingPeriodUnit: .months, category: "스트리밍"),
        .init(name: "Disney+",          symbolName: "star.fill",                              colorName: "blue",   amount: 9.99,   currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "스트리밍"),
        .init(name: "iCloud+",          symbolName: "icloud.fill",                            colorName: "blue",   amount: 3900,   currency: .krw, billingPeriodValue: 1, billingPeriodUnit: .months, category: "클라우드"),
        .init(name: "Google One",       symbolName: "cloud.fill",                             colorName: "blue",   amount: 2.99,   currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "클라우드"),
        .init(name: "Claude",           symbolName: "sparkles",                               colorName: "orange", amount: 20,     currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "AI"),
        .init(name: "ChatGPT Plus",     symbolName: "waveform",                               colorName: "teal",   amount: 20,     currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "AI"),
        .init(name: "Notion",           symbolName: "doc.fill",                               colorName: "gray",   amount: 8,      currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "생산성"),
        .init(name: "Todoist",          symbolName: "checklist",                              colorName: "red",    amount: 4,      currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "생산성"),
        .init(name: "1Password",        symbolName: "key.fill",                               colorName: "blue",   amount: 2.99,   currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "생산성"),
        .init(name: "GitHub Copilot",   symbolName: "chevron.left.forwardslash.chevron.right",colorName: "gray",   amount: 10,     currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "개발"),
        .init(name: "Figma",            symbolName: "paintpalette",                           colorName: "purple", amount: 15,     currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "개발"),
        .init(name: "Cursor",           symbolName: "terminal.fill",                          colorName: "gray",   amount: 20,     currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "개발"),
        .init(name: "Setapp",           symbolName: "square.stack.3d.up.fill",                colorName: "purple", amount: 9.99,   currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "개발"),
        .init(name: "Discord Nitro",    symbolName: "message.fill",                           colorName: "indigo", amount: 9.99,   currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "기타"),
        .init(name: "Xbox Game Pass",   symbolName: "gamecontroller",                         colorName: "green",  amount: 14.99,  currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "기타"),
        .init(name: "Duolingo Plus",    symbolName: "globe",                                  colorName: "green",  amount: 6.99,   currency: .usd, billingPeriodValue: 1, billingPeriodUnit: .months, category: "기타"),
    ]
}

enum SidebarFilter: String, CaseIterable, Identifiable {
    case all
    case thisMonth
    case trials
    case annual
    case foreign
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .thisMonth: "이번 달"
        case .trials: "무료 체험"
        case .annual: "연간 결제"
        case .foreign: "해외 결제"
        case .archived: "보관함"
        }
    }

    var symbol: String {
        switch self {
        case .all: "rectangle.stack"
        case .thisMonth: "calendar"
        case .trials: "clock.badge.exclamationmark"
        case .annual: "arrow.triangle.2.circlepath"
        case .foreign: "globe"
        case .archived: "archivebox"
        }
    }
}
